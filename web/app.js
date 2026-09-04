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
  $('trafficMode').textContent = data.traffic_mode ?? 'off';
  $('wan').textContent = data.wan ?? 'rmnet_data0';
  $('lan').textContent = data.lan ?? 'br-lan';
  const badge = $('stateBadge');
  const state = data.state ?? 'unknown';
  badge.textContent = state;
  badge.dataset.state = state;
}

async function apiPost(path) {
  const token = getToken();
  if (!token) throw new Error('Control token required');
  const r = await fetch(`${API}${path}`, {
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
  return r.json();
}

async function refresh() {
  $('message').textContent = 'Refreshing…';
  try {
    const r = await fetch(`${API}/status`, {cache: 'no-store'});
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    render(await r.json());
    $('message').textContent = 'Status updated.';
  } catch (e) {
    $('message').textContent = `Proxy API unavailable: ${e.message}`;
  }
}

async function action(name) {
  $('message').textContent = `${name}…`;
  try {
    await apiPost(`/${name}`);
    await refresh();
    await refreshClients();
  } catch (e) {
    $('message').textContent = `Action failed: ${e.message}`;
  }
}

async function traffic(actionName) {
  $('message').textContent = `traffic ${actionName}…`;
  try {
    await apiPost(`/traffic?action=${encodeURIComponent(actionName)}`);
    await refresh();
    await refreshClients();
  } catch (e) {
    $('message').textContent = `Traffic action failed: ${e.message}`;
  }
}

async function setDevice(mac, actionName) {
  $('message').textContent = `${mac} => ${actionName}…`;
  try {
    await apiPost(`/device?selector=${encodeURIComponent(mac)}&action=${encodeURIComponent(actionName)}`);
    await refresh();
    await refreshClients();
  } catch (e) {
    $('message').textContent = `Device action failed: ${e.message}`;
  }
}

async function refreshClients() {
  const box = $('clients');
  try {
    const r = await fetch(`${API}/clients`, {cache: 'no-store'});
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const data = await r.json();
    const clients = data.clients || [];
    if (!clients.length) {
      box.innerHTML = '<p class="message">No connected IPv4 clients found.</p>';
      return;
    }
    box.innerHTML = '';
    for (const c of clients) {
      const row = document.createElement('div');
      row.className = 'client-row';
      const info = document.createElement('div');
      info.className = 'client-info';
      info.innerHTML = `<strong>${c.ip}</strong><span>${c.mac}</span><small>${c.state}</small>`;
      const actions = document.createElement('div');
      actions.className = 'actions';
      const proxy = document.createElement('button');
      proxy.textContent = 'Proxy';
      proxy.addEventListener('click', () => setDevice(c.mac, 'proxy'));
      const direct = document.createElement('button');
      direct.textContent = 'Direct';
      direct.addEventListener('click', () => setDevice(c.mac, 'direct'));
      actions.append(proxy, direct);
      row.append(info, actions);
      box.appendChild(row);
    }
  } catch (e) {
    box.innerHTML = `<p class="message">Device list unavailable: ${e.message}</p>`;
  }
}

document.querySelectorAll('[data-action]').forEach((b) => {
  b.addEventListener('click', () => action(b.dataset.action));
});
document.querySelectorAll('[data-traffic]').forEach((b) => {
  b.addEventListener('click', () => traffic(b.dataset.traffic));
});
$('refresh').addEventListener('click', refresh);
$('refreshClients').addEventListener('click', refreshClients);
refresh();
refreshClients();
