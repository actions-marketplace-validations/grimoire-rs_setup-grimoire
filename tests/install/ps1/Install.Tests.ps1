#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
# Happy paths of .github/scripts/install.ps1, run as a child process against a
# real localhost fixture server — the same invocation action.yml uses.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'Fixture.psm1') -Force
    $script:InstallPs1 = Join-Path $PSScriptRoot '../../../.github/scripts/install.ps1'
}

Describe 'install.ps1' {
    BeforeEach {
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) "grim-it-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
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

    It 'installs a pinned version and appends the bin dir to GITHUB_PATH' {
        & pwsh -NoProfile -File $InstallPs1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        (Join-Path $Runner.InstallDir 'grim.exe') | Should -Exist
        (Get-Content $Runner.GithubPath -Raw).Trim() | Should -Be $Runner.InstallDir
    }

    It "installs 'latest' from the latest/download path" {
        $env:GRIM_SETUP_VERSION = 'latest'
        & pwsh -NoProfile -File $InstallPs1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        (Join-Path $Runner.InstallDir 'grim.exe') | Should -Exist
    }

    It 'sends the auth header to the mirror and never leaks it' {
        # A fixture value, never a real secret.
        $canary = 'grim-fixture-canary-7f3a'
        $env:GRIM_RELEASE_AUTH_HEADER = "PRIVATE-TOKEN: $canary"

        $out = & pwsh -NoProfile -File $InstallPs1 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0

        # 1. Positive control. Without it the leak assertions are vacuous: a
        #    script that never sends the header also never leaks it.
        (Get-Content $Srv.HeaderLog -Raw) | Should -Match "PRIVATE-TOKEN: $canary"

        # 2. Never on the step's own output (stdout and stderr merged).
        $out | Should -Not -Match $canary

        # 3. Never in the files that persist into later steps.
        ((Get-Content $Runner.GithubPath -Raw) + (Get-Content $Runner.GithubOutput -Raw)) |
            Should -Not -Match $canary
    }

    It 'sends no auth header when the input is empty' {
        & pwsh -NoProfile -File $InstallPs1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        (Get-Content $Srv.HeaderLog -Raw) | Should -Not -Match 'PRIVATE-TOKEN'
    }
}
