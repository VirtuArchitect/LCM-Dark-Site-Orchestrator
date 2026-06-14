#define AppName "LCM Dark Site Orchestrator"
#define AppVersion "0.1.0"
#define AppPublisher "VirtuArchitect"

[Setup]
AppId={{21D06357-F079-4C2A-8EDB-EAE51417AC15}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\LCM Dark Site Orchestrator
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputBaseFilename=LCM-Dark-Site-Orchestrator-Setup-v{#AppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin

[Files]
Source: "..\..\public\*"; DestDir: "{app}\public"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "..\..\scripts\windows\*.ps1"; DestDir: "{app}\scripts\windows"; Flags: ignoreversion
Source: "..\..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\docs\architecture\README.md"; DestDir: "{app}\docs\architecture"; Flags: ignoreversion
Source: "..\..\docs\windows-installation.md"; DestDir: "{app}\docs"; Flags: ignoreversion

[Dirs]
Name: "{commonappdata}\LCM-Dark-Site-Orchestrator"
Name: "{commonappdata}\LCM-Dark-Site-Orchestrator\logs"
Name: "{commonappdata}\LCM-Dark-Site-Orchestrator\evidence"

[Icons]
Name: "{group}\Open LCM Dark Site Orchestrator"; Filename: "http://localhost:5055/"
Name: "{group}\View Logs"; Filename: "{commonappdata}\LCM-Dark-Site-Orchestrator\logs"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\windows\install-service.ps1"" -InstallDir ""{app}"" -DataDir ""{commonappdata}\LCM-Dark-Site-Orchestrator"" -BindAddress 127.0.0.1 -Port 5055 -UseScheduledTaskFallback"; Flags: runhidden waituntilterminated
Filename: "http://localhost:5055/"; Description: "Open {#AppName}"; Flags: postinstall shellexec skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\windows\uninstall-service.ps1"""; Flags: runhidden waituntilterminated
