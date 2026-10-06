#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 tool/verify_dependencies.py
flutter pub get
flutter analyze

for package in packages/*; do
  if [[ -d "$package/test" ]]; then
    echo
    echo "==> ${package#packages/}"
    (
      cd "$package"
      flutter test
    )
  fi
done

git diff --exit-code -- analysis_options.yaml packages/*/analysis_options.yaml
