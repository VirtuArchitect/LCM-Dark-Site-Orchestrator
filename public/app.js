const modeCard = document.querySelector('#mode-card');
const segments = document.querySelectorAll('.segment');
const siteName = document.querySelector('#site-name');
const darksiteUrl = document.querySelector('#darksite-url');
const bundlePath = document.querySelector('#bundle-path');
const saveProfileButton = document.querySelector('#save-profile-button');
const scanButton = document.querySelector('#scan-button');
const extractionButton = document.querySelector('#extraction-button');
const webValidationButton = document.querySelector('#web-validation-button');
const runbookButton = document.querySelector('#runbook-button');
const evidenceButton = document.querySelector('#evidence-button');
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
const extractionBadge = document.querySelector('#extraction-badge');
const extractionList = document.querySelector('#extraction-list');
const webValidationBadge = document.querySelector('#web-validation-badge');
const webValidationList = document.querySelector('#web-validation-list');
const issueList = document.querySelector('#issue-list');
const issuesBadge = document.querySelector('#issues-badge');
const runbookPreview = document.querySelector('#runbook-preview');
const evidenceList = document.querySelector('#evidence-list');

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
let lastExtraction = { status: 'not_checked', checks: [] };
let lastWebValidation = { status: 'not_checked', probes: [] };
let lastEvidence = { evidence: [] };

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

function badgeClass(status) {
  if (status === 'ready') return 'success';
  if (status === 'blocked') return 'danger';
  return 'warn';
}

function badgeText(status) {
  if (status === 'ready') return 'Ready';
  if (status === 'blocked') return 'Blocked';
  if (status === 'warning') return 'Warning';
  return 'Pending';
}

function renderInventory(inventory) {
  lastInventory = inventory || { status: 'not_scanned', checks: [] };
  const checks = lastInventory.checks || [];
  const found = Number(lastInventory.detectedCount || 0);
  const missing = Number(lastInventory.missingCount || 0);

  detectedCount.textContent = String(found);
  detectedHint.textContent = lastInventory.status === 'not_scanned'
    ? 'Run inventory to populate'
    : `${missing} missing of ${lastInventory.requiredCount || 5} required`;

  inventoryBadge.textContent = badgeText(lastInventory.status);
  inventoryBadge.className = `badge ${badgeClass(lastInventory.status)}`;

  inventoryList.innerHTML = checks.length
    ? checks.map((check) => `
      <div class="check-row ${check.status === 'found' ? 'good' : 'bad'}">
        <span></span>
        <div>
          <strong>${check.label}</strong>
          <small>${check.status === 'found' ? `${check.count} found${check.latest?.version ? ` - v${check.latest.version}` : ''}` : `Missing - ${check.pattern}`}</small>
        </div>
      </div>
    `).join('')
    : '<div class="check-row muted"><span></span><div>Run inventory to populate bundle readiness.</div></div>';

  renderReadiness();
}

function renderExtraction(extraction) {
  lastExtraction = extraction || { status: 'not_checked', checks: [] };
  const checks = lastExtraction.checks || [];

  extractionBadge.textContent = badgeText(lastExtraction.status);
  extractionBadge.className = `badge ${badgeClass(lastExtraction.status)}`;
  extractionList.innerHTML = checks.length
    ? checks.map((check) => `
      <div class="check-row ${check.status === 'found' ? 'good' : check.status === 'warning' ? 'warn-row' : 'bad'}">
        <span></span>
        <div>
          <strong>${check.label}</strong>
          <small>${check.detail || check.status}</small>
        </div>
      </div>
    `).join('')
    : '<div class="check-row muted"><span></span><div>Run extraction validation after unpacking bundles.</div></div>';

  renderReadiness();
}

function renderWebValidation(validation) {
  lastWebValidation = validation || { status: 'not_checked', probes: [] };
  const probes = lastWebValidation.probes || [];

  webValidationBadge.textContent = badgeText(lastWebValidation.status);
  webValidationBadge.className = `badge ${badgeClass(lastWebValidation.status)}`;
  webServerMode.textContent = lastWebValidation.status === 'ready'
    ? 'Reachable'
    : lastWebValidation.status === 'blocked'
      ? 'Blocked'
      : currentMode === 'linux' ? 'Linux' : 'Windows';
  webServerHint.textContent = lastWebValidation.status === 'not_checked'
    ? 'No URL validation yet'
    : `${lastWebValidation.unreachableCount || 0} unreachable of ${lastWebValidation.checkedCount || probes.length} checks`;

  webValidationList.innerHTML = probes.length
    ? probes.map((probe) => `
      <div class="check-row ${probe.status === 'reachable' ? 'good' : 'bad'}">
        <span></span>
        <div>
          <strong>${probe.status === 'reachable' ? 'Reachable' : 'Unreachable'}</strong>
          <small>${probe.url}${probe.statusCode ? ` - HTTP ${probe.statusCode}` : ''}${probe.error ? ` - ${probe.error}` : ''}</small>
        </div>
      </div>
    `).join('')
    : '<div class="check-row muted"><span></span><div>Run web validation after the folder is hosted.</div></div>';

  renderReadiness();
}

function renderEvidence(evidence) {
  lastEvidence = evidence || { evidence: [] };
  const items = lastEvidence.evidence || [];
  evidenceList.innerHTML = items.length
    ? items.map((item) => `<div class="evidence-row"><strong>${item.name}</strong><span>${formatDate(item.createdAt)} - ${Math.ceil((item.size || 0) / 1024)} KB</span></div>`).join('')
    : 'No evidence packs created yet.';

  renderReadiness();
}

function renderRunbook(runbook) {
  runbookPreview.textContent = runbook?.markdown || 'No runbook generated yet.';
}

function renderReadiness() {
  const issues = [];
  if (!siteName.value.trim()) issues.push('No dark-site profile name has been saved.');
  if (!bundlePath.value.trim()) issues.push('No local bundle directory has been configured.');
  if (!darksiteUrl.value.trim()) issues.push('No dark-site web server URL has been configured.');
  if (lastInventory?.status === 'blocked') issues.push(`${lastInventory.missingCount || 0} required bundle type${lastInventory.missingCount === 1 ? '' : 's'} missing from the last scan.`);
  if (!lastInventory || lastInventory.status === 'not_scanned') issues.push('No bundle inventory scan has been completed.');
  if (lastExtraction?.status === 'blocked') issues.push(`${lastExtraction.missingCount || 0} extracted payload check${lastExtraction.missingCount === 1 ? '' : 's'} failed.`);
  if (!lastExtraction || lastExtraction.status === 'not_checked') issues.push('No extraction/folder validation has been completed.');
  if (lastWebValidation?.status === 'blocked') issues.push(`${lastWebValidation.unreachableCount || 0} dark-site web URL check${lastWebValidation.unreachableCount === 1 ? '' : 's'} failed.`);
  if (!lastWebValidation || lastWebValidation.status === 'not_checked') issues.push('No web server URL validation has been completed.');
  if (!lastEvidence?.evidence?.length) issues.push('No evidence pack has been generated.');
  if (currentMode === 'windows') issues.push('Windows/IIS mode is lab or customer-managed; Nutanix documentation recommends a Linux web server for the official workflow.');

  issueList.innerHTML = issues.length
    ? issues.map((issue) => `<li>${issue}</li>`).join('')
    : '<li>No readiness blockers detected in the latest local scan.</li>';

  issuesBadge.textContent = issues.length ? `${issues.length} blocker${issues.length === 1 ? '' : 's'}` : 'Ready';
  issuesBadge.className = `badge ${issues.length ? 'danger' : 'success'}`;
  statusText.textContent = issues.length ? 'Readiness needs attention' : 'Dark-site readiness validated';

  const lastCheck = lastWebValidation?.checkedAt || lastExtraction?.checkedAt || lastInventory?.scannedAt;
  lastValidation.textContent = lastCheck ? new Date(lastCheck).toLocaleDateString() : 'Never';
  lastValidationHint.textContent = lastCheck ? formatDate(lastCheck) : 'No evidence recorded';
}

async function loadState() {
  try {
    const [profile, inventory, extraction, webValidation, evidence] = await Promise.all([
      api('/api/profile'),
      api('/api/inventory'),
      api('/api/extraction'),
      api('/api/web-validation'),
      api('/api/evidence'),
    ]);
    renderProfile(profile);
    renderInventory(inventory);
    renderExtraction(extraction);
    renderWebValidation(webValidation);
    renderEvidence(evidence);
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
    if (lastWebValidation.status === 'not_checked') {
      webServerMode.textContent = currentMode === 'linux' ? 'Linux' : 'Windows';
      webServerHint.textContent = mode.title;
    }
    renderReadiness();
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

extractionButton.addEventListener('click', async () => {
  try {
    setMessage('Validating extracted dark-site folders...');
    const profile = selectedProfile();
    await api('/api/profile', { method: 'POST', body: JSON.stringify(profile) });
    const extraction = await api('/api/extraction', {
      method: 'POST',
      body: JSON.stringify({ bundlePath: profile.bundlePath }),
    });
    renderExtraction(extraction);
    setMessage(`Extraction validation complete: ${extraction.status}.`, extraction.status === 'ready' ? 'success' : 'warning');
  } catch (error) {
    setMessage(error.message, 'error');
  }
});

webValidationButton.addEventListener('click', async () => {
  try {
    setMessage('Validating dark-site web server URL...');
    const profile = selectedProfile();
    await api('/api/profile', { method: 'POST', body: JSON.stringify(profile) });
    const validation = await api('/api/web-validation', {
      method: 'POST',
      body: JSON.stringify({ darksiteUrl: profile.darksiteUrl }),
    });
    renderWebValidation(validation);
    setMessage(`Web validation complete: ${validation.status}.`, validation.status === 'ready' ? 'success' : 'warning');
  } catch (error) {
    setMessage(error.message, 'error');
  }
});

runbookButton.addEventListener('click', async () => {
  try {
    setMessage('Generating runbook from latest validation state...');
    const runbook = await api('/api/runbook');
    renderRunbook(runbook);
    setMessage('Runbook generated.', 'success');
  } catch (error) {
    setMessage(error.message, 'error');
  }
});

evidenceButton.addEventListener('click', async () => {
  try {
    setMessage('Creating evidence pack...');
    const evidence = await api('/api/evidence', { method: 'POST' });
    renderEvidence(evidence);
    renderRunbook({ markdown: evidence.runbook });
    setMessage('Evidence pack created in the local data directory.', 'success');
  } catch (error) {
    setMessage(error.message, 'error');
  }
});

refreshButton.addEventListener('click', loadState);

loadState();
