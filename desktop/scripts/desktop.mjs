import { spawnSync } from 'node:child_process';
import { toolchainEnv } from './toolchain-env.mjs';
const command = process.argv[2];
if (!['dev', 'build'].includes(command)) throw new Error('Use desktop.mjs dev|build');
for (const args of [['scripts/prepare-backend.mjs'], ['node_modules/@tauri-apps/cli/tauri.js', command, ...process.argv.slice(3)]]) {
  const result = spawnSync(process.execPath, args, { stdio: 'inherit', env: toolchainEnv() });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
