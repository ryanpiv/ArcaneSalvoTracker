# Publishing to CurseForge

Releases are driven by git tags: bump the TOC version + changelog, commit, then

```bash
git tag v0.1.0
git push && git push --tags
```

GitHub Actions ([BigWigs packager](https://github.com/BigWigsMods/packager),
see `.github/workflows/release.yml`) packages the addon per `.pkgmeta`,
uploads it to CurseForge, and attaches the zip to a GitHub release. Until the
one-time setup below is done, tag pushes still work — the packager just skips
the CurseForge upload and only produces the GitHub release.

## One-time setup (manual, ~5 minutes)

1. **Create the project** at [authors.curseforge.com](https://authors.curseforge.com) →
   Projects → Create a Project → World of Warcraft → Addon.
   Fill in name ("Arcane Salvo Tracker"), summary, and category (e.g. Combat /
   Class-specific).
2. **Get the project ID** — shown in the "About Project" box on the project's
   overview page — and add it to `ArcaneSalvoTracker.toc`:

   ```
   ## X-Curse-Project-ID: 123456
   ```

3. **Generate an API token** at authors.curseforge.com → Account → API Tokens,
   and store it as the `CF_API_KEY` repository secret:

   ```bash
   gh secret set CF_API_KEY --repo ryanpiv/ArcaneSalvoTracker
   ```

Optional: to also publish to [Wago](https://addons.wago.io), uncomment the
`WAGO_API_KEY` line in `release.yml`, add the project's wago id to `.pkgmeta`
(`wago-id: ...`), and set the `WAGO_API_KEY` secret the same way.

## Releasing

1. Bump `## Version:` in `ArcaneSalvoTracker.toc`.
2. Update `CHANGELOG.md` — its full contents are used as the CurseForge
   changelog, rendered as markdown (wired up via `manual-changelog` in
   `.pkgmeta`).
3. Commit, tag `v<version>` (matching the TOC version), and push the tag.

New uploads land in CurseForge's approval queue and go live once approved
(usually minutes).

## Notes

- The zip ships only runtime files — `spec/`, workflows, lint configs, and
  docs are excluded via the `ignore` list in `.pkgmeta`.
- Alpha/beta channels: the packager infers the release type from the tag —
  tags containing `alpha` or `beta` (e.g. `v0.2.0-beta1`) upload to that
  channel instead of release.
- If the upload fails with an unknown game version, CurseForge may not have
  registered the new patch yet; the error lists nearby known versions. The
  game version is derived from `## Interface:` in the TOC (`120100` → 12.1.0).
