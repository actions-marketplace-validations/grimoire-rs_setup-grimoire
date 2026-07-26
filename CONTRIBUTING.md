# Contributing to setup-grimoire

## What's here

| Path | Purpose |
|------|---------|
| `action.yml` | The composite GitHub Action that installs `grim` |
| `site/` | Static site behind `setup.grimoire.rs` — shell/PowerShell installers and the landing page, deployed via GitHub Pages |
| `.github/workflows/test.yml` | Smoke-tests the action on Linux/macOS/Windows; checks DCO sign-off on pull requests |
| `.github/workflows/pages.yml` | Deploys `site/` to GitHub Pages on push to `main` |
| `.github/scripts/dco.sh` | The DCO check, runnable locally — see [License](#license) |

There's no build here — no Rust, no task runner, no package manifest. The
action is a `runs: using: composite` shell/pwsh script, and `site/` is
served as-is.

## Testing the action

`.github/workflows/test.yml`'s `smoke` job is the real test: it runs
`uses: ./` on ubuntu/macos/windows runners and asserts `grim --version`
succeeds. Push a branch or open a pull request to exercise it — there's no
faster local equivalent, since the composite action needs a real runner
environment (`RUNNER_TEMP`, `GITHUB_PATH`) to install into.

`shellcheck` can't lint `action.yml` directly (it's YAML, not a shell
script). To lint a change to the bash `run:` block, copy its contents into
a scratch file and run `shellcheck` against that before pushing. The pwsh
`run:` block has no local linter in this repo — review it by eye, or check
it with a local `pwsh` install if you have one.

If you have [`act`](https://github.com/nektos/act) and Docker, you can run
the Linux leg of the smoke job locally.

## Testing the installers

`site/sh` and `site/ps1` are thin bootstrap scripts that fetch and run the
real cargo-dist installer — keep them that way, don't grow install logic
here.

```sh
shellcheck site/sh .github/scripts/dco.sh
sh -n site/sh
```

`site/ps1` has no local lint in this repo's toolchain; if you have `pwsh`,
`pwsh -NoProfile -Command '$ErrorActionPreference = "Stop"; . { <paste> }'`
catches syntax errors. Otherwise review by eye — it only runs on the
Windows leg of `smoke` in CI.

`site/index.html` is a static page; open it in a browser to check rendering.

## Commit Conventions

This repo doesn't run a commit-lint job, but existing history follows
[Conventional Commits](https://www.conventionalcommits.org/) (`feat:`,
`fix:`, `chore:`, ...) — keep doing that.

## Branch Model

Branch from `main` — never commit directly to `main`. Keep commits atomic.

## License

setup-grimoire is licensed under the [Apache License, Version 2.0](LICENSE),
and contributions are accepted under that same license — inbound matches
outbound, as Apache-2.0 §5 already presumes. Nothing you contribute is
relicensed, and you keep the copyright in your own work.

**There is no CLA.** Instead, sign off your commits under the
[Developer Certificate of Origin](https://developercertificate.org/) — a
one-line statement that you wrote the patch, or otherwise have the right to
submit it under this license:

```sh
git commit -s          # appends: Signed-off-by: Your Name <you@example.com>
```

The name and email must be real, and the sign-off address must match the one
that authored the commit. If you are contributing work owned by an employer,
make sure you have their permission before you sign off.

CI checks this on every pull request (existing history predates the DCO
requirement and is not checked retroactively). If you forget, `git rebase
--signoff main..HEAD` fixes the whole branch at once. Run the same check
CI runs yourself with:

```sh
.github/scripts/dco.sh              # checks main..HEAD
.github/scripts/dco.sh <range>      # or any explicit range
```

The copyright holder named in `LICENSE` is **The Grimoire Authors** — that
is every person with a commit in this repository, as listed by:

```sh
git shortlog -sne
```

No separate contributor list is maintained; git history is the record.
