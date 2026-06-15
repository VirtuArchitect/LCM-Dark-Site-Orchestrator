const modeCard = document.querySelector('#mode-card');
const pages = document.querySelectorAll('.page[data-page]');
const navItems = document.querySelectorAll('.nav-item[data-page-link]');
const pageTitle = document.querySelector('#page-title');
const pageSubtitle = document.querySelector('#page-subtitle');
const segments = document.querySelectorAll('.segment');
const siteName = document.querySelector('#site-name');
const darksiteUrl = document.querySelector('#darksite-url');
const bundlePath = document.querySelector('#bundle-path');
const saveProfileButton = document.querySelector('#save-profile-button');
const prepareFolderButton = document.querySelector('#prepare-folder-button');
const scanButton = document.querySelector('#scan-button');
const extractionButton = document.querySelector('#extraction-button');
const webValidationButton = document.querySelector('#web-validation-button');
const runbookButton = document.querySelector('#runbook-button');
const evidenceButton = document.querySelector('#evidence-button');
const refreshButton = document.querySelector('#refresh-button');
const refreshStatus = document.querySelector('#refresh-status');
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
const auditList = document.querySelector('#audit-list');
const storageList = document.querySelector('#storage-list');
const inventoryHistoryList = document.querySelector('#inventory-history-list');
const userList = document.querySelector('#user-list');
const rbacUsername = document.querySelector('#rbac-username');
const rbacDisplayName = document.querySelector('#rbac-display-name');
const rbacRole = document.querySelector('#rbac-role');
const createUserButton = document.querySelector('#create-user-button');
const rbacMessage = document.querySelector('#rbac-message');
const backupList = document.querySelector('#backup-list');
const createBackupButton = document.querySelector('#create-backup-button');
const refreshBackupsButton = document.querySelector('#refresh-backups-button');
const governanceSiteCount = document.querySelector('#governance-site-count');
const governanceDomainCount = document.querySelector('#governance-domain-count');
const governanceDomainHint = document.querySelector('#governance-domain-hint');
const governanceLinuxCount = document.querySelector('#governance-linux-count');
const governanceWindowsCount = document.querySelector('#governance-windows-count');
const governanceSiteName = document.querySelector('#governance-site-name');
const governanceDomain = document.querySelector('#governance-domain');
const governanceEnvironment = document.querySelector('#governance-environment');
const governanceOwner = document.querySelector('#governance-owner');
const governanceBundlePath = document.querySelector('#governance-bundle-path');
const governanceDarksiteUrl = document.querySelector('#governance-darksite-url');
const governancePlatform = document.querySelector('#governance-platform');
const governanceMessage = document.querySelector('#governance-message');
const createSiteButton = document.querySelector('#create-site-button');
const siteList = document.querySelector('#site-list');
const helperScriptList = document.querySelector('#helper-script-list');

const pageMeta = {
  dashboard: ['Dashboard', 'Dark-site bundle readiness, web-server validation, and evidence capture'],
  profiles: ['Profiles', 'Configure the local dark-site validation target'],
  'bundle-inventory': ['Bundle Inventory', 'Required LCM dark-site artifacts and checksums'],
  'web-server': ['Web Server', 'Static hosting mode and URL reachability validation'],
  'extraction-checks': ['Extraction Checks', 'Extracted Nutanix Central and CPaaS payload readiness'],
  evidence: ['Evidence Archive', 'Generated evidence bundles for change records'],
  runbook: ['Runbook', 'Operator-facing implementation notes'],
  governance: ['Governance', 'Multi-site and multi-domain dark-site register'],
  'audit-log': ['Audit Log', 'Local operator activity and runtime events'],
  'helper-scripts': ['Helper Scripts', 'Approved manual scripts for local validation and setup'],
  rbac: ['RBAC', 'Role model and access-control roadmap'],
  database: ['Database', 'Storage backend and PostgreSQL roadmap'],
  settings: ['Settings', 'Local runtime paths and platform options'],
};

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

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[char]));
}

function asArray(value) {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}

function setMessage(message, tone = 'muted') {
  profileMessage.textContent = message;
  profileMessage.dataset.tone = tone;
}

function setRefreshStatus(message, tone = 'muted') {
  refreshStatus.textContent = message;
  refreshStatus.dataset.tone = tone;
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

  if (lastWebValidation.status === 'blocked') {
    const failedProbe = probes.find((probe) => probe.status !== 'reachable');
    if (failedProbe) {
      webServerHint.textContent = `Blocked: ${failedProbe.statusCode ? `HTTP ${failedProbe.statusCode}` : failedProbe.error || 'unreachable'}`;
    }
  }

  webValidationList.innerHTML = probes.length
    ? probes.map((probe) => `
      <div class="check-row ${probe.status === 'reachable' ? 'good' : 'bad'}">
        <span></span>
        <div>
          <strong>${probe.status === 'reachable' ? 'Reachable' : 'Unreachable'}</strong>
          <small>${probe.url}${probe.statusCode ? ` - HTTP ${probe.statusCode}` : ''}${probe.warning ? ` - ${probe.warning}` : ''}${probe.error ? ` - ${probe.error}` : ''}</small>
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

function renderAudit(audit) {
  const events = asArray(audit?.events);
  auditList.innerHTML = events.length
    ? events.map((event) => `
      <div class="check-row ${event.status === 'success' || event.status === 'ready' ? 'good' : event.status === 'blocked' ? 'bad' : 'warn-row'}">
        <span></span>
        <div>
          <strong>${escapeHtml(event.action || 'event')} - ${escapeHtml(event.status || 'info')}</strong>
          <small>${escapeHtml(formatDate(event.timestamp))} - ${escapeHtml(event.message || 'No message recorded.')}</small>
        </div>
      </div>
    `).join('')
    : '<div class="check-row muted"><span></span><div><strong>No audit events yet</strong><small>Run a validation action to create the first event.</small></div></div>';
}

function renderStorage(storage) {
  storageList.innerHTML = `
    <div class="check-row good"><span></span><div><strong>Backend</strong><small>${escapeHtml(storage?.backend || 'unknown')} - ${escapeHtml(storage?.status || 'unknown')}</small></div></div>
    <div class="check-row muted"><span></span><div><strong>Data directory</strong><small>${escapeHtml(storage?.dataDir || 'not reported')}</small></div></div>
    <div class="check-row ${storage?.postgres?.configured ? 'good' : 'warn-row'}"><span></span><div><strong>PostgreSQL</strong><small>${escapeHtml(storage?.postgres?.note || 'Not configured.')}</small></div></div>
  `;
}

function renderUsers(data) {
  const users = asArray(data?.users);
  userList.innerHTML = users.length
    ? users.map((user) => `
      <div class="check-row ${user.status === 'active' ? 'good' : 'muted'}">
        <span></span>
        <div>
          <strong>${escapeHtml(user.displayName || user.username)}</strong>
          <small>${escapeHtml(user.username)} - ${escapeHtml(user.role || 'viewer')} - ${escapeHtml(user.status || 'active')} - created ${escapeHtml(formatDate(user.createdAt))}</small>
        </div>
      </div>
    `).join('')
    : '<div class="check-row muted"><span></span><div><strong>No users found</strong><small>Create the first local user assignment.</small></div></div>';
}

function renderBackups(data) {
  const backups = asArray(data?.backups);
  backupList.innerHTML = backups.length
    ? backups.map((backup) => `
      <div class="check-row good">
        <span></span>
        <div>
          <strong>${escapeHtml(backup.name)}</strong>
          <small>${escapeHtml(formatDate(backup.createdAt))} - ${Math.ceil((backup.size || 0) / 1024)} KB</small>
        </div>
        <button class="btn row-action" data-restore-backup="${escapeHtml(backup.name)}">Restore</button>
      </div>
    `).join('')
    : '<div class="check-row muted"><span></span><div><strong>No backups yet</strong><small>Create a backup after the profile and validation state are populated.</small></div></div>';
}

function renderInventoryHistory(data) {
  const scans = asArray(data?.scans);
  inventoryHistoryList.innerHTML = scans.length
    ? scans.map((scan) => `
      <div class="check-row ${scan.status === 'ready' ? 'good' : 'bad'}">
        <span></span>
        <div>
          <strong>${escapeHtml(formatDate(scan.timestamp))} - ${escapeHtml(scan.status || 'unknown')}</strong>
          <small>${escapeHtml(scan.root || '')} - ${Number(scan.detectedCount || 0)} detected, ${Number(scan.missingCount || 0)} missing</small>
        </div>
      </div>
    `).join('')
    : '<div class="check-row muted"><span></span><div><strong>No inventory scans yet</strong><small>Run Scan Bundle Inventory to record the first update snapshot.</small></div></div>';
}

function renderGovernance(governance) {
  const sites = asArray(governance?.sites);
  const domains = asArray(governance?.domains);
  const activeSiteId = governance?.activeSiteId || '';
  governanceSiteCount.textContent = String(governance?.siteCount || sites.length || 0);
  governanceDomainCount.textContent = String(governance?.domainCount || domains.length || 0);
  governanceLinuxCount.textContent = String(governance?.linuxCount || 0);
  governanceWindowsCount.textContent = String(governance?.windowsCount || 0);
  governanceDomainHint.textContent = domains.length ? domains.join(', ') : 'No domains registered';

  siteList.innerHTML = sites.length
    ? sites.map((site) => `
      <div class="check-row ${site.id === activeSiteId ? 'good' : 'muted'}">
        <span></span>
        <div>
          <strong>${escapeHtml(site.name)}${site.id === activeSiteId ? ' - active' : ''}</strong>
          <small>${escapeHtml(site.domain)} - ${escapeHtml(site.environment || 'production')} - ${escapeHtml(site.webServerPlatform || 'linux')} - ${escapeHtml(site.darksiteUrl || 'no URL')}</small>
        </div>
        <button class="btn row-action" data-select-site="${escapeHtml(site.id)}">Load Profile</button>
      </div>
    `).join('')
    : '<div class="check-row muted"><span></span><div><strong>No registered sites</strong><small>Add a site to begin multi-site tracking.</small></div></div>';
}

function renderHelperScripts(data) {
  const scripts = asArray(data?.scripts);
  helperScriptList.innerHTML = scripts.length
    ? scripts.map((script) => `
      <div class="check-row good">
        <span></span>
        <div>
          <strong>${escapeHtml(script.title || script.name)}</strong>
          <small>${escapeHtml(script.platform || 'manual')} - ${escapeHtml(script.safety || '')}</small>
        </div>
        <button class="btn row-action" type="button" data-helper-download="${escapeHtml(script.name || '')}" data-helper-url="${escapeHtml(script.downloadUrl || '')}">Download</button>
      </div>
    `).join('')
    : '<div class="check-row muted"><span></span><div><strong>No helper scripts found</strong><small>Approved script files were not found in scripts/windows.</small></div></div>';
}

function filenameFromContentDisposition(value, fallback) {
  const match = /filename\*?=(?:UTF-8''|")?([^";]+)/i.exec(value || '');
  if (!match) return fallback;
  try {
    return decodeURIComponent(match[1].replace(/"$/g, ''));
  } catch {
    return match[1].replace(/"$/g, '') || fallback;
  }
}

async function downloadHelperScript(button) {
  const downloadUrl = button.dataset.helperUrl;
  const fallbackName = button.dataset.helperDownload || 'helper-script.ps1';
  if (!downloadUrl) {
    setRefreshStatus('Missing script URL', 'error');
    return;
  }

  const originalLabel = button.textContent;
  button.disabled = true;
  button.textContent = 'Downloading...';
  setRefreshStatus('Downloading script...');

  try {
    const response = await fetch(downloadUrl);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.error || `Download failed: ${response.status}`);
    }

    const blob = await response.blob();
    const filename = filenameFromContentDisposition(response.headers.get('Content-Disposition'), fallbackName);
    const objectUrl = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = objectUrl;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
    setRefreshStatus(`Downloaded ${filename}`, 'success');
    await refreshAudit();
  } catch (error) {
    setRefreshStatus(error.message, 'error');
  } finally {
    button.disabled = false;
    button.textContent = originalLabel;
  }
}

async function refreshAudit() {
  renderAudit(await api('/api/audit'));
}

async function refreshBackups() {
  renderBackups(await api('/api/backups'));
}

async function refreshInventoryHistory() {
  renderInventoryHistory(await api('/api/inventory-history'));
}

async function refreshGovernance() {
  renderGovernance(await api('/api/sites'));
}

function currentPage() {
  const raw = window.location.hash.replace(/^#\/?/, '');
  return pageMeta[raw] ? raw : 'dashboard';
}

function showPage(pageName) {
  const selected = pageMeta[pageName] ? pageName : 'dashboard';
  pages.forEach((page) => {
    page.classList.toggle('active', page.dataset.page === selected);
  });
  pageTitle.textContent = pageMeta[selected][0];
  pageSubtitle.textContent = pageMeta[selected][1];
  setActiveNav(selected);
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function setActiveNav(pageName) {
  navItems.forEach((item) => {
    item.classList.toggle('active', item.dataset.pageLink === pageName);
  });
}

function navigateToPage(pageName) {
  const selected = pageMeta[pageName] ? pageName : 'dashboard';
  history.replaceState(null, '', `#/${selected}`);
  showPage(selected);
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
    setRefreshStatus('Refreshing...');
    refreshButton.disabled = true;
    const [profile, inventory, extraction, webValidation, evidence, audit, storage, users, backups, inventoryHistory, governance, helperScripts] = await Promise.all([
      api('/api/profile'),
      api('/api/inventory'),
      api('/api/extraction'),
      api('/api/web-validation'),
      api('/api/evidence'),
      api('/api/audit'),
      api('/api/storage'),
      api('/api/users'),
      api('/api/backups'),
      api('/api/inventory-history'),
      api('/api/sites'),
      api('/api/helper-scripts'),
    ]);
    renderProfile(profile);
    renderInventory(inventory);
    renderExtraction(extraction);
    renderWebValidation(webValidation);
    renderEvidence(evidence);
    renderAudit(audit);
    renderStorage(storage);
    renderUsers(users);
    renderBackups(backups);
    renderInventoryHistory(inventoryHistory);
    renderGovernance(governance);
    renderHelperScripts(helperScripts);
    setMessage('Profile loaded from local jumpserver state.');
    setRefreshStatus('Refreshed', 'success');
  } catch (error) {
    setMessage(error.message, 'error');
    setRefreshStatus(error.message, 'error');
  } finally {
    refreshButton.disabled = false;
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
    await refreshAudit();
  } catch (error) {
    setMessage(error.message, 'error');
  }
});

prepareFolderButton.addEventListener('click', async () => {
  try {
    setMessage('Preparing local bundle folder...');
    const profile = selectedProfile();
    await api('/api/profile', { method: 'POST', body: JSON.stringify(profile) });
    const folder = await api('/api/folder', {
      method: 'POST',
      body: JSON.stringify({ bundlePath: profile.bundlePath }),
    });
    bundlePath.value = folder.path || profile.bundlePath;
    setMessage(`${folder.message} Copy or extract the Nutanix dark-site bundles there, then run inventory.`, 'success');
    renderReadiness();
    await refreshAudit();
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
    await Promise.all([refreshAudit(), refreshInventoryHistory()]);
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
    await refreshAudit();
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
    await refreshAudit();
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
    await refreshAudit();
  } catch (error) {
    setMessage(error.message, 'error');
  }
});

createUserButton.addEventListener('click', async () => {
  try {
    const users = await api('/api/users', {
      method: 'POST',
      body: JSON.stringify({
        username: rbacUsername.value.trim(),
        displayName: rbacDisplayName.value.trim(),
        role: rbacRole.value,
      }),
    });
    renderUsers(users);
    rbacUsername.value = '';
    rbacDisplayName.value = '';
    rbacMessage.textContent = 'User created and audit event recorded.';
    rbacMessage.dataset.tone = 'success';
    await refreshAudit();
  } catch (error) {
    rbacMessage.textContent = error.message;
    rbacMessage.dataset.tone = 'error';
  }
});

createSiteButton.addEventListener('click', async () => {
  try {
    const result = await api('/api/sites', {
      method: 'POST',
      body: JSON.stringify({
        name: governanceSiteName.value.trim(),
        domain: governanceDomain.value.trim(),
        environment: governanceEnvironment.value.trim() || 'production',
        owner: governanceOwner.value.trim(),
        bundlePath: governanceBundlePath.value.trim(),
        darksiteUrl: governanceDarksiteUrl.value.trim(),
        webServerPlatform: governancePlatform.value,
      }),
    });
    renderGovernance(result.governance);
    governanceSiteName.value = '';
    governanceDomain.value = '';
    governanceEnvironment.value = '';
    governanceOwner.value = '';
    governanceBundlePath.value = '';
    governanceDarksiteUrl.value = '';
    governanceMessage.textContent = 'Site registered and audit event recorded.';
    governanceMessage.dataset.tone = 'success';
    await refreshAudit();
  } catch (error) {
    governanceMessage.textContent = error.message;
    governanceMessage.dataset.tone = 'error';
  }
});

siteList.addEventListener('click', async (event) => {
  const button = event.target.closest('[data-select-site]');
  if (!button) return;
  try {
    const result = await api('/api/active-site', {
      method: 'POST',
      body: JSON.stringify({ siteId: button.dataset.selectSite }),
    });
    renderProfile(result.profile);
    await refreshGovernance();
    await refreshAudit();
    setMessage('Registered site loaded into the active profile.', 'success');
  } catch (error) {
    governanceMessage.textContent = error.message;
    governanceMessage.dataset.tone = 'error';
  }
});

createBackupButton.addEventListener('click', async () => {
  try {
    setMessage('Creating local state backup...');
    const result = await api('/api/backups', { method: 'POST' });
    renderBackups(result);
    setMessage('Local state backup created.', 'success');
    await refreshAudit();
  } catch (error) {
    setMessage(error.message, 'error');
  }
});

refreshBackupsButton.addEventListener('click', refreshBackups);

backupList.addEventListener('click', async (event) => {
  const button = event.target.closest('[data-restore-backup]');
  if (!button) return;
  const name = button.dataset.restoreBackup;
  const confirmed = window.confirm(`Restore backup "${name}"? This overwrites the current local state files.`);
  if (!confirmed) return;
  try {
    setMessage('Restoring local state backup...');
    await api('/api/restore', {
      method: 'POST',
      body: JSON.stringify({ name }),
    });
    await loadState();
    setMessage('Local state backup restored.', 'success');
  } catch (error) {
    setMessage(error.message, 'error');
  }
});

refreshButton.addEventListener('click', loadState);

helperScriptList.addEventListener('click', (event) => {
  const button = event.target.closest('[data-helper-download]');
  if (!button) return;
  downloadHelperScript(button);
});

navItems.forEach((item) => {
  item.addEventListener('click', (event) => {
    event.preventDefault();
    navigateToPage(item.dataset.pageLink);
  });
});

window.addEventListener('hashchange', () => {
  showPage(currentPage());
});

loadState();
showPage(currentPage());
