# Lua API

This document is the authoritative reference for the public Lua API exposed by
`codex.nvim`.

> [!NOTE]
> In this document, `codex` refers to `require("codex")`.

For `:Codex*` command flow and internal command-to-component behavior, see
[`docs/command-interactions.md`](./command-interactions.md).

## Table of Contents

- [Return Conventions](#return-conventions)
- [Setup and Runtime](#setup-and-runtime)
- [Session Control](#session-control)
- [Sending and Input](#sending-and-input)
- [Slash and Wrapper Commands](#slash-and-wrapper-commands)
- [Mention Helpers](#mention-helpers)
- [Terminal Keymap Builtins](#terminal-keymap-builtins)

## Return Conventions

| API Scope                                                                 | Return Shape  | Notes                                      |
| ------------------------------------------------------------------------- | ------------- | ------------------------------------------ |
| Send-like, input-control, wrapper-command, resume, and mention APIs       | `ok, err`     | `ok` is `boolean`; `err` is `string\|nil`. |
| Query-style APIs such as `is_running()`, `get_config()`, and `get_logs()` | Varies by API | See the per-API return details below.      |

## Setup and Runtime

| API                  | Description                                                                                                                   | Options / Inputs                                                               | Returns            |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------ |
| `codex.setup(opts)`  | Initialize plugin config and runtime state, register `:Codex*` commands, and wire the send queue and lifecycle collaborators. | `opts` (`table\|nil`): setup options. Call before using the other public APIs. | `nil`              |
| `codex.is_running()` | Return whether the active Codex session is currently alive.                                                                   | None                                                                           | `boolean`          |
| `codex.get_config()` | Return a deep-copied snapshot of the resolved config.                                                                         | None                                                                           | `table\|nil`       |
| `codex.get_logs()`   | Return captured in-memory log entries.                                                                                        | None                                                                           | `codex.LogEntry[]` |
| `codex.clear_logs()` | Clear captured in-memory log entries.                                                                                         | None                                                                           | `nil`              |

## Session Control

| API                 | Description                                                                     | Options / Inputs                                           | Returns |
| ------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------- | ------- |
| `codex.open(focus)` | Open a Codex terminal session.                                                  | `focus` (`boolean\|nil`): defaults to `true` when omitted. | `nil`   |
| `codex.close()`     | Close the active session and reset the send queue.                              | None                                                       | `nil`   |
| `codex.toggle()`    | Toggle the active terminal if one is running, otherwise open a focused session. | None                                                       | `nil`   |
| `codex.focus()`     | Focus the active session, or open one when no session is running.               | None                                                       | `nil`   |

## Sending and Input

| API                             | Description                                                                                           | Options / Inputs                                                                                                                                                                                                                                                   | Returns   |
| ------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------- |
| `codex.send(text)`              | Send raw text through the standard send pipeline.                                                     | `text` (`string`): payload to send.                                                                                                                                                                                                                                | `ok, err` |
| `codex.clear_input()`           | Send `<C-c>` to the active Codex terminal to clear the current prompt input.                          | None                                                                                                                                                                                                                                                               | `ok, err` |
| `codex.copy_input()`            | Copy the current prompt input from the active Codex terminal to the unnamed register.                 | None                                                                                                                                                                                                                                                               | `ok, err` |
| `codex.submit_input()`          | Send Enter to the active Codex terminal to submit the current prompt input.                           | None                                                                                                                                                                                                                                                               | `ok, err` |
| `codex.send_command(slash_cmd)` | Normalize and send a slash command, then auto-submit it with Enter.                                   | `slash_cmd` (`string`): command name with or without a leading `/`.                                                                                                                                                                                                | `ok, err` |
| `codex.send_buffer(opts)`       | Send a file reference as `@path` with a trailing space.                                               | `opts.path` (`string\|nil`): explicit file path, takes precedence over `opts.bufnr`.<br>`opts.bufnr` (`integer\|nil`): buffer to resolve when `opts.path` is omitted.<br>`opts.focus` (`boolean\|nil`): set to `false` to keep editor focus after sending.         | `ok, err` |
| `codex.send_selection(opts)`    | Send a formatted selection reference plus fenced code block, with a trailing newline after the block. | `opts.line1` (`integer\|nil`): explicit start line.<br>`opts.line2` (`integer\|nil`): explicit end line.<br>`opts.visual_mode` (`string\|nil`): visual mode override for custom callers.<br>When omitted, `opts` falls back to the current visual selection/range. | `ok, err` |

## Slash and Wrapper Commands

| API                          | Description                                                                     | Options / Inputs                                                                       | Returns                                                                        |
| ---------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `codex.set_model()`          | Send `/model` using the wrapper-command autosubmit flow.                        | None                                                                                   | `ok, err`                                                                      |
| `codex.show_status()`        | Send `/status` using the wrapper-command autosubmit flow.                       | None                                                                                   | `ok, err`                                                                      |
| `codex.show_permissions()`   | Send `/permissions` using the wrapper-command autosubmit flow.                  | None                                                                                   | `ok, err`                                                                      |
| `codex.compact()`            | Send `/compact` using the wrapper-command autosubmit flow.                      | None                                                                                   | `ok, err`                                                                      |
| `codex.review(instructions)` | Send `/review`, optionally with inline instructions.                            | `instructions` (`string\|nil`): appended after `review` when present and non-empty.    | `ok, err`                                                                      |
| `codex.show_diff()`          | Send `/diff` using the wrapper-command autosubmit flow.                         | None                                                                                   | `ok, err`                                                                      |
| `codex.resume(opts)`         | Resume in-process when an active session exists; otherwise open `codex resume`. | `opts.last` (`boolean\|nil`): when launching a new process, use `codex resume --last`. | `ok, err` for in-process `/resume`; `true` after opening a new resume process. |

## Mention Helpers

| API                                   | Description                                                                                          | Options / Inputs                                                                                                                                                                                    | Returns   |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| `codex.mention_file(path, opts)`      | Send `/mention` for a file path, auto-submit it, then restore previously captured prompt input.      | `path` (`string\|nil`): explicit file path; when omitted, uses the current buffer path.<br>`opts.post_execute` (`fun(ok, err)\|nil`): callback invoked after mention execution completes.           | `ok, err` |
| `codex.mention_directory(path, opts)` | Send `/mention` for a directory path, auto-submit it, then restore previously captured prompt input. | `path` (`string\|nil`): explicit directory path; when omitted, uses the current buffer directory.<br>`opts.post_execute` (`fun(ok, err)\|nil`): callback invoked after mention execution completes. | `ok, err` |

## Terminal Keymap Builtins

| API                                 | Description                                                                                                                                                                                                                     | Available Actions                                                               | Returns                   |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------- |
| `require("codex.keymaps").builtins` | Builtin terminal keymap actions for use in `terminal.keymaps` config. These are action functions intended for terminal-buffer mappings and carry builtin descriptions automatically when used through the keymap helper module. | `toggle`, `clear_input`, `close`, `nav_left`, `nav_down`, `nav_up`, `nav_right` | `table<string, function>` |
