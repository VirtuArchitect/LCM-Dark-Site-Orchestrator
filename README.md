# LCM Dark Site Orchestrator

A readiness and evidence console for Nutanix LCM dark-site preparation.

The project is intended to help operators validate bundle presence, extracted
web-server structure, dark-site URL reachability, and operational readiness
before Prism Central LCM is configured to use a local dark-site source.

Unofficial community tooling. This project is not affiliated with or supported
by Nutanix.

## Design Standard

The dashboard intentionally follows the ZTF-Orchestrator visual language:

- dark enterprise console layout;
- left navigation rail with grouped operational sections;
- compact readiness cards and issue-first status panels;
- Veridian mark as the product badge;
- the same Veridian favicon used by ZTF-Orchestrator.

Linux web server mode is the recommended, guide-aligned path. Windows/IIS mode
can be modeled for lab or customer-managed validation, but should be clearly
labelled because the Nutanix Central guide states Windows-based local web server
is not supported for the official dark-site workflow.

## Current UI Shell

Open the static dashboard preview:

```text
public/index.html
```

No build step is required for the preview.

For a Windows jumpserver install, see
[Windows Installation](docs/windows-installation.md). The MVP runtime serves the
static console on `http://localhost:5055/` and stores operational state under
`C:\ProgramData\LCM-Dark-Site-Orchestrator`.

## Build Phases

1. Foundation and dark-site profile model. Implemented.
2. Bundle inventory and checksum capture. Implemented.
3. Extraction and folder structure validation. Implemented.
4. Linux and Windows web-server validation. Implemented.
5. Readiness dashboard. Implemented.
6. Evidence pack export. Implemented.
7. Guided runbook generation. Implemented.
8. Optional safe helper scripts.
9. Multi-site and multi-domain governance.
10. Optional integration with ZTF-Orchestrator.

## Distribution Plan

Primary distribution should be a Windows installer because many jumpservers and
management servers are Windows-based. Secondary distribution options remain
portable ZIP and Docker/Linux deployment for teams that host the console closer
to a Linux dark-site web server.

## MVP Scope

The first functional release should remain readiness-first:

- define a dark-site profile;
- scan a local bundle directory;
- detect required LCM/MSP/Compatibility/Nutanix Central/Marketplace bundles;
- validate extracted `darksite` structure;
- test HTTP reachability of expected paths;
- export validation evidence.

The tool should not bypass Prism Central or LCM. LCM remains the supported
update engine.

## Implemented MVP Functions

- Static ZTF-Orchestrator-style dashboard shell.
- Windows jumpserver runtime and installer scaffolding.
- Optional Windows Server/IIS dark-site web-root bootstrap script.
- Local profile save/load API.
- Local bundle staging folder preparation API.
- Bundle inventory scan API for required dark-site bundle types, including
  Windows-visible extracted `.tar` folders.
- SHA-256 checksum capture for detected bundle files.
- Extracted Nutanix Central and CPaaS folder/payload validation.
- Dark-site HTTP URL reachability checks for the base URL and detected bundle files.
- Local evidence pack export under `C:\ProgramData\LCM-Dark-Site-Orchestrator\evidence`.
- Generated runbook content based on the latest profile and validation state.

## Local API Surface

The PowerShell runtime exposes a small localhost API used by the dashboard:

| Endpoint | Purpose |
|---|---|
| `GET /api/health` | Runtime status and data directory. |
| `GET/POST /api/profile` | Load or save the local dark-site profile. |
| `POST /api/folder` | Create or confirm the configured local bundle staging folder. |
| `GET/POST /api/inventory` | Load or run required bundle inventory and checksum capture. |
| `GET/POST /api/extraction` | Load or run extracted-folder validation. |
| `GET/POST /api/web-validation` | Load or run HTTP reachability validation. |
| `GET/POST /api/evidence` | List or create evidence packs. |
| `GET /api/runbook` | Generate a runbook from the latest local state. |
