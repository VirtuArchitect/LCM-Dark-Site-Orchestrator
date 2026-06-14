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

## Data Locations

```text
C:\ProgramData\LCM-Dark-Site-Orchestrator\
C:\ProgramData\LCM-Dark-Site-Orchestrator\logs\
C:\ProgramData\LCM-Dark-Site-Orchestrator\evidence\
```

The MVP stores the current profile and last inventory scan as local JSON files:

```text
C:\ProgramData\LCM-Dark-Site-Orchestrator\profile.json
C:\ProgramData\LCM-Dark-Site-Orchestrator\last-inventory.json
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

## Security Defaults

- Localhost bind by default.
- No firewall rule is created automatically.
- Do not install on Prism Central or CVMs.
- Keep bundle credentials and evidence under `C:\ProgramData`.
- Use Linux web-server validation as the Nutanix-aligned path; Windows/IIS mode
  should be labelled as lab or customer-managed.
