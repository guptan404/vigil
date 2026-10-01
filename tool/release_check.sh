#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

dart pub get
dart run melos bootstrap
dart run melos run format
dart run melos run analyze
dart run melos run test

npm run check
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
