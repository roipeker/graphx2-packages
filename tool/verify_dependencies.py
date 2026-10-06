#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
errors = []

for pubspec in sorted((root / "packages").glob("*/pubspec.yaml")):
    text = pubspec.read_text()
    if "ref:" in text:
        errors.append(f"{pubspec.relative_to(root)} contains a literal git ref")
    if "https://github.com/roipeker/graphx2.git" in text:
        if "tag_pattern: v{{version}}" not in text:
            errors.append(
                f"{pubspec.relative_to(root)} must version-solve GraphX with tag_pattern"
            )
        if "version: ^2.0.0-dev.2" not in text:
            errors.append(
                f"{pubspec.relative_to(root)} must declare the GraphX compatibility range"
            )

for name in ("graphx_motion", "graphx_particles"):
    pubspec = root / "packages" / name / "pubspec.yaml"
    text = pubspec.read_text()
    if "graphx_paths:" not in text:
        errors.append(f"{pubspec.relative_to(root)} is missing graphx_paths")
    elif "version: ^0.1.0-dev.3" not in text:
        errors.append(
            f"{pubspec.relative_to(root)} must version-solve graphx_paths"
        )

if errors:
    print("Dependency policy violations:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print("Dependency policy OK")
