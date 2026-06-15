param(
    [string]$BundlePath = 'C:\inetpub\wwwroot\darksite',
    [string]$DarksiteUrl = '',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function New-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail
    )

    [ordered]@{
        name = $Name
        status = $Status
        detail = $Detail
    }
}

$checks = @()

$checks += New-Check -Name 'PowerShell' -Status 'ready' -Detail $PSVersionTable.PSVersion.ToString()

$pathExists = Test-Path -LiteralPath $BundlePath -PathType Container
$checks += New-Check -Name 'Bundle path' -Status $(if ($pathExists) { 'ready' } else { 'blocked' }) -Detail $BundlePath

$webServerFeature = Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue
if ($webServerFeature) {
    $feature = Get-WindowsFeature Web-Server
    $checks += New-Check -Name 'IIS Web-Server feature' -Status $(if ($feature.Installed) { 'ready' } else { 'warning' }) -Detail $(if ($feature.Installed) { 'Installed' } else { 'Not installed' })
}
else {
    $checks += New-Check -Name 'Windows feature tooling' -Status 'warning' -Detail 'Get-WindowsFeature is unavailable on this host.'
}

$webAdmin = Get-Module -ListAvailable -Name WebAdministration
$checks += New-Check -Name 'IIS PowerShell module' -Status $(if ($webAdmin) { 'ready' } else { 'warning' }) -Detail $(if ($webAdmin) { 'WebAdministration available' } else { 'Install Web-Scripting-Tools if this host will manage IIS.' })

if (-not [string]::IsNullOrWhiteSpace($DarksiteUrl)) {
    try {
        $request = [System.Net.HttpWebRequest]::Create($DarksiteUrl)
        $request.Method = 'HEAD'
        $request.Timeout = 5000
        $response = $request.GetResponse()
        $checks += New-Check -Name 'Dark-site URL' -Status 'ready' -Detail "HTTP $([int]$response.StatusCode) $DarksiteUrl"
        $response.Close()
    }
    catch [System.Net.WebException] {
        $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($statusCode -eq 403) {
            $checks += New-Check -Name 'Dark-site URL' -Status 'warning' -Detail "HTTP 403 from $DarksiteUrl. This can be acceptable for an IIS folder with directory browsing disabled."
        }
        else {
            $checks += New-Check -Name 'Dark-site URL' -Status 'blocked' -Detail $_.Exception.Message
        }
        if ($_.Exception.Response) {
            $_.Exception.Response.Close()
        }
    }
}
else {
    $checks += New-Check -Name 'Dark-site URL' -Status 'warning' -Detail 'No URL supplied.'
}

$blocked = @($checks | Where-Object { $_.status -eq 'blocked' }).Count
$warning = @($checks | Where-Object { $_.status -eq 'warning' }).Count
$result = [ordered]@{
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    bundlePath = $BundlePath
    darksiteUrl = $DarksiteUrl
    status = if ($blocked -gt 0) { 'blocked' } elseif ($warning -gt 0) { 'warning' } else { 'ready' }
    checks = $checks
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Host "LCM Dark Site prerequisite validation: $($result.status)"
    foreach ($check in $checks) {
        Write-Host "[$($check.status)] $($check.name): $($check.detail)"
    }
}
