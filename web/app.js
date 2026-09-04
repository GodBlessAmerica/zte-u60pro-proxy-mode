const $ = (id) => document.getElementById(id);
const API = '/cgi-bin/proxy-api';

function getToken() {
  let token = localStorage.getItem('u60ProxyToken') || '';
  if (!token) {
    token = prompt('Enter the U60 Pro Proxy Mode web token:') || '';
    if (token) localStorage.setItem('u60ProxyToken', token);
  }
  return token;
}

function render(data) {
  $('mode').textContent = data.mode ?? '—';
  $('wan').textContent = data.wan ?? 'rmnet_data0';
  $('lan').textContent = data.lan ?? 'br-lan';
  $('pid').textContent = data.pid ?? '—';
  const badge = $('stateBadge');
  const state = data.state ?? 'unknown';
  badge.textContent = state;
  badge.dataset.state = state;
}

async function refresh() {
  $('message').textContent = 'Refreshing…';
  try {
    const r = await fetch(`${API}/status`, {cache: 'no-store'});
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const data = await r.json();
    render(data);
    $('message').textContent = 'Status updated.';
  } catch (e) {
    $('message').textContent = `Proxy API unavailable: ${e.message}`;
  }
}

async function action(name) {
  const token = getToken();
  if (!token) {
    $('message').textContent = 'Control token required.';
    return;
  }
  $('message').textContent = `${name}…`;
  try {
    const r = await fetch(`${API}/${name}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Proxy-Token': token
      },
      body: '{}'
    });
    if (!r.ok) {
      if (r.status === 403) localStorage.removeItem('u60ProxyToken');
      throw new Error(`HTTP ${r.status}`);
    }
    await refresh();
  } catch (e) {
    $('message').textContent = `Action failed: ${e.message}`;
  }
}

document.querySelectorAll('[data-action]').forEach((b) => {
  b.addEventListener('click', () => action(b.dataset.action));
});
$('refresh').addEventListener('click', refresh);
refresh();
