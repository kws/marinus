import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { delimiter, resolve } from 'node:path';
export function toolchainEnv() {
  const env = { ...process.env };
  const cargoBin = resolve(env.CARGO_HOME || resolve(homedir(), '.cargo'), 'bin');
  if (existsSync(resolve(cargoBin, process.platform === 'win32' ? 'cargo.exe' : 'cargo'))) {
    env.PATH = `${cargoBin}${delimiter}${env.PATH || env.Path || ''}`;
    if (process.platform === 'win32') delete env.Path;
  }
  return env;
}
