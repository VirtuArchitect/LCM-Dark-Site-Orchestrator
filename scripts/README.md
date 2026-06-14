# Scripts

Place local developer scripts here. Scripts should be safe to run, documented,
and referenced from `AGENTS.md` or the project README when they are required for
testing, linting, security scanning, or smoke testing.

## Windows

The `windows/` folder contains the MVP jumpserver runtime:

- `lcm-darksite-server.ps1` serves the static console locally.
- `install-service.ps1` installs the console with NSSM when available, or as a
  scheduled-task fallback for early MVP use.
- `uninstall-service.ps1` removes the NSSM service or scheduled task.
