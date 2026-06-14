# Windows Installation

Windows jumpservers are the recommended first deployment target for field use.
The console runs locally and validates dark-site web-server readiness without
being installed on Prism Central, CVMs, or Nutanix appliances.

## Runtime Model

```text
Windows jumpserver
  LCM Dark Site Orchestrator
  C:\ProgramData\LCM-Dark-Site-Orchestrator
        |
        | HTTP checks
        v
Linux nginx/Apache dark-site server
or Windows IIS dark-site server
        |
        v
Prism Central LCM configured by operator
```

## Manual Jumpserver Install

Run from an elevated PowerShell session:

```powershell
cd "C:\Users\john\OneDrive\09 Profile\Documents\GitHub\LCM Dark Site Orchestrator"
.\scripts\windows\install-service.ps1 -UseScheduledTaskFallback
```

Open:

```text
http://localhost:5055/
```

By default the console binds to `127.0.0.1` for local-only access. Use a
specific management IP or `0.0.0.0` only when other administrators need remote
browser access, and create a firewall rule deliberately.

## NSSM Service Option

For a true Windows service, place `nssm.exe` at:

```text
tools\nssm\nssm.exe
```

Then run:

```powershell
.\scripts\windows\install-service.ps1
```

NSSM is not committed to this repository. Download it from its trusted source or
provide it through your internal software repository.

## Installer Build

The Inno Setup script is:

```text
installer\windows\LCMDarkSiteOrchestrator.iss
```

Build it on a Windows packaging machine with Inno Setup installed. The generated
installer uses the scheduled-task fallback by default so the MVP can run without
bundling third-party service-wrapper binaries.

## Optional IIS Dark-Site Web Server

For a base Windows Server 2022 install that will also host the dark-site files,
run the IIS helper from an elevated PowerShell session:

```powershell
cd "C:\Tools\LCM-Dark-Site-Orchestrator"
.\scripts\windows\install-iis-darksite.ps1
```

The script:

- installs IIS static web-server features and the IIS management console;
- installs the IIS PowerShell scripting tools used by `Get-Website` and related
  validation commands;
- creates `C:\inetpub\wwwroot\darksite` if it is missing;
- exposes that folder as `http://<server-name>/darksite/`;
- adds MIME mappings for `.tar`, `.gz`, `.tgz`, `.json`, `.yaml`, and `.yml`;
- starts the IIS service;
- creates an inbound firewall rule for TCP port 80 unless `-SkipFirewallRule` is
  used.

Directory browsing is disabled by default. Enable it only if the customer
process requires visible index listings:

```powershell
.\scripts\windows\install-iis-darksite.ps1 -EnableDirectoryBrowsing
```

To use a non-default path or port:

```powershell
.\scripts\windows\install-iis-darksite.ps1 `
  -PhysicalPath "D:\LCM-DarkSite" `
  -VirtualPath "darksite" `
  -Port 8080
```

After the helper completes, copy or extract the Nutanix LCM dark-site bundles
into the physical path and set the console's **Dark-site URL** to the reported
URL.

## Preparing the Bundle Folder

The console does not require bundles to exist before the profile is created. On
a fresh server:

1. Enter the intended **Local Bundle Path**, for example
   `C:\inetpub\wwwroot\darksite` or `C:\Share\darksite`.
2. Click **Prepare Bundle Folder**.
3. Copy or extract the Nutanix LCM dark-site bundles into that folder.
4. Click **Scan Bundle Inventory**.

The prepare action creates the folder if it is missing and writes a small marker
file explaining what should be staged there. It rejects relative paths and drive
or share roots to avoid accidentally using an unsafe location.

## Data Locations

```text
C:\ProgramData\LCM-Dark-Site-Orchestrator\
C:\ProgramData\LCM-Dark-Site-Orchestrator\logs\
C:\ProgramData\LCM-Dark-Site-Orchestrator\evidence\
```

The MVP stores the current profile and last validation results as local JSON
files:

```text
C:\ProgramData\LCM-Dark-Site-Orchestrator\profile.json
C:\ProgramData\LCM-Dark-Site-Orchestrator\last-inventory.json
C:\ProgramData\LCM-Dark-Site-Orchestrator\last-extraction.json
C:\ProgramData\LCM-Dark-Site-Orchestrator\last-web-validation.json
```

## Bundle Inventory Phase

The first functional phase scans a local or mounted bundle directory from the
jumpserver. It detects these dark-site artifacts:

| Artifact | Expected filename pattern |
|---|---|
| LCM framework bundle | `lcm_dark_site_bundle_*.tar.gz` |
| MSP LCM bundle | `lcm_msp_*.tar.gz` |
| Compatibility bundle | `nutanix_compatibility_bundle.tar.gz` |
| Nutanix Central dark-site bundle | `lcm-darksite-nutanix-central-*.tar.gz` |
| Marketplace dark-site bundle | `lcm_marketplace_bundle_*.tar.gz` |

For detected bundles, the scan records filename, path, size, modified time,
version hint, and SHA-256 checksum.

## Extraction Validation Phase

After the dark-site bundles are unpacked, run **Validate Extraction** from the
dashboard. The console checks for the expected extracted Nutanix Central and
CPaaS structure, including:

- `nutanix-central-*` extracted folder;
- `nc-cpaas-*` extracted folder;
- charts payload under the Nutanix Central folder;
- images payload under the Nutanix Central folder;
- charts payload under the CPaaS folder;
- images payload under the CPaaS folder.

The LCM framework extraction marker is reported as a warning rather than a hard
blocker because some customer staging layouts flatten that content.

## Web Server Validation Phase

Run **Validate Web Server** after the folder is hosted by nginx, Apache, or IIS.
The console checks:

- the configured dark-site base URL;
- each required bundle path detected by the latest inventory scan, relative to
  the configured local bundle root.

URLs must use `http` or `https`. Credentials in URLs are rejected. The console
uses short timeouts so a broken web server does not hang the operator session.
For IIS, `403 Forbidden` on the base `/darksite/` URL is treated as a reachable
warning when directory browsing is disabled. Direct bundle file URLs must still
be reachable once files are staged.

## Evidence and Runbook

The **Create Evidence Pack** action writes a timestamped Markdown evidence file
and JSON manifest to:

```text
C:\ProgramData\LCM-Dark-Site-Orchestrator\evidence\
```

The **Generate Runbook** action creates operator-facing Markdown from the latest
profile, inventory, extraction, and web-validation state. Attach the evidence
pack to the implementation or change record before pointing Prism Central LCM at
the dark-site URL.

## Security Defaults

- Localhost bind by default.
- No firewall rule is created automatically.
- Do not install on Prism Central or CVMs.
- Keep bundle credentials and evidence under `C:\ProgramData`.
- Do not include credentials in dark-site URLs.
- Use the IIS helper only on a server that is intended to host dark-site files.
- Use Linux web-server validation as the Nutanix-aligned path; Windows/IIS mode
  should be labelled as lab or customer-managed.
