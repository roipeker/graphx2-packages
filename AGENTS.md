# Development notes

This repository contains official first-party GraphX ecosystem packages. GraphX core lives in the separate `graphx2` repository.

- Consume GraphX through its public entrypoints. Never import `package:graphx/src/...`.
- Do not modify GraphX core from an ecosystem-package lane; report missing core contracts to the orchestrator.
- Keep package APIs compact and package ownership explicit.
- Preserve hot-path allocation characteristics when porting proven Satechi code.
- Do not use Dart cascade notation (`..` or `?..`) in source, tests, examples, benchmarks, or documentation.
- Satechi is migration reference, not the target architecture.
- Use package-local tests and validate downstream consumers when changing shared foundational packages.
- Stage only paths covered by the active `aictl` lease before committing.
