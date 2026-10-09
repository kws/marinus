import { invoke, isTauri } from '@tauri-apps/api/core';
import { decodeInterfaces, decodeScan, signalFraction, signalLabel, type InterfaceList, type ScanResult } from './protocol';
import demoCapture from '../../contracts/draft/fixtures/macos-completed.json';
import './style.css';

const native = isTauri();
let demo = !native;
let busy = false;
let result: ScanResult | null = null;
let interfaces: InterfaceList | null = null;
let filter = '';
const app = document.querySelector<HTMLDivElement>('#app')!;
app.innerHTML = `
  <header class="toolbar" aria-label="Scan controls">
    <div class="adapter"><label for="interface">Interface</label><select id="interface" aria-label="Wi-Fi interface"></select><button id="refresh" title="Refresh interfaces" aria-label="Refresh interfaces">↻</button></div>
    <div class="toolbar-divider" aria-hidden="true"></div>
    <button id="scan" class="primary">Scan</button>
    <button id="cached">Read cache</button>
    <button id="cancel" hidden>Cancel</button>
    <div class="spacer"></div>
    <button id="export" disabled>Export JSON…</button>
  </header>
  <main class="workspace">
    <div class="table-toolbar">
      <input id="filter" type="search" placeholder="Filter network or BSSID" aria-label="Filter networks">
      <span id="results-description" class="result-count"></span>
      <div class="spacer"></div>
      <label class="demo-switch"><input id="demo" type="checkbox">Synthetic demo</label>
    </div>
    <div class="table-wrap" tabindex="0" role="region" aria-label="Nearby networks">
      <table aria-label="Access point observations">
        <colgroup><col class="network-column"><col class="bssid-column"><col class="signal-column"><col class="frequency-column"><col class="link-column"><col class="freshness-column"></colgroup>
        <thead><tr><th scope="col">Network</th><th scope="col">BSSID</th><th scope="col">Signal</th><th scope="col">Frequency</th><th scope="col">Link</th><th scope="col">Freshness</th></tr></thead>
        <tbody id="networks"></tbody>
      </table>
      <div id="empty" class="empty">Select an interface, then click Scan.</div>
    </div>
  </main>
  <footer class="statusbar">
    <span id="status" role="status" aria-live="polite"></span>
    <span id="strongest" hidden></span>
    <time id="scan-time" hidden></time>
  </footer>`;

function element<T extends HTMLElement = HTMLElement>(id: string): T { return document.getElementById(id) as T; }
const selector = element<HTMLSelectElement>('interface');
function status(message: string, error = false) {
  const node = element('status'); node.textContent = message; node.title = message; node.classList.toggle('error', error);
}
function setBusy(value: boolean) {
  busy = value;
  for (const id of ['scan', 'cached', 'refresh', 'interface', 'demo']) (element(id) as HTMLButtonElement).disabled = value;
  element('cancel').hidden = !value;
  element('scan').textContent = value ? 'Working…' : 'Scan';
  element<HTMLButtonElement>('export').disabled = value || !result;
}
async function refresh() {
  result = null; render(); setBusy(true);
  status(demo ? 'Synthetic demo. No radio scan.' : 'Finding Wi-Fi interfaces…');
  element<HTMLInputElement>('demo').checked = demo;
  try {
    const previous = selector.value;
    interfaces = demo ? decodeInterfaces({ contract_version: '0.1.0', backend: { platform: 'replay', name: 'synthetic-demo', backend_version: '0.1.0' }, interfaces: [{ id: 'demo0', name: 'Demo Wi-Fi adapter', driver: null, state: null }], error: null }) : decodeInterfaces(await invoke('backend_interfaces'));
    selector.replaceChildren(...interfaces.interfaces.map(item => {
      const option = document.createElement('option'); option.value = item.id; option.textContent = item.name === item.id ? item.id : `${item.name} · ${item.id}`; return option;
    }));
    if (interfaces.interfaces.some(item => item.id === previous)) selector.value = previous;
    if (interfaces.error) throw new Error(interfaces.error.message);
    if (!interfaces.interfaces.length) status('No Wi-Fi interfaces found. Enable an adapter, then refresh.', true);
    else if (!demo) status('Ready');
  } catch (error) { status(String(error instanceof Error ? error.message : error), true); }
  finally { setBusy(false); }
}
async function scan(cached: boolean) {
  if (busy || !selector.value) return;
  setBusy(true); result = null; render();
  status(cached ? 'Reading the existing cache…' : 'Requesting a scan. Check for a location permission dialog.');
  try {
    if (demo) {
      const value = structuredClone(demoCapture);
      value.backend = { platform: 'replay', name: 'synthetic-demo', backend_version: '0.1.0' };
      value.interface.id = 'demo0';
      if (cached) { value.scan.status = 'cached'; value.observations.forEach(row => { row.freshness = 'unknown'; }); }
      result = decodeScan(value);
    } else result = decodeScan(await invoke('backend_scan', { interface: selector.value, cached }));
    if (result.scan.error) status(`${result.scan.error.code}: ${result.scan.error.message}`, true);
    else status(demo ? 'Synthetic demo loaded · fixture measurements and timestamps' : cached ? 'Cache read' : 'Scan completed');
  } catch (error) { status(String(error instanceof Error ? error.message : error), true); }
  finally { setBusy(false); render(); }
}
function render() {
  const rows = result?.observations ?? [];
  const strongest = [...rows].sort((a, b) => (signalFraction(b) ?? -1) - (signalFraction(a) ?? -1))[0];
  element('strongest').textContent = strongest ? `Strongest: ${signalLabel(strongest)}` : '';
  element('strongest').hidden = !strongest;
  const scanTime = element<HTMLTimeElement>('scan-time');
  scanTime.hidden = !result;
  scanTime.dateTime = result ? result.scan.completed_at ?? result.scan.started_at : '';
  scanTime.textContent = result ? `${demo ? 'Fixture · ' : ''}${new Date(scanTime.dateTime).toLocaleString()}` : '';
  element<HTMLButtonElement>('export').disabled = busy || !result;
  const visible = rows.filter(row => `${row.ssid ?? ''} ${row.bssid ?? ''}`.toLocaleLowerCase().includes(filter.toLocaleLowerCase()));
  const count = element('results-description');
  count.textContent = result ? `${filter ? `${visible.length} of ${rows.length}` : rows.length} access point${rows.length === 1 ? '' : 's'}` : '';
  count.title = result ? `${result.backend.platform} · ${result.interface.id} · ${result.scan.status} · ${scanTime.textContent}` : '';
  const body = element('networks'); body.replaceChildren();
  for (const row of visible) {
    const tr = document.createElement('tr');
    const name = document.createElement('td');
    name.textContent = row.ssid === null ? '(unavailable)' : row.ssid || '(hidden network)'; name.title = name.textContent;
    const bssid = document.createElement('td'); bssid.className = 'bssid'; bssid.textContent = row.bssid ?? 'Unavailable';
    const signal = document.createElement('td'); const measurement = document.createElement('div'); measurement.className = 'signal'; const label = document.createElement('span'); label.textContent = signalLabel(row);
    const bar = document.createElement('span'); bar.className = 'signal-bar'; bar.setAttribute('aria-hidden', 'true'); const fill = document.createElement('i'); fill.style.width = `${(signalFraction(row) ?? 0) * 100}%`; bar.append(fill); measurement.append(bar, label); signal.append(measurement);
    const frequency = document.createElement('td'); frequency.textContent = row.frequency_mhz === null ? 'Unknown' : `${row.frequency_mhz} MHz`;
    const link = document.createElement('td'); link.textContent = row.connected === null ? 'Unknown' : row.connected ? 'Connected' : '—';
    const freshness = document.createElement('td'); freshness.className = `freshness ${row.freshness}`; freshness.textContent = row.freshness;
    tr.append(name, bssid, signal, frequency, link, freshness); body.append(tr);
  }
  const empty = element('empty'); empty.hidden = visible.length > 0;
  empty.textContent = busy ? 'Working…' : result ? result.scan.status === 'failed' ? 'Scan failed. See the status bar for details.' : filter ? 'No matching networks.' : 'No access points returned.' : 'Select an interface, then click Scan.';
}
element('scan').addEventListener('click', () => void scan(false));
element('cached').addEventListener('click', () => void scan(true));
element('refresh').addEventListener('click', () => void refresh());
element('cancel').addEventListener('click', () => { if (native) void invoke('cancel_scan').catch(error => status(String(error), true)); });
element<HTMLInputElement>('filter').addEventListener('input', event => { filter = (event.target as HTMLInputElement).value; render(); });
selector.addEventListener('change', () => { result = null; render(); });
element<HTMLInputElement>('demo').addEventListener('change', async event => {
  demo = (event.target as HTMLInputElement).checked;
  if (!native && !demo) { demo = true; status('Live scans require the desktop application. This browser preview uses synthetic data.'); element<HTMLInputElement>('demo').checked = true; return; }
  await refresh();
});
element('export').addEventListener('click', async () => {
  if (!result) return;
  const filename = demo ? 'marinus-synthetic-demo.json' : `marinus-scan-${Date.now()}.json`;
  if (native) {
    try {
      const saved = await invoke<boolean>('save_capture', { value: result, filename });
      if (saved) status('Capture saved.');
    } catch (error) { status(String(error), true); }
    return;
  }
  const url = URL.createObjectURL(new Blob([JSON.stringify(result, null, 2) + '\n'], { type: 'application/json' }));
  const anchor = document.createElement('a'); anchor.href = url; anchor.download = filename; anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
void refresh();
