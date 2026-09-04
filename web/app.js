const $ = (id) => document.getElementById(id);

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
    const r = await fetch('/proxy-api/status', {cache: 'no-store'});
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const data = await r.json();
    render(data);
    $('message').textContent = 'Status updated.';
  } catch (e) {
    $('message').textContent = `Proxy API unavailable: ${e.message}`;
  }
}

async function action(name) {
  $('message').textContent = `${name}…`;
  try {
    const r = await fetch(`/proxy-api/${name}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: '{}'
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
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
