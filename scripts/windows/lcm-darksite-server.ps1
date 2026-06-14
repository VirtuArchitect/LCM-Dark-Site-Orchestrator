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
