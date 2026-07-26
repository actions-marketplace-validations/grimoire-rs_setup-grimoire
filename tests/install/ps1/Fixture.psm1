# Shared Pester fixtures for .github/scripts/install.ps1 — the PowerShell
# analogue of ../helpers/server.bash. Builds a fake grim release (a .zip plus
# its .sha256 sidecar) and serves it from `python http.server` so install.ps1
# runs end to end with no network access.
#
# The server speaks plain HTTP, not HTTPS: install.ps1 uses Invoke-WebRequest,
# which enforces no scheme of its own, so there is no TLS dance to reproduce.
# (install.sh does enforce https, which is why its fixture server does not.)
#
# The suites run install.ps1 as a child process (`pwsh -NoProfile -File`), the
# same way action.yml invokes it, so no mocking, dot-source guard or function
# restructuring is needed and $LASTEXITCODE is the real exit code.

# Asset name for the host. Mirrors install.ps1's expression exactly, including
# the `else` branch — $env:PROCESSOR_ARCHITECTURE is unset on Linux and macOS,
# so both the script and this resolve x86_64 there.
function Get-FixtureAsset {
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
    return "grimoire-$arch-pc-windows-msvc.zip"
}

function Get-PythonExe {
    foreach ($name in @('python3', 'python')) {
        if (Get-Command $name -ErrorAction SilentlyContinue) { return $name }
    }
    throw 'No python3/python interpreter found on PATH for the fixture server.'
}

# Publish $File plus a .sha256 sidecar under both release layouts install.ps1
# knows: download/<tag>/ and latest/download/. -Sha overrides the checksum
# written to the sidecar, which is how the mismatch test lies about it.
function Publish-FixtureAsset {
    param(
        [Parameter(Mandatory)][string]$SrvRoot,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$File,
        [string]$Sha
    )
    if (-not $Sha) { $Sha = (Get-FileHash -Path $File -Algorithm SHA256).Hash.ToLower() }
    $name = Split-Path $File -Leaf
    foreach ($dir in @((Join-Path $SrvRoot "download/$Tag"), (Join-Path $SrvRoot 'latest/download'))) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Copy-Item $File (Join-Path $dir $name) -Force
        Set-Content -Path (Join-Path $dir "$name.sha256") -Value "$Sha  $name" -Encoding ASCII
    }
}

# Build the release .zip under $Root and publish it. -NoBinary ships an archive
# with no grim.exe in it; -TamperChecksum publishes a sidecar that cannot match.
# Returns the asset filename.
function New-GrimFixture {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Tag = 'v0.0.0',
        [switch]$NoBinary,
        [switch]$TamperChecksum
    )
    $asset = Get-FixtureAsset
    $build = Join-Path $Root 'build'
    New-Item -ItemType Directory -Path $build -Force | Out-Null
    if ($NoBinary) {
        Set-Content -Path (Join-Path $build 'README.txt') -Value 'no binary here' -Encoding ASCII
    }
    else {
        # Never executed by the tests — install.ps1 only copies it. The action's
        # separate `report` step is what actually runs grim.
        Set-Content -Path (Join-Path $build 'grim.exe') -Value 'fixture grim' -Encoding ASCII
    }

    $archive = Join-Path $Root $asset
    Compress-Archive -Path (Join-Path $build '*') -DestinationPath $archive -Force

    $srvRoot = Join-Path $Root 'srv'
    $sha = if ($TamperChecksum) { '0' * 64 } else { '' }
    Publish-FixtureAsset -SrvRoot $srvRoot -Tag $Tag -File $archive -Sha $sha
    return $asset
}

# Spin a python http.server against <Root>/srv. Returns @{ Process; Port;
# BaseUrl; HeaderLog }. Every request's headers are appended to HeaderLog, which
# is how the auth-header positive control is asserted.
function Start-FixtureServer {
    param([Parameter(Mandatory)][string]$Root)

    $srvRoot = Join-Path $Root 'srv'
    New-Item -ItemType Directory -Path $srvRoot -Force | Out-Null
    $python = Get-PythonExe
    $outLog = Join-Path $Root 'srv.out.log'
    $errLog = Join-Path $Root 'srv.err.log'
    $headerLog = Join-Path $Root 'headers.log'
    Set-Content -Path $headerLog -Value '' -NoNewline

    $serverPy = Join-Path $Root 'fixture-server.py'
    $pyBody = @'
import http.server, os, socketserver

header_log = os.environ["GRIM_FIXTURE_HEADER_LOG"]

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        with open(header_log, "a") as fh:
            fh.write("%s %s\n%s\n" % (self.command, self.path, self.headers))
        return super().do_GET()

with socketserver.TCPServer(('127.0.0.1', 0), Handler) as httpd:
    print('Serving HTTP on 127.0.0.1 port %d' % httpd.server_address[1], flush=True)
    httpd.serve_forever()
'@
    [System.IO.File]::WriteAllText($serverPy, $pyBody)

    $env:GRIM_FIXTURE_HEADER_LOG = $headerLog
    $proc = Start-Process -FilePath $python `
        -ArgumentList '-u', $serverPy `
        -WorkingDirectory $srvRoot `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog `
        -PassThru

    $port = $null
    for ($i = 0; $i -lt 100; $i++) {
        foreach ($lf in @($outLog, $errLog)) {
            if (Test-Path $lf) {
                $content = Get-Content $lf -Raw -ErrorAction SilentlyContinue
                if ($content -match 'port (\d+)') { $port = $Matches[1]; break }
            }
        }
        if ($port) { break }
        Start-Sleep -Milliseconds 100
    }
    if (-not $port) {
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        throw "Failed to start fixture server (logs: $outLog / $errLog)"
    }

    return @{
        Process   = $proc
        Port      = $port
        BaseUrl   = "http://127.0.0.1:$port"
        HeaderLog = $headerLog
    }
}

function Stop-FixtureServer {
    param($Server)
    if ($Server -and $Server.Process -and -not $Server.Process.HasExited) {
        Stop-Process -Id $Server.Process.Id -Force -ErrorAction SilentlyContinue
    }
}

# Fake the runner environment install.ps1 reads: RUNNER_TEMP to install into,
# GITHUB_PATH as the file later steps pick PATH up from.
function New-FixtureRunnerEnv {
    param([Parameter(Mandatory)][string]$Root)
    $runnerTemp = Join-Path $Root 'runner-temp'
    New-Item -ItemType Directory -Path $runnerTemp -Force | Out-Null
    $githubPath = Join-Path $Root 'github-path'
    $githubOutput = Join-Path $Root 'github-output'
    Set-Content -Path $githubPath -Value '' -NoNewline
    Set-Content -Path $githubOutput -Value '' -NoNewline
    $env:RUNNER_TEMP = $runnerTemp
    $env:GITHUB_PATH = $githubPath
    $env:GITHUB_OUTPUT = $githubOutput
    return @{
        RunnerTemp   = $runnerTemp
        GithubPath   = $githubPath
        GithubOutput = $githubOutput
        InstallDir   = (Join-Path $runnerTemp 'grim-bin')
    }
}

Export-ModuleMember -Function `
    Get-FixtureAsset, Get-PythonExe, Publish-FixtureAsset, New-GrimFixture, `
    Start-FixtureServer, Stop-FixtureServer, New-FixtureRunnerEnv
