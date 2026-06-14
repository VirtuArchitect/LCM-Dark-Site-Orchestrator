param(
    [string]$InstallDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$ServiceName = 'LCMDarkSiteOrchestrator',
    [string]$DisplayName = 'LCM Dark Site Orchestrator',
    [string]$DataDir = (Join-Path $env:ProgramData 'LCM-Dark-Site-Orchestrator'),
    [string]$BindAddress = '127.0.0.1',
    [int]$Port = 5055,
    [string]$NssmPath = '',
    [switch]$UseScheduledTaskFallback
)

$ErrorActionPreference = 'Stop'

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell session.'
    }
}

Assert-Admin

$serverScript = Join-Path $InstallDir 'scripts\windows\lcm-darksite-server.ps1'
$contentRoot = Join-Path $InstallDir 'public'
if (-not (Test-Path -LiteralPath $serverScript)) {
    throw "Server script not found: $serverScript"
}
if (-not (Test-Path -LiteralPath (Join-Path $contentRoot 'index.html'))) {
    throw "Static dashboard not found: $contentRoot"
}

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $DataDir 'logs') | Out-Null

$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', "`"$serverScript`"",
    '-ContentRoot', "`"$contentRoot`"",
    '-DataDir', "`"$DataDir`"",
    '-BindAddress', $BindAddress,
    '-Port', $Port
) -join ' '

if (-not $NssmPath) {
    $candidate = Join-Path $InstallDir 'tools\nssm\nssm.exe'
    if (Test-Path -LiteralPath $candidate) {
        $NssmPath = $candidate
    }
}

if ($NssmPath -and (Test-Path -LiteralPath $NssmPath)) {
    & $NssmPath stop $ServiceName 2>$null | Out-Null
    & $NssmPath remove $ServiceName confirm 2>$null | Out-Null
    & $NssmPath install $ServiceName "$PSHOME\powershell.exe" $arguments | Out-Null
    & $NssmPath set $ServiceName DisplayName $DisplayName | Out-Null
    & $NssmPath set $ServiceName Description 'Local readiness console for Nutanix LCM dark-site preparation.' | Out-Null
    & $NssmPath set $ServiceName AppDirectory $InstallDir | Out-Null
    & $NssmPath set $ServiceName AppStdout (Join-Path $DataDir 'logs\service.out.log') | Out-Null
    & $NssmPath set $ServiceName AppStderr (Join-Path $DataDir 'logs\service.err.log') | Out-Null
    & $NssmPath start $ServiceName | Out-Null
    Write-Host "$DisplayName service installed and started."
}
elseif ($UseScheduledTaskFallback) {
    $action = New-ScheduledTaskAction -Execute "$PSHOME\powershell.exe" -Argument $arguments -WorkingDirectory $InstallDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $ServiceName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $ServiceName
    Write-Host "$DisplayName scheduled task installed and started."
}
else {
    throw 'NSSM was not found. Provide -NssmPath or use -UseScheduledTaskFallback for MVP installs.'
}

Write-Host "Open http://${BindAddress}:${Port}/"
