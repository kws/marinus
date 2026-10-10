import { cpSync, mkdirSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../../', import.meta.url));
const resources = resolve(root, 'desktop/src-tauri/resources');
const backend = resolve(resources, 'backend');
function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status})`);
}
rmSync(backend, { recursive: true, force: true });
mkdirSync(backend, { recursive: true });
if (process.platform === 'darwin') {
  run('make', ['build-macos']);
  // Keep the complete privacy app, including its signature and bundle identity.
  run('/usr/bin/ditto', [resolve(root, 'backends/macos/dist/Marinus.app'), resolve(backend, 'Marinus.app')]);
} else if (process.platform === 'win32') {
  const runtime = process.arch === 'arm64' ? 'win-arm64' : 'win-x64';
  run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'backends/windows/scripts/build.ps1', '-Runtime', runtime]);
  cpSync(resolve(root, 'backends/windows/dist'), backend, { recursive: true });
} else if (process.platform === 'linux') {
  cpSync(resolve(root, 'backends/linux/wifi_scan.py'), resolve(backend, 'wifi_scan.py'));
} else {
  throw new Error(`Unsupported platform: ${process.platform}`);
}
mkdirSync(resolve(resources, 'notices'), { recursive: true });
for (const name of ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'licenses']) {
  cpSync(resolve(root, name), resolve(resources, 'notices', name), { recursive: true });
}
run(process.execPath, [resolve(root, 'desktop/scripts/collect-notices.mjs')]);
