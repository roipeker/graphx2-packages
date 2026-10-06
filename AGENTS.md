# Development notes

This repository contains official first-party GraphX ecosystem packages.
GraphX core lives in the separate graphx2 repository.

- Consume GraphX only through public entrypoints; never import package:graphx/src/....
- Keep package ownership explicit and APIs compact.
- Preserve allocation-aware hot paths and deterministic behavior where documented.
- Do not use Dart cascade notation (.. or ?..) in source, tests, examples, benchmarks, or documentation.
- Validate package-local tests and downstream consumers when changing shared foundational packages.
- Keep every package independently consumable from the public Git repository.
