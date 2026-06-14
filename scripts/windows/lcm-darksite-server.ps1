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
        catch {
            $response.StatusCode = 400
            $body = [System.Text.Encoding]::UTF8.GetBytes('Bad request')
            $response.OutputStream.Write($body, 0, $body.Length)
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
