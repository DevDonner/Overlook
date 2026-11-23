# Releasing

Releases are built by `.github/workflows/release.yml` with the BigWigs packager, from `.pkgmeta`.

## One-time setup

1. Create the project on CurseForge (WoW → Addons, game version WoW Forever / 1.60.1, licence MIT).
2. Put its project ID in `Overlook.toc`: `## X-Curse-Project-ID: <id>`. Without it the packager skips CurseForge and only makes the GitHub release.
3. Create an API token at https://legacy.curseforge.com/account/api-tokens and add it to the repo as the secret `CF_API_KEY` (Settings → Secrets and variables → Actions).

## Each release

1. Add the version's notes at the top of `CHANGELOG.md`; it becomes the CurseForge changelog.
2. Commit, then tag and push: `git tag v1.0.1 && git push origin v1.0.1`.
   - `v1.0.1` goes up as a release; `v1.0.1-beta` or `-alpha` as that type.
3. The tag fills in `## Version` (`@project-version@`) in the zip.

What's left out of the zip: see `ignore` in `.pkgmeta` (tests, tools, docs, CI files).
