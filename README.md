<div align="center">

<img src="./assets/logo.png" width="192" />

# setup-grimoire

**GitHub Action that installs the `grim` CLI on your runner —
checksum-verified, on Linux, macOS and Windows**

[![CI][ci-badge]][ci]
[![Release][release-badge]][releases]
[![Marketplace][marketplace-badge]][marketplace]
[![License][license-badge]][license]

</div>

Installs [grim](https://grimoire.rs) — Grimoire, the OCI-backed package
manager for AI skills and rules — and adds it to `PATH`. Linux, macOS and
Windows runners on `x86_64` and `aarch64`; every archive is verified
against the SHA-256 sidecar published beside it.

## Usage

```yaml
steps:
  - uses: grimoire-rs/setup-grimoire@v1
  - run: grim install ghcr.io/grimoire-rs/skills/grim-usage --global
```

Pin a specific grim release:

```yaml
  - uses: grimoire-rs/setup-grimoire@v1
    with:
      version: v0.7.0
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `version` | `latest` | grim release to install: `latest`, an exact `vX.Y.Z` tag, or a prerelease tag such as `v1.2.3-rc.1` |
| `release-base-url` | GitHub releases | Download base for grim archives — see [Using a release mirror](#using-a-release-mirror) |
| `release-auth-header` | `''` | Optional HTTP header for authenticated mirrors, e.g. `PRIVATE-TOKEN: ${{ secrets.MIRROR_TOKEN }}` |

## Using a release mirror

Enterprise runners without github.com access can pull grim from an
internal mirror:

```yaml
  - uses: corp-org/setup-grimoire@v1
    with:
      version: v0.7.0            # pin exactly — see below
      release-base-url: https://artifacts.example.com/grim/releases
      release-auth-header: "PRIVATE-TOKEN: ${{ secrets.MIRROR_TOKEN }}"
```

The mirror must serve `<base>/download/<tag>/<asset>` and the `.sha256`
sidecar next to every archive (mirror the GitHub release assets
verbatim). The `latest` version resolves via GitHub's
`<base>/latest/download/` redirect, which mirrors typically don't
implement — pin an exact `vX.Y.Z`.

**The mirror must be HTTPS with a certificate the runner already trusts.**
Downloads are fetched with `--proto '=https' --tlsv1.2`, so a plain-HTTP
mirror is refused outright, and the action has no input for a private CA
bundle. If your mirror's CA is internal, install it on the runner before
this step — on Linux and macOS `curl` also honours `CURL_CA_BUNDLE`; the
Windows step uses the machine certificate store.

GitHub Enterprise Server instances without GitHub Connect cannot resolve
`uses: grimoire-rs/setup-grimoire@v1` from github.com — fork or mirror
this repository into your enterprise org (including tags) and reference
it locally, as in the example above.

## Outputs

| Output | Description |
|---|---|
| `version` | The installed version as reported by `grim --version` |

## Shell installers

The same binaries install outside CI via <https://setup.grimoire.rs>:

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://setup.grimoire.rs/sh | sh
```

```powershell
irm https://setup.grimoire.rs/ps1 | iex
```

## License

Apache-2.0

<!-- badges -->
[ci]: https://github.com/grimoire-rs/setup-grimoire/actions/workflows/test.yml
[ci-badge]: https://github.com/grimoire-rs/setup-grimoire/actions/workflows/test.yml/badge.svg
[releases]: https://github.com/grimoire-rs/setup-grimoire/releases
[release-badge]: https://img.shields.io/github/v/release/grimoire-rs/setup-grimoire
[marketplace]: https://github.com/marketplace/actions/setup-grimoire
[marketplace-badge]: https://img.shields.io/badge/marketplace-setup--grimoire-blue?logo=github
[license]: LICENSE
[license-badge]: https://img.shields.io/badge/license-Apache--2.0-blue.svg
