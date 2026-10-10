import { describe, expect, it } from 'vitest';
import { decodeInterfaces, decodeScan, signalFraction, signalLabel } from './protocol';
import mac from '../../contracts/draft/fixtures/macos-completed.json';
import linux from '../../contracts/draft/fixtures/linux-completed.json';
import denied from '../../contracts/draft/fixtures/permission-denied.json';

describe('backend protocol', () => {
  it('consumes different native units without inventing measurements', () => {
    const macRow = decodeScan(mac).observations[0];
    const linuxRow = decodeScan(linux).observations[0];
    expect(signalLabel(macRow)).toBe(`${macRow.rssi_dbm} dBm`);
    expect(signalLabel(linuxRow)).toBe(`${linuxRow.strength_percent}%`);
    expect(signalFraction(linuxRow)).toBe(linuxRow.strength_percent! / 100);
    expect(signalFraction({ ...macRow, rssi_dbm: -100 })).toBe(0);
    expect(signalFraction({ ...macRow, rssi_dbm: -30 })).toBe(1);
  });
  it('keeps failures structured and rejects cached fallback', () => {
    expect(decodeScan(denied).observations).toHaveLength(0);
    expect(() => decodeScan({ ...denied, observations: mac.observations })).toThrow('Invalid failed scan');
    expect(() => decodeScan({ ...mac, contract_version: '9.0.0' })).toThrow();
    expect(() => decodeScan({ ...mac, scan: { ...mac.scan, status: 'cached' }, observations: [{ ...mac.observations[0], freshness: 'fresh' }] })).toThrow();
  });
  it('enumerates stable platform-specific IDs', () => {
    const result = decodeInterfaces({ contract_version: '0.1.0', backend: mac.backend, error: null, interfaces: [{ id: 'en0', name: 'en0', driver: null, state: null }] });
    expect(result.interfaces[0].id).toBe('en0');
    expect(() => decodeInterfaces({ ...result, interfaces: [{ id: '', name: 'bad' }] })).toThrow();
  });
});
