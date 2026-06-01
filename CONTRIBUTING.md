# Contributing to Writebook

## Cutting a Release

Writebook is distributed two ways: as a container image on GitHub Container Registry (GHCR), and through the legacy ONCE installer. Both need to be updated when cutting a release.

### Current Process (GHCR)

Releases are driven by **annotated git tags**. When you push a tag matching `v*`, the `publish-image.yml` GitHub Actions workflow runs automatically. It builds multi-architecture Docker images (amd64 and arm64), publishes them to `ghcr.io/basecamp/writebook`, and signs them with [Cosign](https://docs.sigstore.dev/cosign/overview/) using keyless OIDC — no signing keys to manage.

The workflow produces several image tags from a single version push. For example, pushing `v1.2.3` creates:

- `ghcr.io/basecamp/writebook:v1.2.3` — the exact version
- `ghcr.io/basecamp/writebook:1.2.3` — semver without prefix
- `ghcr.io/basecamp/writebook:1.2` — minor floating tag
- `ghcr.io/basecamp/writebook:1` — major floating tag
- `ghcr.io/basecamp/writebook:latest`
- `ghcr.io/basecamp/writebook:sha-<short>` — the git commit SHA

#### Steps

1. **Merge your PR to `main`.** All changes should be on `main` before tagging.

2. **Create an annotated tag.** The tag message becomes the release notes. Prior releases use terse bullet points:

   ```console
   $ git tag -a v1.2.3 -m "Version 1.2.3

   - Fix issue with forwarded headers
   - Update dependencies"
   ```

   Use `git tag -l -n99` to see how previous releases were formatted.

3. **Push the tag.**

   ```console
   $ git push origin v1.2.3
   ```

4. **Verify the workflow.** Check the [Actions tab](https://github.com/basecamp/writebook/actions/workflows/publish-image.yml) to confirm the build completes. The workflow builds each architecture in parallel, then creates a multi-arch manifest and signs everything.

That's it for GHCR. No scripts to run, no Docker credentials needed locally — CI handles the build and push.

### Legacy ONCE Process

Before Writebook was open-sourced, it was distributed through [ONCE](https://once.com) — a platform for self-hosted apps sold as one-time purchases. Some customers still run these installs, which pull from `registry.once.com` instead of GHCR.

The release script was removed from the repo before open-sourcing (in commit `0ecca477`). If you need to cut a ONCE release, retrieve it from git history:

```console
$ git show 0ecca477^:bin/release > bin/release && chmod +x bin/release
```

#### `bin/release`

A Ruby script that uses [SSHKit](https://github.com/capistrano/sshkit) to orchestrate Docker commands locally. It:

1. Sets up a Docker Buildx builder (for cross-compilation) if one doesn't exist.
2. Creates an annotated git tag (same as the GHCR process) and pushes it to origin. Pass `-` as the version to skip tagging — useful if you already tagged for the GHCR release.
3. Builds a multi-arch image and pushes it to `registry.once.com/writebook`.

Usage:

```console
$ bin/release 1.2.3       # tags and builds
$ bin/release -            # builds without tagging (if you already tagged for GHCR)
```

This requires push access to `registry.once.com` and a working Docker Buildx setup with cross-platform support.

> **Note:** This legacy script doesn't yet have a permanent home in the repo. Coordinate with the team before running it.
