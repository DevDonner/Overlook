# Releasing

`.github/workflows/release.yml` runs on each version tag: it runs the tests, then the BigWigs
packager builds the zip from `.pkgmeta`, attaches it to a GitHub release and uploads it to
CurseForge, WoWInterface and Wago, with `CHANGELOG.md` as the changelog.

A site is uploaded to only when both of these are set (otherwise the packager skips it):

| Site | Project ID in `Overlook.toc` | Repo secret (Settings → Secrets and variables → Actions) |
| --- | --- | --- |
| CurseForge | `## X-Curse-Project-ID: 1826936` | `CF_API_KEY`, from authors.curseforge.com (Settings → API tokens) |
| WoWInterface | `## X-WoWI-ID:` the number in the addon's URL (`0` = not set) | `WOWI_API_TOKEN`, from wowinterface.com/downloads/filecpl.php?action=apitokens |
| Wago | `## X-Wago-ID:` the ID on the project's Wago developer page (`0` = not set) | `WAGO_API_TOKEN`, from addons.wago.io/account/apikeys |

`GITHUB_TOKEN` is provided by Actions; nothing to add for the GitHub release.

CurseForge's own automatic packaging (the push webhook on this repo, Settings → Webhooks) builds
from tags too. Once `CF_API_KEY` is added, delete that webhook, or every version is uploaded twice.

## Each release

1. Add the version's notes at the top of `CHANGELOG.md`.
2. Commit, then tag and push: `git tag v1.0.1 && git push origin v1.0.1`.
   - `v1.0.1` goes up as a release; `v1.0.1-beta` or `-alpha` as that type.
3. The tag fills in `## Version` (`@project-version@`) in the zip.
4. Check the Actions run, then the file on each site and the GitHub release. New WoWInterface
   files may wait for a short manual approval.

What's left out of the zip: see `ignore` in `.pkgmeta` (tests, tools, docs, CI files).
