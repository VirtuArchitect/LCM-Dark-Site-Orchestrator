# Scripts

Place local developer scripts here. Scripts should be safe to run, documented,
and referenced from `AGENTS.md` or the project README when they are required for
testing, linting, security scanning, or smoke testing.

## Windows

The `windows/` folder contains the MVP jumpserver runtime:

- `lcm-darksite-server.ps1` serves the static console locally.
- `install-service.ps1` installs the console with NSSM when available, or as a
  scheduled-task fallback for early MVP use.
- `install-iis-darksite.ps1` prepares a Windows Server/IIS dark-site web root
  for lab or customer-managed hosting validation.
- `validate-darksite-prereqs.ps1` performs read-only local prerequisite checks
  for PowerShell, IIS tooling, bundle path access, and optional URL reachability.
- `uninstall-service.ps1` removes the NSSM service or scheduled task.

The console exposes approved helper scripts for download only. It intentionally
does not run helper scripts remotely; operators should review and execute them
manually on the correct server.
