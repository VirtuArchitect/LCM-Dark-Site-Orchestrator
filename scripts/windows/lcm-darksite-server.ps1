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
    if ($lower -match '^lcm_msp_.*\.tar\.gz$') { return 'msp' }
    if ($lower -eq 'nutanix_compatibility_bundle.tar.gz') { return 'compatibility' }
    if ($lower -match '^lcm-darksite-nutanix-central-.*\.tar\.gz$') { return 'nutanixCentralDarksite' }
    if ($lower -match '^lcm_marketplace_bundle_.*\.tar\.gz$') { return 'marketplace' }
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
        name = $File.Name
        path = $File.FullName
        size = $File.Length
        modifiedAt = $File.LastWriteTimeUtc.ToString('o')
        version = Find-Version -Name $File.Name
        sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
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

    $records = @()
    foreach ($file in $files) {
        $record = New-BundleRecord -File $file
        if ($record) {
            $records += $record
        }
    }

    $required = @(
        [ordered]@{ type = 'lcmFramework'; label = 'LCM framework bundle'; pattern = 'lcm_dark_site_bundle_*.tar.gz' },
        [ordered]@{ type = 'msp'; label = 'MSP LCM bundle'; pattern = 'lcm_msp_*.tar.gz' },
        [ordered]@{ type = 'compatibility'; label = 'Compatibility bundle'; pattern = 'nutanix_compatibility_bundle.tar.gz' },
        [ordered]@{ type = 'nutanixCentralDarksite'; label = 'Nutanix Central dark-site bundle'; pattern = 'lcm-darksite-nutanix-central-*.tar.gz' },
        [ordered]@{ type = 'marketplace'; label = 'Marketplace dark-site bundle'; pattern = 'lcm_marketplace_bundle_*.tar.gz' }
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
    return $result
}

function Invoke-UrlProbe {
    param(
        [string]$Url,
        [int]$TimeoutSec = 8
    )

    try {
        $uri = [System.Uri]::new($Url)
        if ($uri.Scheme -notin @('http', 'https')) {
            throw 'Only http and https URLs are supported'
        }
        if (-not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
            throw 'Credentials in URLs are not allowed'
        }

        try {
            $result = Invoke-WebRequest -Uri $uri.AbsoluteUri -Method Head -TimeoutSec $TimeoutSec -UseBasicParsing
        }
        catch {
            $result = Invoke-WebRequest -Uri $uri.AbsoluteUri -Method Get -TimeoutSec $TimeoutSec -UseBasicParsing
        }

        return [ordered]@{
            url = $uri.AbsoluteUri
            status = 'reachable'
            statusCode = [int]$result.StatusCode
            contentLength = if ($result.Headers['Content-Length']) { [string]$result.Headers['Content-Length'] } else { '' }
            error = ''
        }
    }
    catch {
        return [ordered]@{
            url = $Url
            status = 'unreachable'
            statusCode = 0
            contentLength = ''
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
    $probes += Invoke-UrlProbe -Url $base

    $bundleNames = @()
    if ($Inventory -and $Inventory.checks) {
        foreach ($check in $Inventory.checks) {
            if ($check.status -eq 'found' -and $check.latest -and $check.latest.name) {
                $bundleNames += [string]$check.latest.name
            }
        }
    }

    foreach ($name in ($bundleNames | Select-Object -Unique)) {
        $escaped = [System.Uri]::EscapeDataString($name).Replace('%2F', '/')
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

    return [ordered]@{
        status = 'created'
        markdown = $mdPath
        manifest = $jsonPath
        runbook = $runbook
        evidence = Get-EvidenceList
    }
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
