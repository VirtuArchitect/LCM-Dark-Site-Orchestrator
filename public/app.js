const modeCard = document.querySelector('#mode-card');
const segments = document.querySelectorAll('.segment');
const siteName = document.querySelector('#site-name');
const darksiteUrl = document.querySelector('#darksite-url');
const bundlePath = document.querySelector('#bundle-path');
const saveProfileButton = document.querySelector('#save-profile-button');
const scanButton = document.querySelector('#scan-button');
const refreshButton = document.querySelector('#refresh-button');
const profileMessage = document.querySelector('#profile-message');
const statusText = document.querySelector('#status-text');
const detectedCount = document.querySelector('#detected-count');
const detectedHint = document.querySelector('#detected-hint');
const webServerMode = document.querySelector('#web-server-mode');
const webServerHint = document.querySelector('#web-server-hint');
const lastValidation = document.querySelector('#last-validation');
const lastValidationHint = document.querySelector('#last-validation-hint');
const inventoryBadge = document.querySelector('#inventory-badge');
const inventoryList = document.querySelector('#inventory-list');
const issueList = document.querySelector('#issue-list');

const modes = {
  linux: {
    title: 'Linux web server',
    body: 'Recommended path. Validate nginx or Apache static hosting, permissions, firewall, and the extracted /darksite/ folder.',
  },
  windows: {
    title: 'Windows / IIS web server',
    body: 'Lab or customer-managed path. Validate IIS static downloads, MIME handling, file reachability, and show an explicit unsupported-by-guide warning.',
  },
};

let currentMode = 'linux';
let lastInventory = { status: 'not_scanned', checks: [] };

function setMessage(message, tone = 'muted') {
  profileMessage.textContent = message;
  profileMessage.dataset.tone = tone;
}

function selectedProfile() {
  return {
    siteName: siteName.value.trim(),
    webServerPlatform: currentMode,
    bundlePath: bundlePath.value.trim(),
    darksiteUrl: darksiteUrl.value.trim(),
  };
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
    ...options,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || `Request failed: ${response.status}`);
  }
  return data;
}

function formatDate(value) {
  if (!value) return 'Never';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Never';
  return date.toLocaleString();
}

function renderProfile(profile) {
  if (!profile) return;
  siteName.value = profile.siteName || '';
  darksiteUrl.value = profile.darksiteUrl || '';
  bundlePath.value = profile.bundlePath || '';
  const mode = profile.webServerPlatform || 'linux';
  const button = Array.from(segments).find((item) => item.dataset.mode === mode);
  if (button) button.click();
}

function renderInventory(inventory) {
  lastInventory = inventory || { status: 'not_scanned', checks: [] };
  const checks = inventory?.checks || [];
  const found = Number(inventory?.detectedCount || 0);
  const missing = Number(inventory?.missingCount || 0);

  detectedCount.textContent = String(found);
  detectedHint.textContent = inventory?.status === 'not_scanned'
    ? 'Run inventory to populate'
    : `${missing} missing of ${inventory.requiredCount || 5} required`;
  lastValidation.textContent = inventory?.scannedAt ? new Date(inventory.scannedAt).toLocaleDateString() : 'Never';
  lastValidationHint.textContent = inventory?.scannedAt ? formatDate(inventory.scannedAt) : 'No evidence recorded';

  inventoryBadge.textContent = inventory?.status === 'ready' ? 'Ready' : inventory?.status === 'blocked' ? 'Blocked' : 'Pending';
  inventoryBadge.className = `badge ${inventory?.status === 'ready' ? 'success' : inventory?.status === 'blocked' ? 'danger' : 'warn'}`;

  if (checks.length) {
    inventoryList.innerHTML = checks.map((check) => `
      <div class="check-row ${check.status === 'found' ? 'good' : 'bad'}">
        <span></span>
        <div>
          <strong>${check.label}</strong>
          <small>${check.status === 'found' ? `${check.count} found${check.latest?.version ? ` · v${check.latest.version}` : ''}` : `Missing · ${check.pattern}`}</small>
        </div>
      </div>
    `).join('');
  }

  const issues = [];
  if (!siteName.value.trim()) issues.push('No dark-site profile name has been saved.');
  if (!bundlePath.value.trim()) issues.push('No local bundle directory has been configured.');
  if (!darksiteUrl.value.trim()) issues.push('No dark-site web server URL has been configured.');
  if (inventory?.status === 'blocked') issues.push(`${missing} required bundle type${missing === 1 ? '' : 's'} missing from the last scan.`);
  if (!inventory || inventory.status === 'not_scanned') issues.push('No bundle inventory scan has been completed.');
  if (currentMode === 'windows') issues.push('Windows/IIS mode is lab or customer-managed; Nutanix documentation recommends a Linux web server for the official workflow.');

  issueList.innerHTML = issues.length
    ? issues.map((issue) => `<li>${issue}</li>`).join('')
    : '<li>No readiness blockers detected in the latest local scan.</li>';

  statusText.textContent = inventory?.status === 'ready' ? 'Bundle inventory ready' : 'Readiness needs attention';
}

async function loadState() {
  try {
    const [profile, inventory] = await Promise.all([
      api('/api/profile'),
      api('/api/inventory'),
    ]);
    renderProfile(profile);
    renderInventory(inventory);
    setMessage('Profile loaded from local jumpserver state.');
  } catch (error) {
    setMessage(error.message, 'error');
  }
}

segments.forEach((button) => {
  button.addEventListener('click', () => {
    segments.forEach((item) => item.classList.remove('active'));
    button.classList.add('active');
    currentMode = button.dataset.mode;
    const mode = modes[currentMode];
    modeCard.innerHTML = `<h3>${mode.title}</h3><p>${mode.body}</p>`;
    webServerMode.textContent = currentMode === 'linux' ? 'Linux' : 'Windows';
    webServerHint.textContent = mode.title;
    renderInventory(lastInventory);
  });
});

saveProfileButton.addEventListener('click', async () => {
  try {
    const profile = await api('/api/profile', {
      method: 'POST',
      body: JSON.stringify(selectedProfile()),
    });
    renderProfile(profile);
    setMessage('Profile saved locally.');
  } catch (error) {
    setMessage(error.message, 'error');
  }
});

scanButton.addEventListener('click', async () => {
  try {
    setMessage('Scanning bundle inventory...');
    const profile = selectedProfile();
    await api('/api/profile', { method: 'POST', body: JSON.stringify(profile) });
    const inventory = await api('/api/inventory', {
      method: 'POST',
      body: JSON.stringify({ bundlePath: profile.bundlePath }),
    });
    renderInventory(inventory);
    setMessage(`Inventory scan complete: ${inventory.detectedCount}/${inventory.requiredCount} required bundle types found.`, inventory.status === 'ready' ? 'success' : 'warning');
  } catch (error) {
    setMessage(error.message, 'error');
  }
});

refreshButton.addEventListener('click', loadState);

loadState();
