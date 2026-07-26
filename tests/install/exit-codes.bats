#!/usr/bin/env bats
# Every failure path of .github/scripts/install.sh, asserted on the EXACT
# ::error:: annotation text and the exit code. Those annotations are the
# action's user-facing contract — a reworded one is a breaking change, so the
# assertions are literal, not --partial.

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

@test "rejects a malformed version input" {
    export GRIM_SETUP_VERSION="v1.2"

    run bash "$INSTALL_SH"
    assert_failure 1
    assert_output "::error::version 'v1.2' must be 'latest' or vX.Y.Z[-prerelease]"
}

@test "rejects a version that is not a tag at all" {
    export GRIM_SETUP_VERSION="main"

    run bash "$INSTALL_SH"
    assert_failure 1
    assert_output "::error::version 'main' must be 'latest' or vX.Y.Z[-prerelease]"
}

@test "rejects an unsupported platform" {
    # The one case that needs a PATH stub: uname cannot otherwise be coerced,
    # and no GitHub runner is a SunOS host.
    local stub="$BATS_TEST_TMPDIR/stub"
    mkdir -p "$stub"
    cat >"$stub/uname" <<'EOF'
#!/bin/sh
case "$1" in
    -s) echo SunOS ;;
    -m) echo sun4v ;;
esac
EOF
    chmod +x "$stub/uname"
    PATH="$stub:$PATH"

    run bash "$INSTALL_SH"
    assert_failure 1
    assert_output "::error::unsupported platform: SunOS/sun4v"
}

@test "aborts when neither archive extension is published" {
    local stem
    stem="$(server_detect_stem)"

    run bash "$INSTALL_SH"
    assert_failure 1
    # assert_line, not assert_output: curl's own `-S` 404 lines share the merged
    # stream. The annotation is still matched in full, as its own line.
    assert_line "::error::no archive found for $stem (.tar.xz or .tar.gz)"
}

@test "aborts on a checksum mismatch" {
    local asset
    asset="$(server_build_release "$SRV" v0.0.0)"
    # Republish the sidecar with a checksum that cannot match anything.
    printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" \
        "$asset" >"$SRV/download/v0.0.0/$asset.sha256"

    run bash "$INSTALL_SH"
    assert_failure 1
    assert_output "::error::checksum mismatch for $asset"
    assert [ ! -e "$RUNNER_TEMP/grim-bin/grim" ]
}

@test "aborts when the archive contains no grim binary" {
    local stem build
    stem="$(server_detect_stem)"
    build="$BATS_TEST_TMPDIR/nobin"
    mkdir -p "$build/$stem"
    echo "no binary here" >"$build/$stem/README"
    (cd "$build" && tar cJf "$stem.tar.xz" "$stem")
    server_publish "$SRV" v0.0.0 "$build/$stem.tar.xz"

    run bash "$INSTALL_SH"
    assert_failure 1
    assert_output "::error::no grim binary in $stem.tar.xz"
}
