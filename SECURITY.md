# Security Policy

## Reporting a vulnerability

Report privately through GitHub:
**[Security → Advisories → Report a vulnerability](https://github.com/grimoire-rs/setup-grimoire/security/advisories/new)**.

No email address is published, and there is no inbox to maintain — the
advisory form reaches the maintainers directly and keeps the report
private until a fix is out.

Please do not open a public issue for a suspected vulnerability.

## Scope

In scope:

| Path | What |
|------|------|
| `action.yml` | The composite action's inputs, environment and step wiring |
| `.github/scripts/` | `install.sh`, `install.ps1`, `dco.sh` |
| `site/` | The bootstrap installers behind `setup.grimoire.rs` |

Out of scope: vulnerabilities in the `grim` CLI itself. Those belong in
[grimoire-rs/grimoire](https://github.com/grimoire-rs/grimoire/security/advisories/new).

## What the action verifies

`setup-grimoire` does not trust the network:

- Downloads are HTTPS with TLS 1.2 as the floor. `install.sh` passes curl
  `--proto '=https' --tlsv1.2`, so a plain-HTTP URL is refused outright
  rather than downgraded.
- Every archive is checked against the SHA-256 sidecar cargo-dist
  publishes next to it. A mismatch aborts the install; nothing is placed
  on `PATH`.
- This holds for mirrors too. A `release-base-url` pointing at an internal
  mirror must serve the `.sha256` sidecar alongside each archive — a
  mirror that serves an archive without a matching sidecar cannot install
  anything, and one that serves a tampered archive fails the comparison.
- `release-auth-header` is passed to curl and `Invoke-WebRequest` as a
  request header only. It is never written to `$GITHUB_PATH`,
  `$GITHUB_OUTPUT` or the step log; `tests/install/` asserts that on both
  platforms.

## Accepted risk: bootstrap installers use trust on first use

`site/sh` and `site/ps1` are one-line front doors:

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://setup.grimoire.rs/sh | sh
```

They fetch the cargo-dist installer over TLS and run it. Their integrity
rests on TLS alone — trust on first use — the same posture as rustup, uv
and deno.

This is accepted, not overlooked:

- The exposure is bounded to that one bootstrap fetch. The payload it
  runs — the grim archive itself — *is* checksum-verified, by the
  cargo-dist installer the bootstrap hands off to.
- Pinning a hash in the bootstrap would defeat its purpose. The whole
  point of the stable URL is not naming a version; a pinned hash would
  have to change on every release, and every published copy of the
  one-liner would go stale.

If trust on first use is unacceptable in your environment, two
alternatives give you a verified install:

1. Use this action. It pins the release and verifies the archive against
   its sidecar before anything reaches `PATH`.
2. Download the archive and its `.sha256` from the
   [grim releases](https://github.com/grimoire-rs/grimoire/releases) and
   check the digest yourself before running anything.
