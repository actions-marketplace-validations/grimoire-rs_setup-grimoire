#!/bin/sh
# Enforce the DCO term CONTRIBUTING.md promises: every non-merge commit in
# the given range carries a Signed-off-by trailer whose email matches its
# author. Bot authors are exempt — dependabot cannot sign off, and its
# commits are not contributions in the DCO sense.
#
# Usage: .github/scripts/dco.sh [range]   (default: main..HEAD)
set -eu

range="${1:-main..HEAD}"

missing=0
for sha in $(git rev-list --no-merges "$range"); do
    email=$(git show -s --format='%ae' "$sha")
    name=$(git show -s --format='%an' "$sha")
    case "$name$email" in *'[bot]'*) continue ;; esac
    # -F, not a regex: real addresses carry '+' and '.', both ERE
    # metacharacters. Read trailers only, so a Signed-off-by quoted in a
    # commit body cannot satisfy the check.
    if ! git show -s --format='%(trailers:key=Signed-off-by,valueonly)' "$sha" | grep -qF "<$email>"; then
        echo "missing or mismatched sign-off: $(git show -s --format='%h %s' "$sha")"
        echo "  author: $name <$email>"
        missing=$((missing + 1))
    fi
done

if [ "$missing" -gt 0 ]; then
    echo ""
    echo "$missing commit(s) without a matching Signed-off-by trailer."
    echo "Sign off with 'git commit -s', or fix history with"
    echo "  git rebase --signoff $range"
    echo "See the License section of CONTRIBUTING.md."
    exit 1
fi

echo "DCO: all commits in $range are signed off"
