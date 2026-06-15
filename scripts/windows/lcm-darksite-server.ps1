param(
    [string]$ContentRoot = (Join-Path $PSScriptRoot '..\..\public'),
    [string]$DataDir = (Join-Path $env:ProgramData 'LCM-Dark-Site-Orchestrator'),
    [string]$BindAddress = '127.0.0.1',
    [int]$Port = 5055
)

$ErrorActionPreference = 'Stop'

function Resolve-SafePath {
    param(
        [string]$Root,
        [string]$RequestPath
    )

    $decoded = [System.Uri]::UnescapeDataString($RequestPath)
    if ([string]::IsNullOrWhiteSpace($decoded) -or $decoded -eq '/') {
        $decoded = '/index.html'
    }

    $relative = $decoded.TrimStart('/').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $Root $relative))
    $rootFull = [System.IO.Path]::GetFullPath($Root)

    if (-not $candidate.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Requested path escapes content root'
    }

    return $candidate
}

function Get-ContentType {
    param([string]$Path)

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { 'text/html; charset=utf-8'; break }
        '.css'  { 'text/css; charset=utf-8'; break }
        '.js'   { 'application/javascript; charset=utf-8'; break }
        '.json' { 'application/json; charset=utf-8'; break }
        '.svg'  { 'image/svg+xml'; break }
        '.png'  { 'image/png'; break }
        '.ico'  { 'image/x-icon'; break }
        default { 'application/octet-stream' }
    }
}

function Write-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [object]$Body,
        [int]$StatusCode = 200
    )

    $json = $Body | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Read-JsonRequest {
    param([System.Net.HttpListenerRequest]$Request)

    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        $raw = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{}
    }

    return $raw | ConvertFrom-Json
}

function Get-JsonValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if (-not $Object) {
        return $Default
    }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
        return $Object[$Name]
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $Default
}

function Get-ProfilePath {
    Join-Path $DataDir 'profile.json'
}

function Get-InventoryPath {
    Join-Path $DataDir 'last-inventory.json'
}

function Get-ExtractionPath {
    Join-Path $DataDir 'last-extraction.json'
}

function Get-WebValidationPath {
    Join-Path $DataDir 'last-web-validation.json'
}

function Get-EvidenceDir {
    Join-Path $DataDir 'evidence'
}

function Get-AuditPath {
    Join-Path $DataDir 'audit-events.jsonl'
}

function Get-UsersPath {
    Join-Path $DataDir 'users.json'
}

function Get-InventoryHistoryPath {
    Join-Path $DataDir 'inventory-history.jsonl'
}

function Get-BackupDir {
    Join-Path $DataDir 'backups'
}

function Get-SitesPath {
    Join-Path $DataDir 'sites.json'
}

function Get-ActiveSitePath {
    Join-Path $DataDir 'active-site.txt'
}

function Write-TextResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$Body,
        [string]$ContentType = 'text/plain; charset=utf-8',
        [int]$StatusCode = 200,
        [string]$DownloadName = ''
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    if (-not [string]::IsNullOrWhiteSpace($DownloadName)) {
        $Response.Headers.Add('Content-Disposition', "attachment; filename=`"$DownloadName`"")
    }
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Write-AuditEvent {
    param(
        [string]$Action,
        [string]$Status = 'info',
        [string]$Message = '',
        [object]$Details = $null
    )

    $event = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        action = $Action
        status = $Status
        message = $Message
        details = $Details
    }
    ($event | ConvertTo-Json -Depth 6 -Compress) | Add-Content -LiteralPath (Get-AuditPath) -Encoding utf8
}

function Get-AuditEvents {
    param([int]$Limit = 100)

    $path = Get-AuditPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }

    return @(Get-Content -LiteralPath $path -Tail $Limit | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) {
            $_ | ConvertFrom-Json
        }
    } | Sort-Object timestamp -Descending)
}

function Add-JsonLine {
    param(
        [string]$Path,
        [object]$Body
    )

    ($Body | ConvertTo-Json -Depth 8 -Compress) | Add-Content -LiteralPath $Path -Encoding utf8
}

function Get-JsonLines {
    param(
        [string]$Path,
        [int]$Limit = 100
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    return @(Get-Content -LiteralPath $Path -Tail $Limit | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) {
            $_ | ConvertFrom-Json
        }
    } | Sort-Object timestamp -Descending)
}

function ConvertTo-PlainArray {
    param([object]$Items)

    $result = @()
    foreach ($item in @($Items)) {
        if ($item -and $item.PSObject.Properties['value'] -and $item.PSObject.Properties['Count']) {
            foreach ($nested in @($item.value)) {
                $result += $nested
            }
        }
        else {
            $result += $item
        }
    }
    return $result
}

function Load-Users {
    $path = Get-UsersPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $defaultUsers = @(
            [ordered]@{
                id = 'admin'
                username = 'admin'
                displayName = 'Local Administrator'
                role = 'admin'
                status = 'active'
                createdAt = [DateTimeOffset]::UtcNow.ToString('o')
            }
        )
        Save-JsonFile -Path $path -Body $defaultUsers
        return $defaultUsers
    }
    return ConvertTo-PlainArray -Items (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Save-Users {
    param([object[]]$Users)
    Save-JsonFile -Path (Get-UsersPath) -Body @(ConvertTo-PlainArray -Items $Users)
}

function Load-Sites {
    $path = Get-SitesPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }
    return ConvertTo-PlainArray -Items (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Save-Sites {
    param([object[]]$Sites)
    Save-JsonFile -Path (Get-SitesPath) -Body @(ConvertTo-PlainArray -Items $Sites)
}

function Get-ActiveSiteId {
    $path = Get-ActiveSitePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return ''
    }
    return (Get-Content -LiteralPath $path -Raw).Trim()
}

function Set-ActiveSiteId {
    param([string]$SiteId)
    $SiteId | Set-Content -LiteralPath (Get-ActiveSitePath) -Encoding ascii
}

function New-DarkSiteTarget {
    param([object]$Payload)

    $name = [string](Get-JsonValue -Object $Payload -Name 'name')
    $domain = [string](Get-JsonValue -Object $Payload -Name 'domain')
    $environment = [string](Get-JsonValue -Object $Payload -Name 'environment' -Default 'production')
    $owner = [string](Get-JsonValue -Object $Payload -Name 'owner')
    $bundlePath = [string](Get-JsonValue -Object $Payload -Name 'bundlePath')
    $darksiteUrl = [string](Get-JsonValue -Object $Payload -Name 'darksiteUrl')
    $platform = [string](Get-JsonValue -Object $Payload -Name 'webServerPlatform' -Default 'linux')

    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'Site name is required'
    }
    if ([string]::IsNullOrWhiteSpace($domain)) {
        throw 'Domain is required'
    }
    if ($platform -notin @('linux', 'windows')) {
        throw 'Web server platform must be linux or windows'
    }

    $sites = @(Load-Sites)
    $existing = @($sites | Where-Object { $_.name -eq $name -and $_.domain -eq $domain })
    if ($existing.Count -gt 0) {
        throw "Site already exists for domain: $name / $domain"
    }

    $site = [ordered]@{
        id = [guid]::NewGuid().ToString('N')
        name = $name
        domain = $domain
        environment = if ([string]::IsNullOrWhiteSpace($environment)) { 'production' } else { $environment }
        owner = $owner
        bundlePath = $bundlePath
        darksiteUrl = $darksiteUrl
        webServerPlatform = $platform
        status = 'registered'
        createdAt = [DateTimeOffset]::UtcNow.ToString('o')
        updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    }
    Save-Sites -Sites @($sites + $site)
    Write-AuditEvent -Action 'site.create' -Status 'success' -Message "Dark-site target registered: $name / $domain" -Details ([ordered]@{
        siteId = $site.id
        domain = $domain
        environment = $site.environment
    })
    return $site
}

function Select-DarkSiteTarget {
    param([string]$SiteId)

    $site = @(Load-Sites) | Where-Object { $_.id -eq $SiteId } | Select-Object -First 1
    if (-not $site) {
        throw "Site was not found: $SiteId"
    }

    $siteId = [string](Get-JsonValue -Object $site -Name 'id')
    $siteName = [string](Get-JsonValue -Object $site -Name 'name')
    $domain = [string](Get-JsonValue -Object $site -Name 'domain')
    $platform = [string](Get-JsonValue -Object $site -Name 'webServerPlatform' -Default 'linux')
    $bundlePath = [string](Get-JsonValue -Object $site -Name 'bundlePath')
    $darksiteUrl = [string](Get-JsonValue -Object $site -Name 'darksiteUrl')

    Set-ActiveSiteId -SiteId $siteId
    Save-Profile -Profile ([ordered]@{
        siteName = $siteName
        webServerPlatform = $platform
        bundlePath = $bundlePath
        darksiteUrl = $darksiteUrl
    }) | Out-Null
    Write-AuditEvent -Action 'site.select' -Status 'success' -Message "Active site selected: $siteName / $domain" -Details ([ordered]@{
        siteId = $siteId
        domain = $domain
    })
    return [ordered]@{
        activeSiteId = $siteId
        site = $site
        profile = Load-Profile
    }
}

function Get-GovernanceSummary {
    $sites = @(Load-Sites)
    $domains = @($sites | ForEach-Object { $_.domain } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $activeSiteId = Get-ActiveSiteId
    [ordered]@{
        activeSiteId = $activeSiteId
        siteCount = $sites.Count
        domainCount = $domains.Count
        windowsCount = @($sites | Where-Object { $_.webServerPlatform -eq 'windows' }).Count
        linuxCount = @($sites | Where-Object { $_.webServerPlatform -eq 'linux' }).Count
        domains = $domains
        sites = $sites
    }
}

function Get-HelperScriptCatalog {
    $scriptsRoot = Join-Path $PSScriptRoot '.'
    @(
        [ordered]@{
            name = 'install-iis-darksite.ps1'
            title = 'Prepare Windows IIS dark-site web root'
            platform = 'Windows Server'
            safety = 'Creates IIS role/app configuration only when run explicitly by an administrator.'
            path = Join-Path $scriptsRoot 'install-iis-darksite.ps1'
        },
        [ordered]@{
            name = 'validate-darksite-prereqs.ps1'
            title = 'Validate local dark-site prerequisites'
            platform = 'Windows Server'
            safety = 'Read-only checks for PowerShell, IIS tooling, folder access, and optional URL reachability.'
            path = Join-Path $scriptsRoot 'validate-darksite-prereqs.ps1'
        },
        [ordered]@{
            name = 'install-service.ps1'
            title = 'Install console as a Windows service'
            platform = 'Windows Server'
            safety = 'Installs the console service only when NSSM path and install directory are supplied.'
            path = Join-Path $scriptsRoot 'install-service.ps1'
        }
    ) | Where-Object { Test-Path -LiteralPath $_.path -PathType Leaf }
}

function New-LocalUser {
    param([object]$Payload)

    $username = [string](Get-JsonValue -Object $Payload -Name 'username')
    $displayName = [string](Get-JsonValue -Object $Payload -Name 'displayName')
    $role = [string](Get-JsonValue -Object $Payload -Name 'role' -Default 'viewer')

    if ([string]::IsNullOrWhiteSpace($username)) {
        throw 'Username is required'
    }
    if ($role -notin @('admin', 'operator', 'viewer')) {
        throw 'Role must be admin, operator, or viewer'
    }

    $users = @(Load-Users)
    if (@($users | Where-Object { $_.username -eq $username }).Count -gt 0) {
        throw "User already exists: $username"
    }

    $user = [ordered]@{
        id = [guid]::NewGuid().ToString('N')
        username = $username
        displayName = if ([string]::IsNullOrWhiteSpace($displayName)) { $username } else { $displayName }
        role = $role
        status = 'active'
        createdAt = [DateTimeOffset]::UtcNow.ToString('o')
    }
    Save-Users -Users @($users + $user)
    Write-AuditEvent -Action 'user.create' -Status 'success' -Message "Local RBAC user created: $username" -Details ([ordered]@{
        username = $username
        role = $role
    })
    return $user
}

function Get-BackupList {
    $dir = Get-BackupDir
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $dir -File -Filter '*.zip' |
        Sort-Object LastWriteTimeUtc -Descending |
        ForEach-Object {
            [ordered]@{
                name = $_.Name
                path = $_.FullName
                size = $_.Length
                createdAt = $_.LastWriteTimeUtc.ToString('o')
            }
        })
}

function New-StateBackup {
    $dir = Get-BackupDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $dir "lcm-darksite-state-$stamp.zip"
    $items = @(
        (Get-ProfilePath),
        (Get-InventoryPath),
        (Get-InventoryHistoryPath),
        (Get-ExtractionPath),
        (Get-WebValidationPath),
        (Get-AuditPath),
        (Get-UsersPath),
        (Get-SitesPath),
        (Get-ActiveSitePath)
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

    if ($items.Count -eq 0) {
        throw 'No state files are available to back up'
    }

    Compress-Archive -LiteralPath $items -DestinationPath $backupPath -Force
    Write-AuditEvent -Action 'state.backup' -Status 'success' -Message 'Local state backup created.' -Details ([ordered]@{ backup = $backupPath })
    return [ordered]@{
        status = 'created'
        backup = $backupPath
        backups = @(Get-BackupList)
    }
}

function Restore-StateBackup {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Backup name is required'
    }
    $leaf = [System.IO.Path]::GetFileName($Name)
    $backupPath = Join-Path (Get-BackupDir) $leaf
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "Backup was not found: $leaf"
    }

    Expand-Archive -LiteralPath $backupPath -DestinationPath $DataDir -Force
    Write-AuditEvent -Action 'state.restore' -Status 'success' -Message 'Local state backup restored.' -Details ([ordered]@{ backup = $backupPath })
    return [ordered]@{
        status = 'restored'
        backup = $backupPath
        backups = @(Get-BackupList)
    }
}

function Get-DefaultProfile {
    [ordered]@{
        siteName = ''
        webServerPlatform = 'linux'
        bundlePath = ''
        darksiteUrl = ''
        expectedVersions = [ordered]@{
            lcmFramework = ''
            msp = ''
            marketplace = ''
            nutanixCentral = ''
        }
    }
}

function Save-Profile {
    param([object]$Profile)

    $current = Get-DefaultProfile
    foreach ($key in @('siteName', 'webServerPlatform', 'bundlePath', 'darksiteUrl')) {
        $value = Get-JsonValue -Object $Profile -Name $key
        if ($null -ne $value) {
            $current[$key] = [string]$value
        }
    }
    $expectedVersions = Get-JsonValue -Object $Profile -Name 'expectedVersions'
    if ($expectedVersions) {
        foreach ($key in @('lcmFramework', 'msp', 'marketplace', 'nutanixCentral')) {
            $value = Get-JsonValue -Object $expectedVersions -Name $key
            if ($null -ne $value) {
                $current.expectedVersions[$key] = [string]$value
            }
        }
    }

    $current.updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $current | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Get-ProfilePath) -Encoding utf8
    Write-AuditEvent -Action 'profile.save' -Status 'success' -Message 'Dark-site profile saved.' -Details ([ordered]@{
        siteName = $current.siteName
        webServerPlatform = $current.webServerPlatform
        bundlePath = $current.bundlePath
        darksiteUrl = $current.darksiteUrl
    })
    return $current
}

function Load-Profile {
    $path = Get-ProfilePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return Get-DefaultProfile
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Match-BundleType {
    param([string]$Name)

    $lower = $Name.ToLowerInvariant()
    if ($lower -match '^lcm_dark_site_bundle_.*\.tar\.gz$') { return 'lcmFramework' }
    if ($lower -match '^lcm_dark_site_bundle_.*\.tar$') { return 'lcmFramework' }
    if ($lower -match '^lcm[-_]msp(?:[-_]platform)?_.*\.tar(?:\.gz)?$') { return 'msp' }
    if ($lower -eq 'nutanix_compatibility_bundle.tar.gz') { return 'compatibility' }
    if ($lower -eq 'nutanix_compatibility_bundle.tar') { return 'compatibility' }
    if ($lower -match '^lcm[-_]darksite[-_]nutanix[-_]central[-_].*\.tar(?:\.gz)?$') { return 'nutanixCentralDarksite' }
    if ($lower -match '^nutanix-central-\d.*$') { return 'nutanixCentralDarksite' }
    if ($lower -match '^nutanix central extracted folder$') { return 'nutanixCentralDarksite' }
    if ($lower -match '^lcm[-_]marketplace[-_]bundle_.*\.tar(?:\.gz)?$') { return 'marketplace' }
    if ($lower -match '^nutanix-central-.*\.tar\.gz$') { return 'nutanixCentral' }
    if ($lower -match '^nc-cpaas-.*\.tar\.gz$') { return 'ncCpaas' }
    return $null
}

function Find-Version {
    param([string]$Name)

    $match = [regex]::Match($Name, '(\d+(?:\.\d+){1,4})')
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return ''
}

function New-BundleRecord {
    param([System.IO.FileInfo]$File)

    $type = Match-BundleType -Name $File.Name
    if (-not $type) {
        return $null
    }

    [ordered]@{
        type = $type
        artifactKind = 'file'
        name = $File.Name
        path = $File.FullName
        size = $File.Length
        modifiedAt = $File.LastWriteTimeUtc.ToString('o')
        version = Find-Version -Name $File.Name
        sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function New-DirectoryRecord {
    param([System.IO.DirectoryInfo]$Directory)

    $type = Match-BundleType -Name $Directory.Name
    if (-not $type) {
        return $null
    }

    [ordered]@{
        type = $type
        artifactKind = 'directory'
        name = $Directory.Name
        path = $Directory.FullName
        size = 0
        modifiedAt = $Directory.LastWriteTimeUtc.ToString('o')
        version = Find-Version -Name $Directory.Name
        sha256 = ''
    }
}

function Scan-BundleInventory {
    param([string]$BundlePath)

    if ([string]::IsNullOrWhiteSpace($BundlePath)) {
        throw 'Bundle path is required'
    }
    if (-not (Test-Path -LiteralPath $BundlePath -PathType Container)) {
        throw "Bundle path was not found: $BundlePath"
    }

    $root = [System.IO.Path]::GetFullPath($BundlePath)
    $files = Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.gz', '.tar') -or $_.Name -like '*.tar.gz' }
    $directories = Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction Stop

    $records = @()
    foreach ($file in $files) {
        $record = New-BundleRecord -File $file
        if ($record) {
            $records += $record
        }
    }
    foreach ($directory in $directories) {
        $record = New-DirectoryRecord -Directory $directory
        if ($record) {
            $records += $record
        }
    }

    $required = @(
        [ordered]@{ type = 'lcmFramework'; label = 'LCM framework bundle'; pattern = 'lcm_dark_site_bundle_*.tar.gz or extracted .tar folder' },
        [ordered]@{ type = 'msp'; label = 'MSP LCM bundle'; pattern = 'lcm_msp_*.tar.gz or lcm-msp-platform_*.tar.gz' },
        [ordered]@{ type = 'compatibility'; label = 'Compatibility bundle'; pattern = 'nutanix_compatibility_bundle.tar.gz or extracted .tar folder' },
        [ordered]@{ type = 'nutanixCentralDarksite'; label = 'Nutanix Central dark-site bundle'; pattern = 'lcm-darksite-nutanix-central-*.tar.gz or nutanix-central-* folder' },
        [ordered]@{ type = 'marketplace'; label = 'Marketplace dark-site bundle'; pattern = 'lcm_marketplace_bundle_*.tar.gz or extracted .tar folder' }
    )

    $checks = @()
    foreach ($item in $required) {
        $matches = @($records | Where-Object { $_.type -eq $item.type })
        $checks += [ordered]@{
            type = $item.type
            label = $item.label
            pattern = $item.pattern
            status = if ($matches.Count -gt 0) { 'found' } else { 'missing' }
            count = $matches.Count
            latest = if ($matches.Count -gt 0) { $matches | Sort-Object modifiedAt -Descending | Select-Object -First 1 } else { $null }
        }
    }

    $missing = @($checks | Where-Object { $_.status -eq 'missing' })
    $result = [ordered]@{
        scannedAt = [DateTimeOffset]::UtcNow.ToString('o')
        root = $root
        requiredCount = $required.Count
        detectedCount = @($checks | Where-Object { $_.status -eq 'found' }).Count
        missingCount = $missing.Count
        status = if ($missing.Count -eq 0) { 'ready' } else { 'blocked' }
        checks = $checks
        bundles = $records
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Get-InventoryPath) -Encoding utf8
    Add-JsonLine -Path (Get-InventoryHistoryPath) -Body ([ordered]@{
        timestamp = $result.scannedAt
        root = $result.root
        status = $result.status
        detectedCount = $result.detectedCount
        missingCount = $result.missingCount
        checks = $result.checks
        bundles = $result.bundles
    })
    Write-AuditEvent -Action 'inventory.scan' -Status $result.status -Message "Inventory scan detected $($result.detectedCount) of $($result.requiredCount) required bundle types." -Details ([ordered]@{
        root = $result.root
        detectedCount = $result.detectedCount
        missingCount = $result.missingCount
    })
    return $result
}

function Load-Inventory {
    $path = Get-InventoryPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Load-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Save-JsonFile {
    param(
        [string]$Path,
        [object]$Body
    )

    $Body | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Initialize-BundleFolder {
    param([string]$BundlePath)

    if ([string]::IsNullOrWhiteSpace($BundlePath)) {
        throw 'Bundle path is required'
    }

    if (-not [System.IO.Path]::IsPathRooted($BundlePath)) {
        throw 'Bundle path must be an absolute local or UNC path'
    }

    $fullPath = [System.IO.Path]::GetFullPath($BundlePath)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.TrimEnd('\') -eq $root.TrimEnd('\')) {
        throw 'Bundle path must not be a drive or share root'
    }

    $existed = Test-Path -LiteralPath $fullPath -PathType Container
    if (-not $existed) {
        New-Item -ItemType Directory -Force -Path $fullPath | Out-Null
    }

    $markerPath = Join-Path $fullPath 'README-LCM-DARKSITE.txt'
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
        @(
            'LCM Dark Site staging folder',
            '',
            'Copy or extract Nutanix LCM dark-site source bundles into this folder before running inventory validation.',
            'This marker file can be removed after the real bundle content is staged.'
        ) | Set-Content -LiteralPath $markerPath -Encoding utf8
    }

    $result = [ordered]@{
        status = 'ready'
        path = $fullPath
        created = -not $existed
        marker = $markerPath
        message = if ($existed) { 'Bundle folder already exists.' } else { 'Bundle folder created.' }
    }
    Write-AuditEvent -Action 'folder.prepare' -Status 'success' -Message $result.message -Details ([ordered]@{
        path = $fullPath
        created = $result.created
    })
    return $result
}

function Find-FirstDirectory {
    param(
        [string]$Root,
        [string]$Pattern
    )

    @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $Pattern } |
        Sort-Object FullName |
        Select-Object -First 1)[0]
}

function Test-DirectoryArtifact {
    param(
        [System.IO.DirectoryInfo]$Directory,
        [string]$Label,
        [string[]]$Patterns
    )

    if (-not $Directory) {
        return [ordered]@{
            label = $Label
            status = 'missing'
            detail = 'Parent folder was not found'
            path = ''
        }
    }

    $matches = @()
    foreach ($pattern in $Patterns) {
        $matches += @(Get-ChildItem -LiteralPath $Directory.FullName -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $pattern })
        $matches += @(Get-ChildItem -LiteralPath $Directory.FullName -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $pattern })
    }

    $first = $matches | Sort-Object FullName | Select-Object -First 1
    return [ordered]@{
        label = $Label
        status = if ($first) { 'found' } else { 'missing' }
        detail = if ($first) { "Found $($first.Name)" } else { "Expected one of: $($Patterns -join ', ')" }
        path = if ($first) { $first.FullName } else { $Directory.FullName }
    }
}

function Test-ExtractionState {
    param([string]$BundlePath)

    if ([string]::IsNullOrWhiteSpace($BundlePath)) {
        throw 'Bundle path is required'
    }
    if (-not (Test-Path -LiteralPath $BundlePath -PathType Container)) {
        throw "Bundle path was not found: $BundlePath"
    }

    $root = [System.IO.Path]::GetFullPath($BundlePath)
    $nutanixCentral = Find-FirstDirectory -Root $root -Pattern 'nutanix-central-*'
    $ncCpaas = Find-FirstDirectory -Root $root -Pattern 'nc-cpaas-*'
    $frameworkFolder = Find-FirstDirectory -Root $root -Pattern 'lcm_dark_site_bundle*'

    $checks = @(
        [ordered]@{
            label = 'Bundle root exists'
            status = 'found'
            detail = $root
            path = $root
        },
        [ordered]@{
            label = 'LCM framework extraction marker'
            status = if ($frameworkFolder) { 'found' } else { 'warning' }
            detail = if ($frameworkFolder) { "Found $($frameworkFolder.Name)" } else { 'No lcm_dark_site_bundle* folder detected; this can be acceptable if extracted content is flattened.' }
            path = if ($frameworkFolder) { $frameworkFolder.FullName } else { $root }
        },
        [ordered]@{
            label = 'Nutanix Central extracted folder'
            status = if ($nutanixCentral) { 'found' } else { 'missing' }
            detail = if ($nutanixCentral) { "Found $($nutanixCentral.Name)" } else { 'Expected nutanix-central-* extracted folder' }
            path = if ($nutanixCentral) { $nutanixCentral.FullName } else { $root }
        },
        [ordered]@{
            label = 'Nutanix Central CPaaS extracted folder'
            status = if ($ncCpaas) { 'found' } else { 'missing' }
            detail = if ($ncCpaas) { "Found $($ncCpaas.Name)" } else { 'Expected nc-cpaas-* extracted folder' }
            path = if ($ncCpaas) { $ncCpaas.FullName } else { $root }
        },
        (Test-DirectoryArtifact -Directory $nutanixCentral -Label 'Nutanix Central charts payload' -Patterns @('*charts-bundle*', '*charts*')),
        (Test-DirectoryArtifact -Directory $nutanixCentral -Label 'Nutanix Central images payload' -Patterns @('*images-bundle*', '*images*')),
        (Test-DirectoryArtifact -Directory $ncCpaas -Label 'CPaaS charts payload' -Patterns @('*charts-bundle*', '*charts*')),
        (Test-DirectoryArtifact -Directory $ncCpaas -Label 'CPaaS images payload' -Patterns @('*images-bundle*', '*images*'))
    )

    $missing = @($checks | Where-Object { $_.status -eq 'missing' })
    $warnings = @($checks | Where-Object { $_.status -eq 'warning' })
    $result = [ordered]@{
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        root = $root
        status = if ($missing.Count -gt 0) { 'blocked' } elseif ($warnings.Count -gt 0) { 'warning' } else { 'ready' }
        missingCount = $missing.Count
        warningCount = $warnings.Count
        checks = $checks
    }

    Save-JsonFile -Path (Get-ExtractionPath) -Body $result
    Write-AuditEvent -Action 'extraction.validate' -Status $result.status -Message "Extraction validation completed with $($result.missingCount) missing checks." -Details ([ordered]@{
        root = $result.root
        missingCount = $result.missingCount
        warningCount = $result.warningCount
    })
    return $result
}

function Invoke-UrlProbe {
    param(
        [string]$Url,
        [int]$TimeoutSec = 8,
        [switch]$AllowForbidden
    )

    try {
        $uri = [System.Uri]::new($Url)
        if ($uri.Scheme -notin @('http', 'https')) {
            throw 'Only http and https URLs are supported'
        }
        if (-not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
            throw 'Credentials in URLs are not allowed'
        }

        $lastError = ''
        foreach ($method in @('HEAD', 'GET')) {
            $probeResponse = $null
            try {
                $probeRequest = [System.Net.HttpWebRequest]::Create($uri.AbsoluteUri)
                $probeRequest.Method = $method
                $probeRequest.Timeout = $TimeoutSec * 1000
                $probeRequest.AllowAutoRedirect = $true
                $probeResponse = $probeRequest.GetResponse()
                return [ordered]@{
                    url = $uri.AbsoluteUri
                    status = 'reachable'
                    statusCode = [int]$probeResponse.StatusCode
                    contentLength = if ($probeResponse.ContentLength -ge 0) { [string]$probeResponse.ContentLength } else { '' }
                    warning = ''
                    error = ''
                }
            }
            catch [System.Net.WebException] {
                $lastError = $_.Exception.Message
                $probeResponse = $_.Exception.Response
                $statusCode = if ($probeResponse) { [int]$probeResponse.StatusCode } else { 0 }

                if ($AllowForbidden -and $statusCode -eq 403) {
                    return [ordered]@{
                        url = $uri.AbsoluteUri
                        status = 'reachable'
                        statusCode = 403
                        contentLength = ''
                        warning = 'Base URL returned 403 Forbidden. This is acceptable for an empty IIS directory when directory browsing is disabled.'
                        error = ''
                    }
                }

                if ($method -eq 'GET') {
                    return [ordered]@{
                        url = $uri.AbsoluteUri
                        status = 'unreachable'
                        statusCode = $statusCode
                        contentLength = ''
                        warning = ''
                        error = $lastError
                    }
                }
            }
            finally {
                if ($probeResponse) {
                    $probeResponse.Close()
                }
            }
        }
    }
    catch {
        return [ordered]@{
            url = $Url
            status = 'unreachable'
            statusCode = 0
            contentLength = ''
            warning = ''
            error = $_.Exception.Message
        }
    }
}

function Test-WebServerState {
    param(
        [string]$DarksiteUrl,
        [object]$Inventory
    )

    if ([string]::IsNullOrWhiteSpace($DarksiteUrl)) {
        throw 'Dark-site URL is required'
    }

    $baseUri = [System.Uri]::new($DarksiteUrl)
    if ($baseUri.Scheme -notin @('http', 'https')) {
        throw 'Dark-site URL must use http or https'
    }
    if (-not [string]::IsNullOrWhiteSpace($baseUri.UserInfo)) {
        throw 'Do not include credentials in the dark-site URL'
    }

    $base = $baseUri.AbsoluteUri
    if (-not $base.EndsWith('/')) {
        $base = "$base/"
    }

    $probes = @()
    $probes += Invoke-UrlProbe -Url $base -AllowForbidden

    $bundlePaths = @()
    if ($Inventory -and $Inventory.checks) {
        foreach ($check in $Inventory.checks) {
            if ($check.status -eq 'found' -and $check.latest -and $check.latest.name) {
                $localPath = [string]$check.latest.path
                $relativePath = ''
                if ($Inventory.root -and $localPath) {
                    $root = [System.IO.Path]::GetFullPath([string]$Inventory.root).TrimEnd('\', '/')
                    $fullPath = [System.IO.Path]::GetFullPath($localPath)
                    if ($fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $relativePath = $fullPath.Substring($root.Length).TrimStart('\', '/')
                    }
                }
                if ([string]::IsNullOrWhiteSpace($relativePath)) {
                    $relativePath = [string]$check.latest.name
                }
                $bundlePaths += $relativePath.Replace('\', '/')
            }
        }
    }

    foreach ($path in ($bundlePaths | Select-Object -Unique)) {
        $segments = $path.Split('/') | ForEach-Object { [System.Uri]::EscapeDataString($_) }
        $escaped = $segments -join '/'
        $probes += Invoke-UrlProbe -Url ([System.Uri]::new([System.Uri]$base, $escaped).AbsoluteUri)
    }

    $unreachable = @($probes | Where-Object { $_.status -ne 'reachable' })
    $result = [ordered]@{
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        darksiteUrl = $base
        status = if ($unreachable.Count -eq 0 -and $probes.Count -gt 1) { 'ready' } elseif ($unreachable.Count -eq 0) { 'warning' } else { 'blocked' }
        checkedCount = $probes.Count
        unreachableCount = $unreachable.Count
        probes = $probes
    }

    Save-JsonFile -Path (Get-WebValidationPath) -Body $result
    Write-AuditEvent -Action 'web.validate' -Status $result.status -Message "Web validation checked $($result.checkedCount) URL(s)." -Details ([ordered]@{
        darksiteUrl = $result.darksiteUrl
        checkedCount = $result.checkedCount
        unreachableCount = $result.unreachableCount
    })
    return $result
}

function Get-EvidenceList {
    $dir = Get-EvidenceDir
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $dir -File -Filter '*.md' |
        Sort-Object LastWriteTimeUtc -Descending |
        ForEach-Object {
            [ordered]@{
                name = $_.Name
                path = $_.FullName
                size = $_.Length
                createdAt = $_.LastWriteTimeUtc.ToString('o')
            }
        })
}

function New-RunbookMarkdown {
    param(
        [object]$Profile,
        [object]$Inventory,
        [object]$Extraction,
        [object]$WebValidation
    )

    $lines = @(
        '# LCM Dark Site Runbook',
        '',
        "Generated: $([DateTimeOffset]::UtcNow.ToString('o'))",
        '',
        '## Profile',
        "- Site: $([string](Get-JsonValue -Object $Profile -Name 'siteName' -Default ''))",
        "- Web server platform: $([string](Get-JsonValue -Object $Profile -Name 'webServerPlatform' -Default ''))",
        "- Local bundle path: $([string](Get-JsonValue -Object $Profile -Name 'bundlePath' -Default ''))",
        "- Dark-site URL: $([string](Get-JsonValue -Object $Profile -Name 'darksiteUrl' -Default ''))",
        '',
        '## Operator Flow',
        '1. Copy the Nutanix LCM dark-site source bundles to the local bundle path.',
        '2. Extract the Nutanix Central and CPaaS payloads into the same dark-site folder.',
        '3. Host the folder from the selected web server platform.',
        '4. Validate bundle inventory, extraction state, and web reachability from this console.',
        '5. Point Prism Central LCM dark-site configuration at the validated URL.',
        '6. Attach the evidence pack to the change record before production use.',
        '',
        '## Latest Validation',
        "- Inventory: $([string](Get-JsonValue -Object $Inventory -Name 'status' -Default 'not_scanned'))",
        "- Extraction: $([string](Get-JsonValue -Object $Extraction -Name 'status' -Default 'not_checked'))",
        "- Web server: $([string](Get-JsonValue -Object $WebValidation -Name 'status' -Default 'not_checked'))"
    )

    return ($lines -join [Environment]::NewLine)
}

function New-EvidencePack {
    $profile = Load-Profile
    $inventory = Load-Inventory
    $extraction = Load-JsonFile -Path (Get-ExtractionPath)
    $webValidation = Load-JsonFile -Path (Get-WebValidationPath)
    $runbook = New-RunbookMarkdown -Profile $profile -Inventory $inventory -Extraction $extraction -WebValidation $webValidation

    $dir = Get-EvidenceDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $baseName = "lcm-darksite-evidence-$stamp"
    $mdPath = Join-Path $dir "$baseName.md"
    $jsonPath = Join-Path $dir "$baseName.json"

    $markdown = @(
        '# LCM Dark Site Readiness Evidence',
        '',
        "Generated: $([DateTimeOffset]::UtcNow.ToString('o'))",
        '',
        '## Summary',
        "- Site: $([string](Get-JsonValue -Object $profile -Name 'siteName' -Default ''))",
        "- Inventory status: $([string](Get-JsonValue -Object $inventory -Name 'status' -Default 'not_scanned'))",
        "- Extraction status: $([string](Get-JsonValue -Object $extraction -Name 'status' -Default 'not_checked'))",
        "- Web validation status: $([string](Get-JsonValue -Object $webValidation -Name 'status' -Default 'not_checked'))",
        '',
        '## Runbook',
        '',
        $runbook
    ) -join [Environment]::NewLine

    $markdown | Set-Content -LiteralPath $mdPath -Encoding utf8
    Save-JsonFile -Path $jsonPath -Body ([ordered]@{
        generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
        profile = $profile
        inventory = $inventory
        extraction = $extraction
        webValidation = $webValidation
    })

    $result = [ordered]@{
        status = 'created'
        markdown = $mdPath
        manifest = $jsonPath
        runbook = $runbook
        evidence = Get-EvidenceList
    }
    Write-AuditEvent -Action 'evidence.create' -Status 'success' -Message 'Evidence pack created.' -Details ([ordered]@{
        markdown = $mdPath
        manifest = $jsonPath
    })
    return $result
}

function Handle-ApiRequest {
    param([System.Net.HttpListenerContext]$Context)

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath

    if ($path -eq '/api/health' -and $request.HttpMethod -eq 'GET') {
        Write-JsonResponse -Response $response -Body ([ordered]@{
            status = 'healthy'
            version = '0.1.0'
            dataDir = $DataDir
            profileConfigured = (Test-Path -LiteralPath (Get-ProfilePath) -PathType Leaf)
            inventoryAvailable = (Test-Path -LiteralPath (Get-InventoryPath) -PathType Leaf)
            extractionAvailable = (Test-Path -LiteralPath (Get-ExtractionPath) -PathType Leaf)
            webValidationAvailable = (Test-Path -LiteralPath (Get-WebValidationPath) -PathType Leaf)
        })
        return $true
    }

    if ($path -eq '/api/storage' -and $request.HttpMethod -eq 'GET') {
        Write-JsonResponse -Response $response -Body ([ordered]@{
            backend = 'json-file'
            status = 'healthy'
            dataDir = $DataDir
            auditPath = Get-AuditPath
            postgres = [ordered]@{
                configured = $false
                status = 'not_configured'
                note = 'PostgreSQL is recommended for a future multi-user deployment, but this MVP uses local JSON files.'
            }
        })
        return $true
    }

    if ($path -eq '/api/sites') {
        if ($request.HttpMethod -eq 'GET') {
            Write-JsonResponse -Response $response -Body (Get-GovernanceSummary)
            return $true
        }
        if ($request.HttpMethod -eq 'POST') {
            $payload = Read-JsonRequest -Request $request
            $site = New-DarkSiteTarget -Payload $payload
            Write-JsonResponse -Response $response -Body ([ordered]@{
                site = $site
                governance = Get-GovernanceSummary
            })
            return $true
        }
    }

    if ($path -eq '/api/active-site' -and $request.HttpMethod -eq 'POST') {
        $payload = Read-JsonRequest -Request $request
        $siteId = [string](Get-JsonValue -Object $payload -Name 'siteId')
        Write-JsonResponse -Response $response -Body (Select-DarkSiteTarget -SiteId $siteId)
        return $true
    }

    if ($path -eq '/api/helper-scripts' -and $request.HttpMethod -eq 'GET') {
        Write-JsonResponse -Response $response -Body ([ordered]@{
            scripts = @(Get-HelperScriptCatalog | ForEach-Object {
                [ordered]@{
                    name = $_.name
                    title = $_.title
                    platform = $_.platform
                    safety = $_.safety
                    downloadUrl = "/api/helper-script?name=$([System.Uri]::EscapeDataString($_.name))"
                }
            })
            note = 'Helper scripts are never executed by the console. Download and run them manually after review.'
        })
        return $true
    }

    if ($path -eq '/api/helper-script' -and $request.HttpMethod -eq 'GET') {
        $name = [string]$request.QueryString['name']
        $script = @(Get-HelperScriptCatalog | Where-Object { $_.name -eq $name }) | Select-Object -First 1
        if (-not $script) {
            Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{ error = 'Helper script not found or not approved for download' })
            return $true
        }
        Write-AuditEvent -Action 'helper.download' -Status 'success' -Message "Helper script downloaded: $name" -Details ([ordered]@{ name = $name })
        Write-TextResponse -Response $response -Body (Get-Content -LiteralPath $script.path -Raw) -ContentType 'text/plain; charset=utf-8' -DownloadName $script.name
        return $true
    }

    if ($path -eq '/api/audit' -and $request.HttpMethod -eq 'GET') {
        Write-JsonResponse -Response $response -Body ([ordered]@{
            events = @(Get-AuditEvents -Limit 100)
        })
        return $true
    }

    if ($path -eq '/api/users') {
        if ($request.HttpMethod -eq 'GET') {
            Write-JsonResponse -Response $response -Body ([ordered]@{
                users = @(Load-Users)
                roles = @('admin', 'operator', 'viewer')
                enforced = $false
                note = 'Users are persisted for RBAC planning. Authentication and authorization are not enforced in the localhost MVP.'
            })
            return $true
        }
        if ($request.HttpMethod -eq 'POST') {
            $payload = Read-JsonRequest -Request $request
            $user = New-LocalUser -Payload $payload
            Write-JsonResponse -Response $response -Body ([ordered]@{
                user = $user
                users = @(Load-Users)
            })
            return $true
        }
    }

    if ($path -eq '/api/backups') {
        if ($request.HttpMethod -eq 'GET') {
            Write-JsonResponse -Response $response -Body ([ordered]@{ backups = @(Get-BackupList) })
            return $true
        }
        if ($request.HttpMethod -eq 'POST') {
            Write-JsonResponse -Response $response -Body (New-StateBackup)
            return $true
        }
    }

    if ($path -eq '/api/restore' -and $request.HttpMethod -eq 'POST') {
        $payload = Read-JsonRequest -Request $request
        $name = [string](Get-JsonValue -Object $payload -Name 'name')
        Write-JsonResponse -Response $response -Body (Restore-StateBackup -Name $name)
        return $true
    }

    if ($path -eq '/api/profile') {
        if ($request.HttpMethod -eq 'GET') {
            Write-JsonResponse -Response $response -Body (Load-Profile)
            return $true
        }
        if ($request.HttpMethod -eq 'POST') {
            $payload = Read-JsonRequest -Request $request
            Write-JsonResponse -Response $response -Body (Save-Profile -Profile $payload)
            return $true
        }
    }

    if ($path -eq '/api/folder') {
        if ($request.HttpMethod -eq 'POST') {
            $payload = Read-JsonRequest -Request $request
            $bundlePath = [string](Get-JsonValue -Object $payload -Name 'bundlePath')
            Write-JsonResponse -Response $response -Body (Initialize-BundleFolder -BundlePath $bundlePath)
            return $true
        }
    }

    if ($path -eq '/api/inventory') {
        if ($request.HttpMethod -eq 'GET') {
            $inventory = Load-Inventory
            if ($inventory) {
                Write-JsonResponse -Response $response -Body $inventory
            }
            else {
                Write-JsonResponse -Response $response -Body ([ordered]@{ status = 'not_scanned'; checks = @(); bundles = @() })
            }
            return $true
        }
        if ($request.HttpMethod -eq 'POST') {
            $payload = Read-JsonRequest -Request $request
            $bundlePath = [string](Get-JsonValue -Object $payload -Name 'bundlePath')
            Write-JsonResponse -Response $response -Body (Scan-BundleInventory -BundlePath $bundlePath)
            return $true
        }
    }

    if ($path -eq '/api/inventory-history' -and $request.HttpMethod -eq 'GET') {
        Write-JsonResponse -Response $response -Body ([ordered]@{
            scans = @(Get-JsonLines -Path (Get-InventoryHistoryPath) -Limit 50)
        })
        return $true
    }

    if ($path -eq '/api/extraction') {
        if ($request.HttpMethod -eq 'GET') {
            $extraction = Load-JsonFile -Path (Get-ExtractionPath)
            if ($extraction) {
                Write-JsonResponse -Response $response -Body $extraction
            }
            else {
                Write-JsonResponse -Response $response -Body ([ordered]@{ status = 'not_checked'; checks = @() })
            }
            return $true
        }
        if ($request.HttpMethod -eq 'POST') {
            $payload = Read-JsonRequest -Request $request
            $bundlePath = [string](Get-JsonValue -Object $payload -Name 'bundlePath')
            Write-JsonResponse -Response $response -Body (Test-ExtractionState -BundlePath $bundlePath)
            return $true
        }
    }

    if ($path -eq '/api/web-validation') {
        if ($request.HttpMethod -eq 'GET') {
            $webValidation = Load-JsonFile -Path (Get-WebValidationPath)
            if ($webValidation) {
                Write-JsonResponse -Response $response -Body $webValidation
            }
            else {
                Write-JsonResponse -Response $response -Body ([ordered]@{ status = 'not_checked'; probes = @() })
            }
            return $true
        }
        if ($request.HttpMethod -eq 'POST') {
            $payload = Read-JsonRequest -Request $request
            $darksiteUrl = [string](Get-JsonValue -Object $payload -Name 'darksiteUrl')
            Write-JsonResponse -Response $response -Body (Test-WebServerState -DarksiteUrl $darksiteUrl -Inventory (Load-Inventory))
            return $true
        }
    }

    if ($path -eq '/api/evidence') {
        if ($request.HttpMethod -eq 'GET') {
            Write-JsonResponse -Response $response -Body ([ordered]@{ evidence = Get-EvidenceList })
            return $true
        }
        if ($request.HttpMethod -eq 'POST') {
            Write-JsonResponse -Response $response -Body (New-EvidencePack)
            return $true
        }
    }

    if ($path -eq '/api/runbook' -and $request.HttpMethod -eq 'GET') {
        Write-JsonResponse -Response $response -Body ([ordered]@{
            generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
            markdown = (New-RunbookMarkdown -Profile (Load-Profile) -Inventory (Load-Inventory) -Extraction (Load-JsonFile -Path (Get-ExtractionPath)) -WebValidation (Load-JsonFile -Path (Get-WebValidationPath)))
        })
        return $true
    }

    return $false
}

$ContentRoot = [System.IO.Path]::GetFullPath($ContentRoot)
if (-not (Test-Path -LiteralPath (Join-Path $ContentRoot 'index.html'))) {
    throw "Content root is invalid or missing index.html: $ContentRoot"
}

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $DataDir 'logs') | Out-Null

$prefix = "http://${BindAddress}:${Port}/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host "LCM Dark Site Orchestrator listening on $prefix"
Write-Host "Content root: $ContentRoot"
Write-Host "Data directory: $DataDir"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $response = $context.Response
        $response.Headers.Add('X-Content-Type-Options', 'nosniff')
        $response.Headers.Add('Referrer-Policy', 'no-referrer')

        try {
            if ($context.Request.Url.AbsolutePath.StartsWith('/api/', [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not (Handle-ApiRequest -Context $context)) {
                    Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{ error = 'API endpoint not found' })
                }
            }
            else {
                $filePath = Resolve-SafePath -Root $ContentRoot -RequestPath $context.Request.Url.AbsolutePath
                if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                    $response.StatusCode = 404
                    $body = [System.Text.Encoding]::UTF8.GetBytes('Not found')
                    $response.OutputStream.Write($body, 0, $body.Length)
                }
                else {
                    $bytes = [System.IO.File]::ReadAllBytes($filePath)
                    $response.ContentType = Get-ContentType -Path $filePath
                    $response.ContentLength64 = $bytes.Length
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                }
            }
        }
        catch {
            if ($context.Request.Url.AbsolutePath.StartsWith('/api/', [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{ error = $_.Exception.Message })
            }
            else {
                $response.StatusCode = 400
                $body = [System.Text.Encoding]::UTF8.GetBytes('Bad request')
                $response.OutputStream.Write($body, 0, $body.Length)
            }
        }
        finally {
            $response.OutputStream.Close()
        }
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
