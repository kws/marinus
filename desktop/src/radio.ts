import type { Observation } from './protocol';

export function radioChannel(frequency: number | null): { band: string; channel: string } {
  let band = 'Unknown';
  let channel: number | null = null;
  if (frequency !== null && Number.isInteger(frequency)) {
    if (frequency === 2484) { band = '2.4 GHz'; channel = 14; }
    else if (frequency >= 2412 && frequency <= 2472 && (frequency - 2407) % 5 === 0) {
      band = '2.4 GHz'; channel = (frequency - 2407) / 5;
    } else if (frequency >= 4910 && frequency <= 4980 && (frequency - 4000) % 5 === 0) {
      // The Japanese 4.9 GHz channels belong to CoreWLAN's 5 GHz band.
      band = '5 GHz'; channel = (frequency - 4000) / 5;
    } else if (frequency >= 5035 && frequency <= 5895 && (frequency - 5000) % 5 === 0) {
      band = '5 GHz'; channel = (frequency - 5000) / 5;
    } else if (frequency === 5935) { band = '6 GHz'; channel = 2; }
    else if (frequency >= 5955 && frequency <= 7115 && (frequency - 5950) % 5 === 0) {
      band = '6 GHz'; channel = (frequency - 5950) / 5;
    }
  }
  return { band, channel: channel === null ? 'Unknown' : String(channel) };
}

export function advertisedWidth(row: Observation): string {
  const width = row.channel_width_mhz;
  return width !== null && Number.isInteger(width) && width > 0 ? `${width} MHz` : 'Unknown';
}
