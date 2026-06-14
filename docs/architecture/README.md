# Architecture Notes

LCM Dark Site Orchestrator is planned as a readiness and evidence console, not
as a replacement for Prism Central Life Cycle Manager.

## Product Boundary

The application should:

- model one or more dark-site profiles;
- validate local bundle inventory and extracted web-server structure;
- validate Linux and Windows static web-server reachability;
- generate operator runbooks and evidence packs;
- track readiness history and audit-relevant operator actions.

The application should not:

- bypass Prism Central LCM;
- claim a Windows web server is Nutanix-supported for the official dark-site
  workflow;
- perform destructive LCM operations without documented Nutanix APIs or
  explicit operator approval.

## Visual Language

The UI follows the ZTF-Orchestrator style:

- Veridian badge and favicon;
- dark `bg-gray-950` style shell;
- compact cards with `surface` panels and blue/teal status accents;
- grouped sidebar navigation;
- issue-first dashboard panels.

## Web Server Modes

| Mode | Positioning | Validation Focus |
|---|---|---|
| Linux | Recommended and guide-aligned | nginx/Apache static path, permissions, firewall, extracted `/darksite/` structure, HTTP reachability |
| Windows / IIS | Lab or customer-managed | IIS static path, MIME/download checks, URL reachability, explicit unsupported-by-guide warning |

## Core Data Flow

```text
Dark-site profile
  -> bundle scanner
  -> extraction validator
  -> web URL probe
  -> readiness score
  -> evidence archive
```
