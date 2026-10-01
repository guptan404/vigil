# Releasing Vigil

Published package versions are permanent. Complete this checklist from a clean,
reviewed commit rather than from a working tree containing unrelated changes.

## One-time setup

1. Make `https://github.com/guptan404/vigil` public, or update every package
   manifest to the final public repository and issue-tracker URLs.
2. Create or select a verified pub.dev publisher and add at least one backup
   administrator.
3. Confirm ownership of the `@vigil` npm organization. If that scope is not
   available, rename both npm packages and their internal dependency together.
4. Configure npm trusted publishing from the public repository. Prefer OIDC to
   long-lived npm tokens; trusted public releases receive provenance metadata.
5. Enable GitHub private vulnerability reporting for the repository.

## Prepare a release

1. Use the same version in every package that is part of the release.
2. Update each affected `CHANGELOG.md`.
3. Run `./tool/release_check.sh`.
4. Inspect every pub and npm file list printed by the dry runs.
5. Commit the release changes and rerun dry runs from a clean working tree.

The Dart packages use Pub workspaces, so internal dependencies resolve to local
packages during development while their published manifests retain hosted
version constraints. After an internal dependency is published, independently
validate a dependent package against the hosted version by temporarily adding a
`pubspec_overrides.yaml` beside it containing an empty `resolution:` field, then
run `dart pub get`, analysis, tests, and `dart pub publish --dry-run`.

## First pub.dev release

Publish in dependency order and wait for each dependency to become resolvable:

```sh
cd dart/vigil_core
dart pub publish

cd ../vigil_backend
dart pub publish

cd ../vigil_dio
dart pub publish

cd ../vigil_ui
dart pub publish

cd ../vigil
dart pub publish
```

The independent backend, Dio, and UI packages can be published in any order
after `vigil_core`. The umbrella `vigil` package must be last.

## First npm release

Publish `@vigil/core` before `@vigil/express`:

```sh
npm publish --workspace @vigil/core --access public
npm publish --workspace @vigil/express --access public
```

When publishing from a supported trusted CI workflow, npm generates provenance
automatically. Do not publish the private workspace root or either example app.

## After publishing

1. Install every package into a fresh sample application from its registry.
2. Verify the pub.dev documentation and platform tabs.
3. Verify npm provenance, declarations, and ESM imports.
4. Create and push the signed release tag.
5. Announce known limitations, especially the development-only security model.
