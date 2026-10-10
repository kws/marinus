export type Backend = { platform: 'macos' | 'linux' | 'windows' | 'replay'; name: string; backend_version: string };
export type Failure = { code: string; message: string };
export type InterfaceList = {
  contract_version: '0.1.0'; backend: Backend;
  interfaces: { id: string; name: string; driver: string | null; state: string | null }[];
  error: Failure | null;
};
export type Observation = {
  ssid: string | null; ssid_bytes_base64: string | null; bssid: string | null;
  rssi_dbm: number | null; noise_dbm: number | null; strength_percent: number | null;
  frequency_mhz: number | null; channel_width_mhz: number | null; connected: boolean | null;
  freshness: 'fresh' | 'cached' | 'unknown'; last_seen_age_ms: number | null;
};
export type ScanResult = {
  contract_version: '0.1.0'; backend: Backend;
  interface: { id: string; driver: string | null };
  capabilities: { rssi_dbm: boolean; strength_percent: boolean; noise_dbm: boolean; channel_width_mhz: boolean; last_seen_resolution_ms: number | null };
  scan: { status: 'completed' | 'cached' | 'failed'; started_at: string; completed_at: string | null; error: Failure | null };
  observations: Observation[];
};

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid backend response.');
  return value as Record<string, unknown>;
}
function envelope(value: unknown) {
  const result = object(value);
  if (result.contract_version !== '0.1.0') throw new Error('Unsupported backend contract.');
  const backend = object(result.backend);
  if (!['macos', 'linux', 'windows', 'replay'].includes(String(backend.platform))) throw new Error('Unknown backend platform.');
  return result;
}
export function decodeInterfaces(value: unknown): InterfaceList {
  const result = envelope(value);
  if (!Array.isArray(result.interfaces) || !result.interfaces.every(item => {
    const row = object(item);
    return typeof row.id === 'string' && row.id.length > 0 && typeof row.name === 'string';
  })) throw new Error('Invalid Wi-Fi interface list.');
  if (result.error !== null && typeof object(result.error).message !== 'string') throw new Error('Invalid backend error.');
  return value as InterfaceList;
}
export function decodeScan(value: unknown): ScanResult {
  const result = envelope(value);
  const scan = object(result.scan);
  if (!['completed', 'cached', 'failed'].includes(String(scan.status)) || typeof object(result.interface).id !== 'string'
    || !Array.isArray(result.observations)) throw new Error('Invalid scan result.');
  if (scan.status === 'failed') {
    if (typeof object(scan.error).message !== 'string' || result.observations.length !== 0) throw new Error('Invalid failed scan.');
  } else if (scan.error !== null || typeof scan.completed_at !== 'string') throw new Error('Incomplete scan result.');
  for (const item of result.observations) {
    const row = object(item);
    for (const field of ['rssi_dbm', 'noise_dbm', 'strength_percent', 'frequency_mhz', 'channel_width_mhz', 'last_seen_age_ms']) {
      if (row[field] !== null && (typeof row[field] !== 'number' || !Number.isFinite(row[field]))) throw new Error(`Invalid ${field}.`);
    }
    if (typeof row.rssi_dbm === 'number' && row.rssi_dbm > 0) throw new Error('Invalid RSSI.');
    if (typeof row.strength_percent === 'number' && (row.strength_percent < 0 || row.strength_percent > 100)) throw new Error('Invalid signal percentage.');
    for (const field of ['frequency_mhz', 'channel_width_mhz']) {
      if (row[field] !== null && (!Number.isInteger(row[field]) || (row[field] as number) <= 0)) throw new Error(`Invalid ${field}.`);
    }
    if (!['fresh', 'cached', 'unknown'].includes(String(row.freshness)) || (scan.status === 'cached' && row.freshness === 'fresh')) throw new Error('Invalid observation freshness.');
    if (row.ssid !== null && typeof row.ssid !== 'string') throw new Error('Invalid network name.');
    if (row.bssid !== null && (typeof row.bssid !== 'string' || !/^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/.test(row.bssid))) throw new Error('Invalid BSSID.');
  }
  return value as ScanResult;
}
export function signalLabel(row: Observation): string {
  if (row.rssi_dbm !== null) return `${row.rssi_dbm} dBm`;
  if (row.strength_percent !== null) return `${row.strength_percent}%`;
  return 'Unavailable';
}
export function signalFraction(row: Observation): number | null {
  // Fixed display scales. Never normalize against the strongest AP in a scan.
  if (row.rssi_dbm !== null) return Math.max(0, Math.min(1, (row.rssi_dbm + 100) / 70));
  if (row.strength_percent !== null) return row.strength_percent / 100;
  return null;
}
