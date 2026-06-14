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

## Planned Build Phases

1. Foundation and dark-site profile model.
2. Bundle inventory and checksum capture.
3. Extraction and folder structure validation.
4. Linux and Windows web-server validation.
5. Readiness dashboard.
6. Evidence pack export.
7. Guided runbook generation.
8. Optional safe helper scripts.
9. Multi-site and multi-domain governance.
10. Optional integration with ZTF-Orchestrator.

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
