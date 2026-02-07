# ClaudeCode.nvim Capability Comparison for `codex.nvim`

Last updated: February 7, 2026

## Scope

This document summarizes capabilities from
[`coder/claudecode.nvim`](https://github.com/coder/claudecode.nvim), compares
them to current Codex CLI capabilities, and proposes an implementation plan for
this Neovim plugin.

## Version Context

- `coder/claudecode.nvim` latest visible release: `v0.3.0` (September 16, 2025)
- `openai/codex` latest visible release: `v0.98.0` (February 5, 2026)

## ClaudeCode.nvim Capability Inventory

### 1) Terminal Lifecycle and UX

- Commands for opening/toggling/focusing Claude terminal sessions.
- Open with args/model-selection support.
- Configurable auto-start and focus behavior.

### 2) Editor Context Transfer

- Send visual selections.
- Add file/path context with optional line ranges.
- Add files from file-tree integrations.

### 3) Change Review Workflow

- Diff/proposed-change view.
- Accept/deny workflows exposed as commands.

### 4) Provider Abstraction

- Multiple terminal backends (`auto`, `snacks`, native, external).
- Custom provider interface.

### 5) Workspace/CWD Behavior

- Configurable working directory strategy.
- Git-root-based behavior support.

### 6) IDE Bridge Internals (Claude-specific)

- WebSocket server and lock-file based discovery for Claude IDE integration.
- Tool-bridge behavior tied to Claude Code protocol expectations.

## Codex CLI Capability Inventory

### 1) Interactive Session Management

- `codex` interactive TUI.
- Session resume support (`codex resume`, `codex exec resume`).
- Slash commands for runtime controls (`/model`, `/permissions`, `/status`,
  `/review`, `/diff`, `/mention`, `/compact`, etc.).

### 2) Automation/Execution

- `codex exec` for non-interactive tasks.
- JSON output and schema-oriented modes for machine workflows.

### 3) Security and Runtime Controls

- Sandbox and approval controls (`--sandbox`, `--ask-for-approval`,
  `--full-auto`, `--yolo`).

### 4) Integrations

- MCP support (`codex mcp ...`).
- Local config (`~/.codex/config.toml`, project `.codex/config.toml`).
- Support for image input and optional web-search-enabled flows.

## Capability Mapping: ClaudeCode.nvim -> `codex.nvim`

### Direct/Strong Mapping

- Terminal lifecycle features map directly.
- Context send/add flows map directly (selection and file-based context
  insertion into active Codex session).
- Model/session commands map directly (launch args + slash command wrappers).
- Provider abstraction maps directly and should be preserved.

### Partial Mapping / Needs Adaptation

- Claude-style accept/deny diff flow is not 1:1 in Codex UX.
- Recommended Codex-native approach:
  - Expose wrappers for `/diff` and `/review`.
  - Add optional Git rollback helpers where useful.

### Do Not Clone (for MVP)

- Claude-specific WebSocket/lock-file bridge internals should not be copied
  as-is.
- Codex already provides local interactive and tool execution flows; duplicating
  Claude bridge internals would add complexity without clear MVP value.

## Proposed MVP for `codex.nvim`

### Phase 1: Core Terminal + Commands

- Setup API and defaults.
- Terminal provider abstraction (`auto`, `snacks`, `native`, `external`,
  `none`).
- `:Codex` and `:CodexFocus`.

### Phase 2: Context Transfer

- `:CodexSend` for visual selection.
- `:CodexAdd` for current file/path (+ optional line ranges).
- `:CodexTreeAdd` hooks for explorer integrations.

### Phase 3: Session and Model Controls

- `:CodexResume`.
- `:CodexSelectModel`.
- Optional helpers for `/status` and `/permissions`.

### Phase 4: Review and Diff Helpers

- `:CodexReview` wrapper.
- `:CodexDiff` wrapper.
- Optional Git-based rollback command(s).

## Initial Technical Design Notes

- Keep transport simple for MVP: terminal-first control (send text to active
  terminal job/channel).
- Treat provider abstraction as first-class to avoid hard dependency on one
  terminal plugin.
- Keep command API stable even if internal transport evolves later.
- Add structured logging/config toggles early; they reduce debugging cost during
  terminal/provider integration.

## Architecture Direction (Agreed)

The plugin should use a command-pattern core with strict abstraction boundaries
so execution logic can be tested without concrete terminal providers.

### 1) Provider Interface (Common Contract)

Each terminal provider should implement a small shared interface:

- `start(session_spec) -> session_handle`
- `send(session_handle, text) -> ok|err`
- `focus(session_handle) -> ok|err`
- `stop(session_handle) -> ok|err`
- `is_alive(session_handle) -> boolean`
- `metadata(session_handle) -> table` (provider-specific diagnostics)

Provider-specific options are allowed via `provider_opts.<provider_name>` while
preserving the common API.

### 2) Command Pattern in Core

Neovim user commands should be thin adapters that build command objects and pass
them to a core executor.

- User command layer: parse args, gather editor context.
- Command objects: immutable intent (`OpenCodexCommand`, `SendSelectionCommand`,
  `ResumeSessionCommand`, etc.).
- Execution core: resolves dependencies and runs command handlers.
- Provider adapter: only terminal/plugin-specific behavior lives here.

This keeps business logic independent from Neovim UI concerns and provider
internals.

### 3) Dependency Injection for Testability

Command handlers should depend on interfaces, not globals:

- `ProviderRegistry`
- `SessionStore`
- `ContextBuilder`
- `CodexCommandFormatter`
- `Logger`

In tests, replace these with fakes/stubs to validate behavior deterministically.

### 4) Testing Strategy

- Unit tests (primary): command handlers with fake providers/session stores.
- Contract tests: validate every provider implementation satisfies the shared
  provider interface.
- Integration tests: minimal Neovim command registration and end-to-end
  execution smoke tests.

Goal: most logic coverage from unit tests, with only a small matrix of provider
integration tests.

### 5) Suggested Module Shape

- `lua/codex/core/commands/*.lua` command definitions
- `lua/codex/core/handlers/*.lua` command handlers
- `lua/codex/core/executor.lua` command dispatcher/executor
- `lua/codex/providers/*.lua` provider implementations
- `lua/codex/providers/interface.lua` provider contract documentation/helpers
- `lua/codex/state/session_store.lua` active session state abstraction
- `lua/codex/context/*.lua` editor/file/selection context builders
- `lua/codex/nvim/commands.lua` Neovim command registration (thin layer)
- `tests/unit/*` handler and formatter tests
- `tests/contract/providers/*` provider contract tests
- `tests/integration/*` Neovim-level smoke tests

## Risks and Unknowns

- Neovim terminal behavior differs across provider backends; test matrix needed.
- Diff/review UX parity with Claude may require a custom UI layer if `/diff`
  output is not sufficient for users.
- Resume/session ergonomics depend on Codex CLI behavior and may require
  iterative tuning.

## Suggested Next Step

Define `codex.nvim` command surface and module layout before coding:

- `lua/codex/init.lua` for setup.
- `lua/codex/config.lua` for defaults and validation.
- `lua/codex/core/*` for command/executor architecture.
- `lua/codex/providers/*.lua` for terminal providers.
- `lua/codex/nvim/commands.lua` for user command registration (thin adapters).
- `lua/codex/context/*` for selection/file context builders.
- `tests/unit`, `tests/contract`, and `tests/integration` scaffolding.

## Sources

- https://github.com/coder/claudecode.nvim
- https://github.com/openai/codex
- https://developers.openai.com/codex/cli
- https://developers.openai.com/codex/cli/features
- https://developers.openai.com/codex/cli/slash-commands
- https://developers.openai.com/codex/cli/reference
- https://developers.openai.com/codex/config-basic
- https://developers.openai.com/codex/mcp
