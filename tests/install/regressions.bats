#!/usr/bin/env bats
# One test per shipped defect. Each fails against the commit before its fix.

load helpers/load
load helpers/server

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    INSTALL_SH="$REPO_ROOT/.github/scripts/install.sh"

    SRV="$BATS_TEST_TMPDIR/srv"
    mkdir -p "$SRV"

    # Armed by writing a path fragment into it; see helpers/server.bash.
    FLAKY_ONCE="$BATS_TEST_TMPDIR/flaky-once"
    export GRIM_FIXTURE_FLAKY_ONCE="$FLAKY_ONCE"

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

@test "an uppercase checksum in the sidecar still verifies" {
    # sha256sum and shasum both print lowercase, but nothing says a mirror's
    # sidecar must. install.ps1 has always lowercased both sides; bash compared
    # the two strings raw, so an uppercase sidecar failed the install with a
    # checksum-mismatch annotation on a file that was in fact intact.
    local asset sum
    asset="$(server_build_release "$SRV" v0.0.0)"
    sum="$(server_sha256 "$SRV/download/v0.0.0/$asset" | tr 'a-f' 'A-F')"
    printf '%s  %s\n' "$sum" "$asset" >"$SRV/download/v0.0.0/$asset.sha256"

    run bash "$INSTALL_SH"
    assert_success

    run "$RUNNER_TEMP/grim-bin/grim" --version
    assert_output "grim 0.0.0"
}

@test "a transient 503 on the archive is retried, not treated as missing" {
    # Only .tar.xz is published, and the mirror 503s the first request for it.
    # Without --retry that is indistinguishable from a missing asset: the loop
    # moves on to .tar.gz, 404s, and the run dies claiming no archive exists.
    server_build_release "$SRV" v0.0.0 tar.xz >/dev/null
    printf '.tar.xz' >"$FLAKY_ONCE"

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
