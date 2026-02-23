# Contributing

## Prerequisites

- **Neovim >= 0.11.0** -- the plugin uses APIs introduced in this version.
- **[mise](https://mise.jdx.dev/)** -- manages tool versions for the project.
- **Git** -- for version control and pre-commit hooks.

mise pins the following tools (see `mise.toml`):

| Tool       | Version |
| ---------- | ------- |
| stylua     | v2.3.1  |
| selene     | 0.30.0  |
| mdformat   | 1.0.0   |
| pre-commit | 4.2.0   |

## Getting Started

```sh
# Clone the repository
git clone https://github.com/yaadata/codex.nvim.git
cd codex.nvim

# Install mise-managed tools (stylua, selene, mdformat, pre-commit)
mise install

# Clone plenary.nvim into .deps/ (required for running tests)
just bootstrap-test-deps

# Install git pre-commit hooks
just pre-commit-install
```

What each step does:

- `mise install` reads `mise.toml` and installs the pinned versions of stylua,
  selene, mdformat, and pre-commit.
- `just bootstrap-test-deps` clones (or pulls) `plenary.nvim` into
  `.deps/plenary.nvim`. This is the only test dependency.
- `just pre-commit-install` installs pre-commit hooks into `.git/hooks/` so that
  formatting, linting, and unit tests run automatically before each commit.

## Running Commands with Mise (Recommended)

To avoid "command not found" errors for tools like `selene`, `stylua`, and
`mdformat`, run project commands through mise:

```sh
mise exec -- just test-unit
mise exec -- just fmt-check
mise exec -- just lint
```

This ensures commands use the tool versions pinned in `mise.toml`, even when
those tools are not globally installed on your system.

## Running Tests

### Full Suite

```sh
mise exec -- just test
```

Runs `bootstrap-test-deps`, then `test-unit`, then `test-contract` in sequence.

### Unit Tests

```sh
mise exec -- just test-unit
```

Loops over every `tests/unit/*_spec.lua` file and runs each one individually via
`PlenaryBustedFile` in a headless Neovim instance. This isolation ensures one
failing spec file does not prevent others from running.

### Contract Tests

```sh
mise exec -- just test-contract
```

Runs `tests/contract/provider_contract_spec.lua` which verifies that every
registered provider exports all 9 required methods and handles nil handles
correctly.

### Test Environment

Tests run in headless Neovim with `tests/minimal_init.lua` as the init file.
This minimal config:

1. Prepends the plugin root to `rtp`.
2. Resolves plenary.nvim from `CODEX_PLENARY_PATH`, `.deps/plenary.nvim`, or the
   lazy.nvim default location.
3. Disables swap files and shada.
4. Loads `plugin/plenary.vim` to register the `PlenaryBustedFile` command.

## Formatting and Linting

### Formatting (stylua)

```sh
mise exec -- just fmt         # format in place
mise exec -- just fmt-check   # check only (used in CI and pre-commit)
```

Stylua configuration (`.stylua.toml`):

| Setting            | Value            |
| ------------------ | ---------------- |
| `column_width`     | 100              |
| `indent_type`      | Spaces           |
| `indent_width`     | 2                |
| `line_endings`     | Unix             |
| `quote_style`      | AutoPreferDouble |
| `call_parentheses` | Always           |

### Markdown Formatting (mdformat)

```sh
mise exec -- just fmt         # format in place (includes Lua and Markdown)
mise exec -- just fmt-check   # check only (used in CI and pre-commit)
```

mdformat is installed via the `pipx` backend with the
[mdformat-gfm](https://github.com/hukkin/mdformat-gfm) plugin for GitHub
Flavored Markdown support (tables, task lists, etc.). The `--number` flag is
used to apply consecutive numbering to ordered lists.

Targets: `docs/` and `README.md`.

### Linting (selene)

```sh
mise exec -- just lint
```

Selene configuration (`selene.toml` + `codex.yml`):

- Uses a custom `codex` standard defined in `codex.yml`.
- Base standard: `lua51`.
- Additional globals: `vim` (with `new-fields`), `describe`, `it`,
  `before_each`, `after_each`, `assert` (with `new-fields`).
- Excludes `.deps/**` from linting.

## Pre-Commit Hooks

The following hooks run before every commit (`.pre-commit-config.yaml`):

**Pre-commit stage** (runs on file content):

1. **codex-fmt-check** -- `mise exec -- just fmt-check`
2. **codex-lint** -- `mise exec -- just lint`
3. **codex-md-fmt-check** --
   `mise exec -- mdformat --number --check docs/ README.md`
4. **codex-test-unit** -- `mise exec -- just test-unit`
5. **codex-test-contract** -- `mise exec -- just test-contract`

**Commit-msg stage** (validates the commit message):

6. **conventional-pre-commit** -- enforces the conventional commit format
   described in the Git Workflow section. Requires a scope from the allowed list
   and one of the allowed types. Uses `--strict` mode.

Run all hooks manually against the full repo:

```sh
mise exec -- just pre-commit-run
```

Do not bypass hooks with `--no-verify`. If a hook fails, fix the issue and
commit again.

## Code Style Guide

### Module Structure

```lua
local M = {}

-- Private helpers (local functions, not on M)
local function helper() end

-- Public API (functions on M)
function M.public_method() end

return M
```

### Type Annotations

Use EmmyLua annotations for all public functions and types:

```lua
---@param name string
---@param count integer
---@return boolean ok
---@return string|nil err
function M.example(name, count) end
```

Document every function (public and private) with a one-line summary placed
before `---@param`/`---@return` tags:

```lua
---Returns whether the active session is alive.
---@param session codex.Session|nil
---@param provider codex.Provider
---@return boolean
local function session_is_alive(session, provider) end
```

Define shared types with `---@class` and `---@alias` in `lua/codex/types.lua`.
Module-local types (like `codex.SelectionSpec`) can be defined in the module
that owns them.

### Error Handling

- Use `(ok, err)` two-value returns for operational failures (network errors,
  missing selections, provider failures).
- Use `error()` only for programmer errors (calling API before setup, invalid
  arguments that indicate bugs).

### Naming

| Element   | Convention         | Example                |
| --------- | ------------------ | ---------------------- |
| Files     | `snake_case.lua`   | `session_store.lua`    |
| Functions | `snake_case`       | `get_visual_selection` |
| Constants | `UPPER_SNAKE_CASE` | `ERR_NO_FILEPATH`      |
| Types     | `codex.PascalCase` | `codex.ProviderHandle` |
| Commands  | `CodexPascalCase`  | `CodexSend`            |

### Comments

Prefer self-documenting code over inline comments. Use EmmyLua annotations as
the primary form of documentation. Add comments only where the logic is not
self-evident.

## Testing Patterns

### Framework

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) which
provides busted-style test primitives: `describe`, `it`, `before_each`,
`after_each`, and `assert`.

### Module Isolation

Clear `package.loaded` in `before_each` to ensure each test starts with a fresh
module state:

```lua
before_each(function()
  package.loaded["codex"] = nil
end)
```

### Dependency Injection

The `_deps` pattern allows full isolation in unit tests. Create mock factories
for each collaborator and inject them via `setup()`:

```lua
local function make_provider()
  local provider = { open_calls = {}, send_calls = {} }
  function provider.is_available()
    return true
  end
  function provider.open(cmd, args, env, config, focus, on_exit)
    table.insert(provider.open_calls, { cmd = cmd, focus = focus })
    return { id = "handle_" .. #provider.open_calls, alive = true }
  end
  -- ... implement remaining methods ...
  return provider
end

-- In test setup:
codex.setup({
  _deps = {
    providers = providers_mock,
    session_store = make_session_store(),
    logger = make_logger(),
    vim = make_fake_vim(),
    -- ...
  },
})
```

See `tests/unit/init_spec.lua` for the canonical examples of all mock factories:
`make_provider`, `make_session_store`, `make_logger`, `make_formatter`,
`make_selection`, `make_fake_vim`, and the `setup_with_deps` helper.

### Contract Tests

Contract tests (`tests/contract/provider_contract_spec.lua`) verify structural
compliance: every provider module exports all 9 required methods as functions,
`is_available` returns a boolean, and nil-handle methods behave correctly. The
currently registered providers are `native` and `snacks`.

When adding a new provider, add an entry to the `provider_modules` table in the
contract test file.

## Git Workflow

### Branching

Feature branches off `main`. Keep branches focused on a single change.

### Commit Messages

Use [conventional commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>
```

**Types:** `chore`, `docs`, `enhance`, `feat`, `fix`, `refactor`, `release`,
`test`

**Scopes:** `ci`, `codex`, `config`, `context`, `core`, `nvim`, `project`,
`providers`, `state`

These conventions are enforced by a `commit-msg` hook via
[conventional-pre-commit](https://github.com/compilerla/conventional-pre-commit).
Allowed commit types and scopes are enforced by `--strict` with explicit
`--scopes`.

**Examples:**

```
feat(codex): register CodexReview and CodexDiff commands
feat(core): add review and diff slash command wrappers
fix(nvim): wire on_exit callback to terminal lifecycle
chore(project): update .gitignore
docs(project): add LICENSE file
test(core): add resume dual-mode behavior tests
```

### Release Docs Checklist

When cutting a new release tag:

1. Update the warning banner in `README.md` to state the new latest tag.
2. Verify the release reference points to
   `https://codeberg.org/yaadata/codex.nvim/releases`.

## Adding a New Command

1. **API function** -- Add the public method in `lua/codex/init.lua` with a
   one-line LuaDoc summary (description first), `---@param`/`---@return`
   annotations, and an `ensure_setup()` guard.
2. **User command** -- Register the `:Codex*` command in
   `lua/codex/nvim/commands.lua`, delegating to the API function.
3. **Unit tests** -- Add test cases in `tests/unit/init_spec.lua` covering the
   new API function (happy path, error path, auto-open behaviour).
4. **Command dispatch tests** -- If the command exercises a new code path beyond
   existing patterns, add targeted tests.
5. **README update** -- Add the command to the Commands section and the Lua API
   to the Lua API section in `README.md`.
6. **Types** -- If the command introduces new option types or result types, add
   them to `lua/codex/types.lua`.
7. **Architecture docs** -- Update `docs/command-interactions.md` for any
   command registration or behavior changes, and keep the
   `docs/architecture.md` component-interaction link accurate.
