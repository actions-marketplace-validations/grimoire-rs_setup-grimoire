#!/usr/bin/env bash
# Install the grim CLI on a Linux or macOS runner: pick the release asset for
# the host platform, verify it against the cargo-dist .sha256 sidecar, and put
# the binary on PATH through $GITHUB_PATH.
#
# Inputs arrive as environment variables set by action.yml (GRIM_SETUP_VERSION,
# GRIM_RELEASE_BASE_URL, GRIM_RELEASE_AUTH_HEADER) rather than as arguments, so
# the step's `env:` block stays the single place they are named.
set -euo pipefail
IFS=$'\n\t'

# The shape the `version:` input accepts, named once so the check and the
# annotation that explains it cannot drift apart.
#
# This governs WHICH GRIM RELEASE IS INSTALLED. It is unrelated to
# setup-grimoire's own release-tag filter in .github/workflows/release.yml,
# which deliberately excludes prereleases and the moving v1 tag. Two
# same-looking regexes, two different purposes, two different files. Loosening
# one must not loosen the other.
readonly VERSION_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'

main() {
    local version stem base auth_header tmp asset candidate ext url expected actual found install_dir
    local -a curl_args

    version="${GRIM_SETUP_VERSION:-latest}"
    if [[ "$version" != "latest" && ! "$version" =~ $VERSION_RE ]]; then
        echo "::error::version '$version' must be 'latest' or vX.Y.Z"
        exit 1
    fi

    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64) stem="grimoire-x86_64-unknown-linux-gnu" ;;
        Linux/aarch64 | Linux/arm64) stem="grimoire-aarch64-unknown-linux-gnu" ;;
        Darwin/x86_64) stem="grimoire-x86_64-apple-darwin" ;;
        Darwin/arm64) stem="grimoire-aarch64-apple-darwin" ;;
        *)
            echo "::error::unsupported platform: $(uname -s)/$(uname -m)"
            exit 1
            ;;
    esac

    base="${GRIM_RELEASE_BASE_URL:-https://github.com/grimoire-rs/grimoire/releases}"
    auth_header="${GRIM_RELEASE_AUTH_HEADER:-}"

    # One curl argument list, built once. An array (not a string) so the header
    # value survives with its spaces intact — the old `${auth_header:+-H
    # "$auth_header"}` form relied on IFS containing a space and breaks under
    # the IFS set above. Never empty, so `"${curl_args[@]}"` is safe under
    # `set -u` on macOS's bash 3.2.
    curl_args=(--proto '=https' --tlsv1.2 -LsSf)
    if [[ -n "$auth_header" ]]; then
        curl_args+=(-H "$auth_header")
    fi

    tmp="$(mktemp -d)"
    # Double-quoted so $tmp is expanded now: a single-quoted trap would look up
    # a `local` variable that no longer exists once main returns.
    # shellcheck disable=SC2064
    trap "rm -rf \"$tmp\"" EXIT

    # Releases may ship as .tar.xz or .tar.gz; try each until one downloads.
    # tar -xf below auto-detects xz vs gzip, so only the URL differs.
    asset=""
    for ext in tar.xz tar.gz; do
        candidate="$stem.$ext"
        if [[ "$version" == "latest" ]]; then
            url="$base/latest/download/$candidate"
        else
            url="$base/download/$version/$candidate"
        fi
        # Exit code AND size in one condition: a mirror that answers 200 with an
        # empty body would otherwise be accepted as the asset, and tar would
        # fail later with no annotation instead of falling through to .tar.gz.
        if curl "${curl_args[@]}" "$url" -o "$tmp/$candidate" && [[ -s "$tmp/$candidate" ]]; then
            asset="$candidate"
            break
        fi
    done
    if [[ -z "$asset" ]]; then
        echo "::error::no archive found for $stem (.tar.xz or .tar.gz)"
        exit 1
    fi

    # cargo-dist publishes a sibling .sha256 for every archive.
    curl "${curl_args[@]}" "$url.sha256" -o "$tmp/$asset.sha256"
    expected="$(awk '{print $1}' "$tmp/$asset.sha256")"
    actual="$(sha256sum "$tmp/$asset" 2>/dev/null | awk '{print $1}' ||
        shasum -a 256 "$tmp/$asset" | awk '{print $1}')"
    if [[ "$expected" != "$actual" ]]; then
        echo "::error::checksum mismatch for $asset"
        exit 1
    fi

    tar -xf "$tmp/$asset" -C "$tmp"
    # -print -quit, not `| head -1`: same first match, but no pipeline, so
    # `set -o pipefail` has no SIGPIPE to propagate when find's output outruns
    # the pipe buffer. -quit is in GNU and BSD find alike; the macOS bats leg is
    # the proof.
    found="$(find "$tmp" -name grim -type f -print -quit)"
    if [[ -z "$found" ]]; then
        echo "::error::no grim binary in $asset"
        exit 1
    fi
    install_dir="$RUNNER_TEMP/grim-bin"
    mkdir -p "$install_dir"
    install -m 0755 "$found" "$install_dir/grim"
    echo "$install_dir" >>"$GITHUB_PATH"
}

main "$@"
