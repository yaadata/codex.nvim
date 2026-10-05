# Architecture

The core API manages sessions, input, prompt building, and logs. Builtins compose
those primitives into agent-specific workflows. Keep harness commands and CLI
arguments in builtins.

Browse [`lua/codex/`](../lua/codex/) for implementations and types, and
[`tests/`](../tests/) for verified behavior.

## Boundaries

- Builtins use the public core API. Require `codex` when the workflow runs so
  cached modules do not retain an API from before reload.
- Runtime modules receive dependencies or accessors from setup. Tests inject
  collaborators through `_deps`; builtin calls to global `vim` need separate
  test overrides.
- Keep the shared prompt builder, terminal input, and readiness queue distinct.

## Providers

Use the current provider type and an existing provider as references. When adding
one, update its registration, configuration, shared types, and contract tests.
