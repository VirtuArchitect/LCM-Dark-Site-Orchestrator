param(
    [string]$SiteName = 'Default Web Site',
    [string]$PhysicalPath = 'C:\inetpub\wwwroot\darksite',
    [string]$VirtualPath = 'darksite',
    [int]$Port = 80,
    [switch]$EnableDirectoryBrowsing,
    [switch]$SkipFirewallRule
)

$ErrorActionPreference = 'Stop'

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell session.'
    }
}

function Ensure-MimeMap {
    param(
        [string]$Extension,
        [string]$MimeType
    )

    $filter = "/system.webServer/staticContent/mimeMap[@fileExtension='$Extension']"
    $existing = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $filter -Name fileExtension -ErrorAction SilentlyContinue
    if ($existing) {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $filter -Name mimeType -Value $MimeType
        return
    }

    Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter '/system.webServer/staticContent' -Name '.' -Value @{
        fileExtension = $Extension
        mimeType = $MimeType
    }
}

Assert-Admin

$features = @(
    'Web-Server',
    'Web-Static-Content',
    'Web-Default-Doc',
    'Web-Http-Errors',
    'Web-Http-Logging',
    'Web-Request-Monitor',
    'Web-Mgmt-Console'
)

$installed = Install-WindowsFeature -Name $features -IncludeManagementTools
$failed = @($installed.FeatureResult | Where-Object { -not $_.Success })
if ($failed.Count -gt 0) {
    $names = ($failed | ForEach-Object { $_.Name }) -join ', '
    throw "One or more IIS features failed to install: $names"
}

Import-Module WebAdministration

New-Item -ItemType Directory -Force -Path $PhysicalPath | Out-Null
New-Item -ItemType Directory -Force -Path 'C:\inetpub\wwwroot' | Out-Null

$site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
if (-not $site) {
    New-Website -Name $SiteName -Port $Port -PhysicalPath 'C:\inetpub\wwwroot' -Force | Out-Null
}

$virtualPathName = $VirtualPath.Trim('/').Trim('\')
if ([string]::IsNullOrWhiteSpace($virtualPathName)) {
    throw 'VirtualPath must not be empty.'
}

$vdir = Get-WebVirtualDirectory -Site $SiteName -Name $virtualPathName -ErrorAction SilentlyContinue
if ($vdir) {
    Set-ItemProperty -Path "IIS:\Sites\$SiteName\$virtualPathName" -Name physicalPath -Value $PhysicalPath
}
else {
    New-WebVirtualDirectory -Site $SiteName -Name $virtualPathName -PhysicalPath $PhysicalPath | Out-Null
}

Ensure-MimeMap -Extension '.tar' -MimeType 'application/x-tar'
Ensure-MimeMap -Extension '.gz' -MimeType 'application/gzip'
Ensure-MimeMap -Extension '.tgz' -MimeType 'application/gzip'
Ensure-MimeMap -Extension '.json' -MimeType 'application/json'
Ensure-MimeMap -Extension '.yaml' -MimeType 'application/x-yaml'
Ensure-MimeMap -Extension '.yml' -MimeType 'application/x-yaml'

$vdirPath = "IIS:\Sites\$SiteName\$virtualPathName"
Set-WebConfigurationProperty -PSPath $vdirPath -Filter 'system.webServer/directoryBrowse' -Name enabled -Value ([bool]$EnableDirectoryBrowsing)

if (-not $SkipFirewallRule) {
    $ruleName = "LCM Dark Site IIS HTTP $Port"
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
    }
}

Start-Service W3SVC

$hostName = $env:COMPUTERNAME
$url = "http://$hostName/$virtualPathName/"
Write-Host 'IIS dark-site hosting is prepared.'
Write-Host "Site: $SiteName"
Write-Host "Physical path: $PhysicalPath"
Write-Host "Dark-site URL: $url"
Write-Host 'Copy or extract the Nutanix LCM dark-site bundles into the physical path before validation.'
