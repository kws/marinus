import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { toolchainEnv } from './toolchain-env.mjs';

const desktop = fileURLToPath(new URL('../', import.meta.url));
const notices = resolve(desktop, 'src-tauri/resources/notices');
function run(command, args) {
  const result = spawnSync(command, args, { cwd: desktop, env: toolchainEnv(), encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr);
  return result.stdout;
}
const host = run('rustc', ['--print', 'host-tuple']).trim();
const metadata = JSON.parse(run('cargo', ['metadata', '--locked', '--format-version', '1', '--filter-platform', host, '--manifest-path', 'src-tauri/Cargo.toml']));
const resolved = new Set(metadata.resolve.nodes.map(node => node.id));
const summary = [];
for (const pkg of metadata.packages.filter(pkg => pkg.source && resolved.has(pkg.id)).sort((a, b) => a.name.localeCompare(b.name))) {
  if (!pkg.license && !pkg.license_file) throw new Error(`Missing license metadata: ${pkg.name} ${pkg.version}`);
  const output = resolve(notices, 'rust-dependencies', `${pkg.name}-${pkg.version}`);
  mkdirSync(output, { recursive: true });
  const source = dirname(pkg.manifest_path);
  const files = readdirSync(source).filter(name => /^(licen[sc]e|copying|notice)([._-]|$)/i.test(name));
  for (const name of new Set(files)) {
    if (existsSync(resolve(source, name))) cpSync(resolve(source, name), resolve(output, name), { recursive: true });
  }
  if (pkg.license_file && existsSync(resolve(source, pkg.license_file))) {
    cpSync(resolve(source, pkg.license_file), resolve(output, basename(pkg.license_file)));
    files.push(basename(pkg.license_file));
  }
  const entry = { name: pkg.name, version: pkg.version, license: pkg.license, repository: pkg.repository, source: pkg.source, retained_files: [...new Set(files)] };
  writeFileSync(resolve(output, 'metadata.json'), JSON.stringify(entry, null, 2) + '\n');
  summary.push(entry);
}
const api = resolve(desktop, 'node_modules/@tauri-apps/api');
const apiOutput = resolve(notices, 'tauri-javascript-api');
mkdirSync(apiOutput, { recursive: true });
for (const name of readdirSync(api).filter(name => /^license/i.test(name))) cpSync(resolve(api, name), resolve(apiOutput, name));
writeFileSync(resolve(apiOutput, 'metadata.json'), readFileSync(resolve(api, 'package.json')));
writeFileSync(resolve(notices, 'desktop-dependencies.json'), JSON.stringify({ host, packages: summary }, null, 2) + '\n');
process.stdout.write(`Retained license metadata and supplied notices for ${summary.length} Rust packages and the frontend API.\n`);
