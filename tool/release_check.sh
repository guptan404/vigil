#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

dart pub get
# Pub workspaces resolve all local packages above. Run validation directly so
# a clean runner does not depend on a globally installed Melos launcher.
dart format --output=none --set-exit-if-changed .
dart analyze

for package in dart/* example/flutter_app; do
  if [[ ! -d "$package/test" ]]; then
    continue
  fi
  (
    cd "$package"
    if grep -q 'sdk: flutter' pubspec.yaml; then
      flutter test
    else
      dart test
    fi
  )
done

npm run check
npm run test:integration
npm run pack:check

for package in \
  dart/vigil_core \
  dart/vigil_backend \
  dart/vigil_dio \
  dart/vigil_ui \
  dart/vigil; do
  echo "Validating $package"
  (
    cd "$package"
    dart doc
    dart pub publish --dry-run
  )
done
