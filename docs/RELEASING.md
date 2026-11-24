# Releasing

Two builds come from each version tag, both packaged from `.pkgmeta`:

- **CurseForge** packages the tag itself (the project's automatic packaging: "package any new
  tagged commits it sees when the code is pushed"), and uses `CHANGELOG.md` as the changelog.
  It hears about pushes through a webhook on the GitHub repo (Settings → Webhooks, push events,
  `https://www.curseforge.com/api/projects/1826936/package?token=…` with a CurseForge API token).
  Without it nothing reaches CurseForge. Pushes to `main` without a tag go up as alpha files.
- **GitHub Releases**: `.github/workflows/release.yml` runs the tests and attaches the same zip.
  It has no CurseForge key on purpose, so nothing is uploaded twice.

## Each release

1. Add the version's notes at the top of `CHANGELOG.md`.
2. Commit, then tag and push: `git tag v1.0.1 && git push origin v1.0.1`.
   - `v1.0.1` goes up as a release; `v1.0.1-beta` or `-alpha` as that type.
3. The tag fills in `## Version` (`@project-version@`) in the zip.
4. Check the file on the CurseForge project's Files tab and the GitHub release.

What's left out of the zip: see `ignore` in `.pkgmeta` (tests, tools, docs, CI files).
