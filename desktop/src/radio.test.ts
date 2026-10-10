import { describe, expect, it } from 'vitest';
import { decodeScan } from './protocol';
import { advertisedWidth, radioChannel } from './radio';
import mac from '../../contracts/draft/fixtures/macos-completed.json';
import linux from '../../contracts/draft/fixtures/linux-completed.json';

describe('advertised radio configuration', () => {
  it.each([
    [2412, '2.4 GHz', '1'], [2437, '2.4 GHz', '6'], [2472, '2.4 GHz', '13'],
    [2484, '2.4 GHz', '14'], [4910, '5 GHz', '182'], [4980, '5 GHz', '196'],
    [5180, '5 GHz', '36'], [5745, '5 GHz', '149'], [5885, '5 GHz', '177'],
    [5935, '6 GHz', '2'], [5955, '6 GHz', '1'], [5975, '6 GHz', '5'],
    [7115, '6 GHz', '233'],
  ])('maps %i MHz to %s channel %s', (frequency, band, channel) => {
    expect(radioChannel(frequency as number)).toEqual({ band, channel });
  });

  it('retains unknown and unrecognized frequencies without rounding to a channel', () => {
    for (const frequency of [null, 0, 2400, 2413, 2485, 5000, 5940, 7116, 10000]) {
      expect(radioChannel(frequency)).toEqual({ band: 'Unknown', channel: 'Unknown' });
    }
  });

  it('shows each BSSID’s own width and keeps the primary channel independent of width', () => {
    const row = decodeScan(mac).observations[0];
    const observations = [
      { ...row, bssid: '02:00:00:00:00:01', frequency_mhz: 5180, channel_width_mhz: 80 },
      { ...row, bssid: '02:00:00:00:00:02', frequency_mhz: 5180, channel_width_mhz: 20 },
      { ...row, bssid: '02:00:00:00:00:03', frequency_mhz: 5975, channel_width_mhz: 320 },
    ];
    expect(observations.map(advertisedWidth)).toEqual(['80 MHz', '20 MHz', '320 MHz']);
    expect(observations.map(item => radioChannel(item.frequency_mhz).channel)).toEqual(['36', '36', '5']);
    expect(advertisedWidth(decodeScan(linux).observations[0])).toBe('Unknown');
    expect(advertisedWidth({ ...row, channel_width_mhz: null })).toBe('Unknown');
  });

  it('rejects zero, negative and fractional radio measurements in backend responses', () => {
    for (const field of ['frequency_mhz', 'channel_width_mhz']) {
      for (const value of [0, -20, 20.5]) {
        expect(() => decodeScan({ ...mac, observations: [{ ...mac.observations[0], [field]: value }] })).toThrow(`Invalid ${field}`);
      }
    }
  });
});
