#!/usr/bin/env bats
# Happy paths of .github/scripts/install.sh, driven against the HTTPS fixture
# release server. Nothing is stubbed on PATH: the real curl, tar and find run
# against a real (localhost) mirror, so what is under test is the shipped code.

load helpers/load
load helpers/server

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    INSTALL_SH="$REPO_ROOT/.github/scripts/install.sh"

    SRV="$BATS_TEST_TMPDIR/srv"
    mkdir -p "$SRV"

    HEADER_LOG="$BATS_TEST_TMPDIR/headers.log"
    : >"$HEADER_LOG"
    export GRIM_FIXTURE_HEADER_LOG="$HEADER_LOG"

    local _out
    _out="$(server_start "$SRV" "$BATS_TEST_TMPDIR/server.log")" || {
        echo "$_out"
        return 1
    }
    SERVER_PID="${_out%% *}"
    SERVER_PORT="${_out##* }"

    # What the action's step gives the script: three inputs and the runner's
    # own environment. GITHUB_PATH and GITHUB_OUTPUT are files later steps read.
    export RUNNER_TEMP="$BATS_TEST_TMPDIR/runner-temp"
    mkdir -p "$RUNNER_TEMP"
    export GITHUB_PATH="$BATS_TEST_TMPDIR/github-path"
    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github-output"
    : >"$GITHUB_PATH"
    : >"$GITHUB_OUTPUT"
    # Trusts the one vendored fixture cert; does NOT disable TLS verification.
    CURL_CA_BUNDLE="$(server_ca_bundle)"
    export CURL_CA_BUNDLE

    export GRIM_RELEASE_BASE_URL="https://127.0.0.1:$SERVER_PORT"
    export GRIM_SETUP_VERSION="v0.0.0"
    export GRIM_RELEASE_AUTH_HEADER=""
}

teardown() {
    server_stop "${SERVER_PID:-}"
}

@test "installs a pinned version and appends the bin dir to GITHUB_PATH" {
    server_build_release "$SRV" v0.0.0 >/dev/null

    run bash "$INSTALL_SH"
    assert_success

    assert [ -x "$RUNNER_TEMP/grim-bin/grim" ]
    run cat "$GITHUB_PATH"
    assert_output "$RUNNER_TEMP/grim-bin"

    run "$RUNNER_TEMP/grim-bin/grim" --version
    assert_output "grim 0.0.0"
}

@test "installs a prerelease tag" {
    server_build_release "$SRV" v0.0.0-rc.1 >/dev/null
    export GRIM_SETUP_VERSION="v0.0.0-rc.1"

    run bash "$INSTALL_SH"
    assert_success
    assert [ -x "$RUNNER_TEMP/grim-bin/grim" ]
}

@test "installs 'latest' from the latest/download path" {
    server_build_release "$SRV" v0.0.0 >/dev/null
    export GRIM_SETUP_VERSION="latest"

    run bash "$INSTALL_SH"
    assert_success
    assert [ -x "$RUNNER_TEMP/grim-bin/grim" ]
}

@test "falls back to .tar.gz when the .tar.xz asset is missing" {
    server_build_release "$SRV" v0.0.0 tar.gz >/dev/null

    run bash "$INSTALL_SH"
    assert_success
    assert [ -x "$RUNNER_TEMP/grim-bin/grim" ]
}

@test "sends the auth header to the mirror and never leaks it" {
    # A fixture value, never a real secret.
    local canary="grim-fixture-canary-7f3a"
    export GRIM_RELEASE_AUTH_HEADER="PRIVATE-TOKEN: $canary"
    server_build_release "$SRV" v0.0.0 >/dev/null

    run bash "$INSTALL_SH"
    assert_success

    # 1. Positive control. Without it the leak assertions below are vacuous:
    #    a script that never sends the header also never leaks it.
    run grep -c "PRIVATE-TOKEN: $canary" "$HEADER_LOG"
    assert_success

    # 2. Never on the step's own output. `run` merges stdout and stderr, so
    #    this covers every stream the workflow log surfaces.
    run bash "$INSTALL_SH"
    refute_output --partial "$canary"

    # 3. Never in the two files that persist into later steps.
    run cat "$GITHUB_PATH" "$GITHUB_OUTPUT"
    refute_output --partial "$canary"
}

@test "sends no auth header when the input is empty" {
    server_build_release "$SRV" v0.0.0 >/dev/null

    run bash "$INSTALL_SH"
    assert_success

    run grep -ci "PRIVATE-TOKEN" "$HEADER_LOG"
    assert_output "0"
}
