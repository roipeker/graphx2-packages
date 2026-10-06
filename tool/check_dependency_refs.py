from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []

for pubspec in sorted((ROOT / "packages").glob("*/pubspec.yaml")):
    text = pubspec.read_text()
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.strip() != "git:":
            continue
        block = lines[index + 1:index + 6]
        url = next((x.strip().removeprefix("url:").strip() for x in block if x.strip().startswith("url:")), None)
        ref = next((x.strip().removeprefix("ref:").strip() for x in block if x.strip().startswith("ref:")), None)
        if url in {
            "https://github.com/roipeker/graphx2.git",
            "https://github.com/roipeker/graphx2-packages.git",
        } and ref != "main":
            errors.append(f"{pubspec.relative_to(ROOT)}: expected ref: main for {url}, found {ref!r}")

if errors:
    print("Dependency ref policy failed:")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print("Dependency refs: aligned to main")
