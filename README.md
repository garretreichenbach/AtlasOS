# AtlasOS repository

AtlasOS is a LuaMade desktop shell and app environment. This repository contains the source tree, shared libraries, a generated single-file web installer, and GitHub Actions workflows that keep the installer artifact in sync.

For the user-facing install guide, in-game usage, and desktop/app behavior, start with [`AtlasOS/README.md`](./AtlasOS/README.md).

## Repository layout

| Path | Purpose |
|---|---|
| [`AtlasOS/`](./AtlasOS/) | Core OS scripts, built-in apps, installer entrypoints, and user-facing documentation. |
| [`Lib/`](./Lib/) | Shared libraries used by AtlasOS at runtime. |
| [`scripts/`](./scripts/) | Host-side build tooling, currently the web installer builder. |
| [`dist/`](./dist/) | Generated release artifacts committed to the repository. |
| [`.github/workflows/`](./.github/workflows/) | CI and release automation for the generated web installer. |

## Important docs

- [`AtlasOS/README.md`](./AtlasOS/README.md) — main install and usage guide for LuaMade players.
- [`AtlasOS/APPINFO.md`](./AtlasOS/APPINFO.md) — package/app metadata format.
- [`scripts/build_web_installer.py`](./scripts/build_web_installer.py) — generates the single-file web installer.

## Local build workflow

Build the web installer from the repository root:

```bash
python3 scripts/build_web_installer.py
```

That generates:

- [`dist/atlasos-web-installer.lua`](./dist/atlasos-web-installer.lua)

The generated installer bundles the current contents of:

- [`AtlasOS/`](./AtlasOS/)
- [`Lib/`](./Lib/)

Whenever files under those trees change in a way that should affect installs, rebuild the installer and commit the updated `dist` file.

## Quick validation

After changing AtlasOS source, the installer builder, or release docs, use this minimal check:

```bash
python3 scripts/build_web_installer.py
git diff --exit-code -- dist/atlasos-web-installer.lua
```

If the second command reports changes, review and commit the regenerated installer artifact.

## CI workflow

[`web-installer.yml`](./.github/workflows/web-installer.yml) runs on pushes to `main`, pull requests, and manual dispatch.

It does three things:

1. checks out the repo
2. rebuilds `dist/atlasos-web-installer.lua`
3. fails if the committed artifact is out of date

This keeps the checked-in installer aligned with the source tree.

## Release workflow

[`release-web-installer.yml`](./.github/workflows/release-web-installer.yml) publishes the generated installer as a GitHub Release asset.

Supported release paths:

- push a tag like `v1.0.0`
- run the workflow manually and provide the `tag` input

Typical tag-based release flow:

```bash
git tag v1.0.0
git push origin main
git push origin v1.0.0
```

Typical manual release flow:

1. open the **Release web installer** workflow in GitHub Actions
2. choose **Run workflow**
3. enter a tag such as `v1.0.0`

The workflow rebuilds the installer, verifies it matches the checked-in `dist` artifact, and uploads `dist/atlasos-web-installer.lua` to the GitHub Release for that tag.

## Contributor entry points

Common places to start depending on the type of change:

- desktop/taskbar/window behavior: [`AtlasOS/ui.lua`](./AtlasOS/ui.lua)
- startup/install flow: [`AtlasOS/installer.lua`](./AtlasOS/installer.lua), [`AtlasOS/installer_gate.lua`](./AtlasOS/installer_gate.lua), [`Lib/atlasinstall.lua`](./Lib/atlasinstall.lua)
- built-in apps: [`AtlasOS/apps/`](./AtlasOS/apps/)
- shared app metadata/runtime helpers: [`Lib/appinfo.lua`](./Lib/appinfo.lua), [`Lib/startmenu.lua`](./Lib/startmenu.lua)
- package format: [`AtlasOS/APPINFO.md`](./AtlasOS/APPINFO.md)

## Documentation map

Use the right doc for the right task:

- **Installing or using AtlasOS in-game** → [`AtlasOS/README.md`](./AtlasOS/README.md)
- **Adding or packaging apps** → [`AtlasOS/APPINFO.md`](./AtlasOS/APPINFO.md)
- **Rebuilding the single-file installer** → [`scripts/build_web_installer.py`](./scripts/build_web_installer.py)
- **Understanding CI/release automation** → [`.github/workflows/`](./.github/workflows/)

## Notes for maintainers

- `dist/atlasos-web-installer.lua` is intentionally committed.
- The web installer is only as current as the last committed rebuild.
- The end-user `httpget` instructions are documented in [`AtlasOS/README.md`](./AtlasOS/README.md).

