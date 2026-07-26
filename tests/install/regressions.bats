#!/usr/bin/env bats
# One test per shipped defect. Each fails against the commit before its fix.

load helpers/load
load helpers/server

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    INSTALL_SH="$REPO_ROOT/.github/scripts/install.sh"

    SRV="$BATS_TEST_TMPDIR/srv"
    mkdir -p "$SRV"

    local _out
    _out="$(server_start "$SRV" "$BATS_TEST_TMPDIR/server.log")" || {
        echo "$_out"
        return 1
    }
    SERVER_PID="${_out%% *}"
    SERVER_PORT="${_out##* }"

    export RUNNER_TEMP="$BATS_TEST_TMPDIR/runner-temp"
    mkdir -p "$RUNNER_TEMP"
    export GITHUB_PATH="$BATS_TEST_TMPDIR/github-path"
    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github-output"
    : >"$GITHUB_PATH"
    : >"$GITHUB_OUTPUT"
    CURL_CA_BUNDLE="$(server_ca_bundle)"
    export CURL_CA_BUNDLE

    export GRIM_RELEASE_BASE_URL="https://127.0.0.1:$SERVER_PORT"
    export GRIM_SETUP_VERSION="v0.0.0"
    export GRIM_RELEASE_AUTH_HEADER=""
}

teardown() {
    server_stop "${SERVER_PID:-}"
}

# bats test_tags=slow
@test "an archive with thousands of matching entries does not fail with SIGPIPE" {
    # `x="$(find ... | head -1)"` under `set -o pipefail` returns 141 as soon as
    # find's output outruns the 64 KiB pipe buffer and head exits first. 4000
    # entries named grim is ~136 KiB of find output — over twice the buffer on
    # every platform, so this is deterministic, not a race. Measured on bash
    # 5.3: 348 KB of producer output failed 3/3, 79 KB passed 3/3.
    server_build_release "$SRV" v0.0.0 tar.xz 4000 >/dev/null

    run bash "$INSTALL_SH"
    assert_success

    run "$RUNNER_TEMP/grim-bin/grim" --version
    assert_output "grim 0.0.0"
}

@test "a truncated .tar.xz (200 with an empty body) falls through to .tar.gz" {
    # A 404 is already handled — curl's exit code drives the fallback. The
    # observable defect is a mirror that answers 200 with nothing: curl exits 0,
    # the empty file is accepted as the asset, and tar explodes with no
    # annotation. The sidecar below matches the empty file, so pre-fix the run
    # gets all the way to tar rather than tripping over a missing checksum.
    server_build_release "$SRV" v0.0.0 tar.gz >/dev/null

    local stem empty
    stem="$(server_detect_stem)"
    empty="$BATS_TEST_TMPDIR/$stem.tar.xz"
    : >"$empty"
    server_publish "$SRV" v0.0.0 "$empty"

    run bash "$INSTALL_SH"
    assert_success

    run "$RUNNER_TEMP/grim-bin/grim" --version
    assert_output "grim 0.0.0"
}
