param(
    [string]$ServiceName = 'LCMDarkSiteOrchestrator',
    [string]$NssmPath = ''
)

$ErrorActionPreference = 'Stop'

if (-not $NssmPath) {
    $candidate = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'tools\nssm\nssm.exe'
    if (Test-Path -LiteralPath $candidate) {
        $NssmPath = $candidate
    }
}

if ($NssmPath -and (Test-Path -LiteralPath $NssmPath)) {
    & $NssmPath stop $ServiceName 2>$null | Out-Null
    & $NssmPath remove $ServiceName confirm 2>$null | Out-Null
}

$task = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false
}

Write-Host "$ServiceName removed if it existed."
