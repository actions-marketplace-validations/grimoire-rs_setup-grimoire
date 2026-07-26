#!/usr/bin/env bash
# Load bats-support + bats-assert from the vendored submodules so suites can use
# assert_success / assert_failure / assert_output / refute_output.
#
# load.bash lives in tests/install/helpers, so the repo root is three levels up.
_GRIM_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
load "${_GRIM_REPO_ROOT}/external/bats-support/load.bash"
load "${_GRIM_REPO_ROOT}/external/bats-assert/load.bash"
