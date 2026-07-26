# Install the grim CLI on a Windows runner: download the release .zip for the
# host architecture, verify it against the cargo-dist .sha256 sidecar, and put
# the binary on PATH through $env:GITHUB_PATH.
#
# Inputs arrive as environment variables set by action.yml (GRIM_SETUP_VERSION,
# GRIM_RELEASE_BASE_URL, GRIM_RELEASE_AUTH_HEADER) rather than as parameters,
# so the step's `env:` block stays the single place they are named.
$ErrorActionPreference = 'Stop'

# The shape the `version:` input accepts, named once so the check and the
# annotation that explains it cannot drift apart.
#
# This governs WHICH GRIM RELEASE IS INSTALLED. It is unrelated to
# setup-grimoire's own release-tag filter in .github/workflows/release.yml,
# which deliberately excludes prereleases and the moving v1 tag. Two
# same-looking regexes, two different purposes, two different files. Loosening
# one must not loosen the other.
$VersionPattern = '^v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$'

$version = if ($env:GRIM_SETUP_VERSION) { $env:GRIM_SETUP_VERSION } else { 'latest' }
if ($version -ne 'latest' -and $version -notmatch $VersionPattern) {
    Write-Host "::error::version '$version' must be 'latest' or vX.Y.Z[-prerelease]"
    exit 1
}
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
$asset = "grimoire-$arch-pc-windows-msvc.zip"
$base = if ($env:GRIM_RELEASE_BASE_URL) { $env:GRIM_RELEASE_BASE_URL } else { 'https://github.com/grimoire-rs/grimoire/releases' }
$url = if ($version -eq 'latest') { "$base/latest/download/$asset" } else { "$base/download/$version/$asset" }
$headers = @{}
if ($env:GRIM_RELEASE_AUTH_HEADER) {
    $name, $value = $env:GRIM_RELEASE_AUTH_HEADER -split ':', 2
    $headers[$name.Trim()] = $value.Trim()
}

$tmp = Join-Path $env:RUNNER_TEMP ("grim-setup-" + [System.Guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
# PowerShell 6+ only, which the action guarantees: the step runs `pwsh`
# explicitly, never Windows PowerShell 5.1. Note the asymmetry with install.sh:
# PowerShell retries 404s too, which is harmless here because there is exactly
# one Windows asset and so no extension fallback to stall.
Invoke-WebRequest -Uri $url -Headers $headers -OutFile (Join-Path $tmp $asset) -MaximumRetryCount 3 -RetryIntervalSec 2
Invoke-WebRequest -Uri "$url.sha256" -Headers $headers -OutFile (Join-Path $tmp "$asset.sha256") -MaximumRetryCount 3 -RetryIntervalSec 2
$expected = (Get-Content (Join-Path $tmp "$asset.sha256") -Raw).Split(' ')[0].Trim()
$actual = (Get-FileHash (Join-Path $tmp $asset) -Algorithm SHA256).Hash.ToLower()
if ($expected.ToLower() -ne $actual) {
    Write-Host "::error::checksum mismatch for $asset"
    exit 1
}

Expand-Archive -Path (Join-Path $tmp $asset) -DestinationPath $tmp
$found = Get-ChildItem -Path $tmp -Recurse -Filter grim.exe | Select-Object -First 1
if (-not $found) {
    Write-Host "::error::no grim.exe in $asset"
    exit 1
}
$installDir = Join-Path $env:RUNNER_TEMP 'grim-bin'
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item $found.FullName (Join-Path $installDir 'grim.exe')
Add-Content -Path $env:GITHUB_PATH -Value $installDir
