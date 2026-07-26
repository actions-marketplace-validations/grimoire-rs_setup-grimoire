#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
# One test per shipped defect in .github/scripts/install.ps1. Each fails against
# the commit before its fix.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'Fixture.psm1') -Force
    $script:InstallPs1 = Join-Path $PSScriptRoot '../../../.github/scripts/install.ps1'
}

Describe 'install.ps1 regressions' {
    BeforeEach {
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) "grim-rg-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
        $script:Runner = New-FixtureRunnerEnv -Root $Root
        $script:Asset = New-GrimFixture -Root $Root
        $script:Srv = Start-FixtureServer -Root $Root
        $env:GRIM_RELEASE_BASE_URL = $Srv.BaseUrl
        $env:GRIM_SETUP_VERSION = 'v0.0.0'
        $env:GRIM_RELEASE_AUTH_HEADER = ''
    }
    AfterEach {
        Stop-FixtureServer -Server $Srv
        Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
    }

    It 'removes its temp dir after a successful install' {
        & pwsh -NoProfile -File $InstallPs1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        @(Get-ChildItem -Path $Runner.RunnerTemp -Filter 'grim-setup-*') | Should -BeNullOrEmpty
    }

    It 'removes its temp dir after a failed install' {
        New-GrimFixture -Root $Root -TamperChecksum | Out-Null

        & pwsh -NoProfile -File $InstallPs1 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        @(Get-ChildItem -Path $Runner.RunnerTemp -Filter 'grim-setup-*') | Should -BeNullOrEmpty
    }

    It 'retries a transient 503 instead of failing the install' {
        Set-Content -Path $Srv.FlakyFile -Value '.zip' -NoNewline

        & pwsh -NoProfile -File $InstallPs1 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        (Join-Path $Runner.InstallDir 'grim.exe') | Should -Exist
    }
}
