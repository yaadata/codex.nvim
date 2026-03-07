# Lua API

This document is the authoritative reference for the public Lua API exposed by
`codex.nvim`.

For `:Codex*` command flow and internal command-to-component behavior, see
[`docs/command-interactions.md`](./command-interactions.md).

## Return Conventions

Send-like, wrapper-command, resume, and mention APIs return:

- `ok` (`boolean`) whether the request was sent immediately or queued
  successfully.
- `err` (`string|nil`) error details when the request could not be dispatched.

Query-style APIs such as `is_running()`, `get_config()`, and `get_logs()` use
their own return shapes documented in their sections below.

## Setup and Runtime

### `require("codex").setup(opts)`

Initialize plugin config and runtime state, register `:Codex*` commands, and
wire the send queue and lifecycle collaborators.

Call this before using the other public APIs.

### `require("codex").is_running()`

Return whether the active Codex session is currently alive.

### `require("codex").get_config()`

Return a deep-copied snapshot of the resolved config, or `nil` before setup.

### `require("codex").get_logs()`

Return captured in-memory log entries.

### `require("codex").clear_logs()`

Clear captured in-memory log entries.

## Session Control

### `require("codex").open(focus)`

Open a Codex terminal session. When `focus` is omitted, it defaults to `true`.

### `require("codex").close()`

Close the active session and reset the send queue.

### `require("codex").toggle()`

Toggle the active terminal if one is running, otherwise open a focused session.

### `require("codex").focus()`

Focus the active session, or open one when no session is running.

## Sending and Input

### `require("codex").send(text)`

Send raw text through the standard send pipeline.

- `text` (`string`): payload to send.

### `require("codex").clear_input()`

Send `<C-c>` to the active Codex terminal to clear the current prompt input.

### `require("codex").send_command(slash_cmd)`

Normalize and send a slash command, then auto-submit it with Enter.

- `slash_cmd` (`string`): command name with or without a leading `/`.

### `require("codex").send_buffer(opts)`

Send a file reference as `@path` with a trailing space.

Options:

- `opts.path` (`string|nil`): explicit file path to send; takes precedence over
  `opts.bufnr`.
- `opts.bufnr` (`integer|nil`): buffer to resolve when `opts.path` is omitted.
- `opts.focus` (`boolean|nil`): set to `false` to keep editor focus after
  sending; defaults to focused send behavior.

Returns an error when the target buffer or path cannot be resolved to a regular
file.

### `require("codex").send_selection(opts)`

Send a formatted selection reference plus fenced code block, with a trailing
newline after the block.

Options:

- `opts.line1` (`integer|nil`): start line for an explicit range.
- `opts.line2` (`integer|nil`): end line for an explicit range.
- `opts.visual_mode` (`string|nil`): visual mode override when needed by custom
  callers.

When `opts` is omitted, the function falls back to the current visual
selection/range.

## Slash and Wrapper Commands

### `require("codex").set_model()`

Send `/model` using the wrapper-command autosubmit flow.

### `require("codex").show_status()`

Send `/status` using the wrapper-command autosubmit flow.

### `require("codex").show_permissions()`

Send `/permissions` using the wrapper-command autosubmit flow.

### `require("codex").compact()`

Send `/compact` using the wrapper-command autosubmit flow.

### `require("codex").review(instructions)`

Send `/review`, optionally with inline instructions.

- `instructions` (`string|nil`): appended after `review ` when present and
  non-empty.

### `require("codex").show_diff()`

Send `/diff` using the wrapper-command autosubmit flow.

### `require("codex").resume(opts)`

Resume in-process when an active session exists; otherwise open `codex resume`.

Options:

- `opts.last` (`boolean|nil`): when launching a new process, use
  `codex resume --last`.

Returns `true` after opening a new resume process, or the standard `ok, err`
result when dispatching in-process `/resume`.

## Mention Helpers

### `require("codex").mention_file(path, opts)`

Send `/mention` for a file path, auto-submit it, then restore previously
captured prompt input.

- `path` (`string|nil`): explicit file path; when omitted, uses the current
  buffer path.
- `opts.post_execute` (`fun(ok, err)|nil`): callback invoked after mention
  execution completes.

### `require("codex").mention_directory(path, opts)`

Send `/mention` for a directory path, auto-submit it, then restore previously
captured prompt input.

- `path` (`string|nil`): explicit directory path; when omitted, uses the
  current buffer directory.
- `opts.post_execute` (`fun(ok, err)|nil`): callback invoked after mention
  execution completes.

## Terminal Keymap Builtins

### `require("codex.keymaps").builtins`

Builtin terminal keymap actions for use in `terminal.keymaps` config:

- `toggle`
- `clear_input`
- `close`
- `nav_left`
- `nav_down`
- `nav_up`
- `nav_right`

These are action functions intended for terminal-buffer mappings and carry
builtin descriptions automatically when used through the keymap helper module.
