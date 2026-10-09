import { cpSync, mkdtempSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { toolchainEnv } from './toolchain-env.mjs';

const desktop = fileURLToPath(new URL('../', import.meta.url));
const development = process.argv.slice(2).includes('--development');
const temporary = mkdtempSync(resolve(tmpdir(), 'marinus-release-'));
const env = toolchainEnv();
function required(name) {
  if (!env[name] || env[name] === '-') throw new Error(`Set ${name}, or use --development for a local test build.`);
  return env[name];
}
function run(command, args, capture = false) {
  const result = spawnSync(command, args, { cwd: desktop, env, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status})${capture ? `: ${result.stderr}` : ''}`);
  return result.stdout;
}
function notarize(path) {
  const report = JSON.parse(run('xcrun', ['notarytool', 'submit', path, '--keychain-profile', env.NOTARY_PROFILE, '--wait', '--output-format', 'json'], true));
  if (report.status !== 'Accepted') throw new Error('Notarization was not accepted.');
}
function notarizeApp(app, archiveName) {
  const archive = resolve(temporary, archiveName);
  run('ditto', ['-c', '-k', '--keepParent', app, archive]);
  notarize(archive);
  run('xcrun', ['stapler', 'staple', app]); run('xcrun', ['stapler', 'validate', app]);
}
try {
  if (!development && process.platform === 'darwin') {
    env.SIGN_IDENTITY = required('SIGN_IDENTITY');
    env.APPLE_SIGNING_IDENTITY = env.SIGN_IDENTITY;
    required('NOTARY_PROFILE');
  }
  if (!development && process.platform === 'win32') { required('WINDOWS_SIGN_THUMBPRINT'); required('WINDOWS_TIMESTAMP_URL'); }
  if (development && process.platform === 'darwin') {
    env.SIGN_IDENTITY = '-'; env.APPLE_SIGNING_IDENTITY = '-';
    for (const name of ['APPLE_ID', 'APPLE_PASSWORD', 'APPLE_TEAM_ID', 'APPLE_API_KEY', 'APPLE_API_ISSUER', 'APPLE_API_KEY_PATH']) delete env[name];
  }
  run(process.execPath, ['scripts/prepare-backend.mjs']);
  if (!development && process.platform === 'darwin') {
    // Staple the helper before sealing the parent app's resources.
    notarizeApp(resolve(desktop, 'src-tauri/resources/backend/Marinus.app'), 'scanner.zip');
  }
  let extra = [];
  if (process.platform === 'win32' && !development) {
    run('signtool', ['sign', '/sha1', env.WINDOWS_SIGN_THUMBPRINT, '/fd', 'SHA256', '/tr', env.WINDOWS_TIMESTAMP_URL, '/td', 'SHA256', 'src-tauri/resources/backend/marinus.exe']);
    run('signtool', ['verify', '/pa', 'src-tauri/resources/backend/marinus.exe']);
    const config = resolve(temporary, 'signing.json');
    writeFileSync(config, JSON.stringify({ bundle: { windows: { certificateThumbprint: env.WINDOWS_SIGN_THUMBPRINT, timestampUrl: env.WINDOWS_TIMESTAMP_URL, digestAlgorithm: 'sha256', tsp: true } } }));
    extra = ['--config', config];
  }
  const cli = resolve(desktop, 'node_modules/@tauri-apps/cli/tauri.js');
  run(process.execPath, [cli, 'build', ...(process.platform === 'darwin' ? ['--bundles', 'app'] : []), ...extra]);
  const bundle = resolve(desktop, 'src-tauri/target/release/bundle');
  if (process.platform === 'darwin') {
    const app = resolve(bundle, 'macos/Marinus Desktop.app');
    run('codesign', ['--verify', '--deep', '--strict', app]);
    // Nested scanner retains io.github.kws.marinus and its LaunchServices permission identity.
    run('codesign', ['--verify', '--strict', resolve(app, 'Contents/Resources/backend/Marinus.app')]);
    if (!development) notarizeApp(app, 'desktop.zip');
    const staging = resolve(temporary, 'disk');
    cpSync(app, resolve(staging, 'Marinus Desktop.app'), { recursive: true });
    symlinkSync('/Applications', resolve(staging, 'Applications'));
    const output = resolve(bundle, `Marinus-Desktop-0.1.0-${process.arch}${development ? '-development' : ''}.dmg`);
    run('hdiutil', ['create', '-volname', 'Marinus Desktop', '-srcfolder', staging, '-ov', '-format', 'UDZO', output]);
    if (!development) {
      run('codesign', ['--force', '--sign', env.SIGN_IDENTITY, '--timestamp', output]);
      notarize(output);
      run('xcrun', ['stapler', 'staple', output]); run('xcrun', ['stapler', 'validate', output]);
    }
    process.stdout.write(`Created ${output}\n`);
  } else if (process.platform === 'win32' && !development) {
    for (const file of readdirSync(resolve(bundle, 'nsis')).filter(name => name.endsWith('.exe'))) run('signtool', ['verify', '/pa', resolve(bundle, 'nsis', file)]);
  }
} finally { rmSync(temporary, { recursive: true, force: true }); }
