#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
# Failure paths of .github/scripts/install.ps1: exit code plus the EXACT
# ::error:: annotation text, which is the action's user-facing contract.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'Fixture.psm1') -Force
    $script:InstallPs1 = Join-Path $PSScriptRoot '../../../.github/scripts/install.ps1'
}

Describe 'install.ps1 failure paths' {
    BeforeEach {
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) "grim-ec-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
        $script:Runner = New-FixtureRunnerEnv -Root $Root
        $script:Asset = Get-FixtureAsset
        $env:GRIM_SETUP_VERSION = 'v0.0.0'
        $env:GRIM_RELEASE_AUTH_HEADER = ''
    }
    AfterEach {
        if ($script:Srv) { Stop-FixtureServer -Server $script:Srv; $script:Srv = $null }
        Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
    }

    It 'rejects a malformed version input' {
        $env:GRIM_SETUP_VERSION = 'v1.2'
        $env:GRIM_RELEASE_BASE_URL = 'https://example.invalid/releases'
        $out = & pwsh -NoProfile -File $InstallPs1 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out.Trim() | Should -Be "::error::version 'v1.2' must be 'latest' or vX.Y.Z"
    }

    It 'rejects a version that is not a tag at all' {
        $env:GRIM_SETUP_VERSION = 'main'
        $env:GRIM_RELEASE_BASE_URL = 'https://example.invalid/releases'
        $out = & pwsh -NoProfile -File $InstallPs1 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out.Trim() | Should -Be "::error::version 'main' must be 'latest' or vX.Y.Z"
    }

    It 'aborts on a checksum mismatch' {
        New-GrimFixture -Root $Root -TamperChecksum | Out-Null
        $script:Srv = Start-FixtureServer -Root $Root
        $env:GRIM_RELEASE_BASE_URL = $Srv.BaseUrl

        $out = & pwsh -NoProfile -File $InstallPs1 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out.Trim() | Should -Be "::error::checksum mismatch for $Asset"
        (Join-Path $Runner.InstallDir 'grim.exe') | Should -Not -Exist
    }

    It 'aborts when the archive contains no grim.exe' {
        New-GrimFixture -Root $Root -NoBinary | Out-Null
        $script:Srv = Start-FixtureServer -Root $Root
        $env:GRIM_RELEASE_BASE_URL = $Srv.BaseUrl

        $out = & pwsh -NoProfile -File $InstallPs1 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match "::error::no grim.exe in $([regex]::Escape($Asset))"
    }

    It 'fails when the release asset is missing' {
        # No fixture published: Invoke-WebRequest throws, $ErrorActionPreference
        # 'Stop' makes it terminating, and the child pwsh exits non-zero. There
        # is no ::error:: for this path — the exception message is the report.
        $script:Srv = Start-FixtureServer -Root $Root
        $env:GRIM_RELEASE_BASE_URL = $Srv.BaseUrl

        & pwsh -NoProfile -File $InstallPs1 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        (Join-Path $Runner.InstallDir 'grim.exe') | Should -Not -Exist
    }
}
