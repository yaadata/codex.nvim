# Command Interactions

## Overview

This document is the canonical reference for how `:Codex*` commands map from
`lua/codex/nvim/commands.lua` into the public API in `lua/codex/init.lua` (the
facade) and then into `session_lifecycle`, `send_dispatch`, `mention`, and
provider collaborators.

For the authoritative Lua API reference, see [`docs/api.md`](./api.md).

## Command Mapping

| User Command                    | Entry Function                          | Primary Path                                                                                    |
| ------------------------------- | --------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `:Codex`                        | `codex.toggle()`                        | Toggle active terminal or open a focused session                                                |
| `:Codex!`                       | `codex.open(true)`                      | Force-open and focus terminal                                                                   |
| `:CodexFocus`                   | `codex.focus()`                         | Focus active session or open one                                                                |
| `:CodexClose`                   | `codex.close()`                         | Close active session and reset queue                                                            |
| `:CodexClearInput`              | `codex.clear_input()`                   | Send `<C-c>` to active session                                                                  |
| `:CodexSendFile`                | `codex.send_file(opts)`                 | Collect explicit file path (`opts.path`) or current buffer path, format `@path`, send via queue |
| `:CodexSendSelection`           | `codex.send_selection(opts)`            | Collect the active visual selection, format, send via queue                                     |
| `:CodexMentionFile [path]`      | `codex.mention_file(path[, opts])`      | Build `/mention` payload for relative file and submit                                           |
| `:CodexMentionDirectory [path]` | `codex.mention_directory(path[, opts])` | Build `/mention` payload for relative directory (with trailing separator) and submit            |
| `:CodexResume`                  | `codex.resume({ last = false })`        | In-process `/resume` or launch `codex resume`                                                   |
| `:CodexResume!`                 | `codex.resume({ last = true })`         | Launch `codex resume --last` when opening new process                                           |

## Lazy.nvim Command Bootstrap (Recommended)

When configured through lazy.nvim with `cmd = { ... }` and `opts = { ... }`,
the first `:Codex*` invocation typically follows this flow:

```text
User runs :Codex (example)
    |
    v
lazy.nvim command stub for "Codex"
    |
    v
lazy loads codex.nvim
    |
    v
lazy calls require("codex").setup(opts)
    |
    v
init.lua setup() registers :Codex* commands and runtime wiring
    |
    v
command executes against configured codex runtime
```

## Setup Registration Flow

```text
User calls require("codex").setup(opts)
    |
    v
init.lua setup()
    |- build deps (default_deps + opts._deps)
    |- apply config defaults + validation
    |- send_dispatch.create({ get_deps, get_config, get_send_queue, open_session })
    |- send_queue.new({ process = send_dispatch.process_pending_send_item })
    |- mention.create({ get_deps, get_config, dispatch_send })
    |- wrapper_command.create({ get_deps, get_config, dispatch_send })
    |- commands.register()
    \- register VimLeavePre cleanup autocmd
```

## Command Flows

### `:Codex` and `:Codex!`

```text
User runs :Codex (or :Codex!)
    |
    v
commands.lua -> codex.toggle() (or codex.open(true) for :Codex!)
    |
    v
init.lua -> session_lifecycle
    |- toggle_session(deps, config):
    |    |- session_store.get_active()
    |    |- providers.resolve(config.terminal.provider)
    |    |- [active + provider.is_alive(handle)]
    |    |    \- provider.toggle(handle, cmd, args, env, config)
    |    |        \- if new_handle returned, update session.handle
    |    \- [no active session] open_session(deps, config, args, focus=true)
    \- open_session(deps, config, args, focus=true):
         |- provider.open(cmd, args, env, config, focus, on_exit_cb)
         \- session_store.create({ handle, cmd, cwd, provider_name })
```

### `:CodexFocus`

```text
User runs :CodexFocus
    |
    v
commands.lua -> codex.focus()
    |
    v
init.lua focus() -> session_lifecycle
    |- ensure_setup()
    |- focus_session(deps, config)
    |    |- session_store.get_active() + get_provider()
    |    \- [active + alive] -> provider.focus(session.handle), return true
    \- [not focused] -> codex.open(true)
```

### `:CodexClose`

```text
User runs :CodexClose
    |
    v
commands.lua -> codex.close()
    |
    v
init.lua close() -> session_lifecycle.close_session(deps, config, send_queue)
    |- session_store.get_active()
    |- [no active session] -> send_queue.reset() and return
    \- [active session]
         |- provider.close(session.handle)
         |- session_store.remove(session.id)
         \- send_queue.reset()
```

### `:CodexClearInput`

```text
User runs :CodexClearInput
    |
    v
commands.lua -> codex.clear_input()
    |
    v
init.lua clear_input()
    |- ensure_setup()
    |- session_lifecycle.get_active_session_and_provider(deps, config)
    |- [no alive session] -> return false, "no active Codex session"
    \- [alive session] -> provider.send(handle, terminal_io.encode_termcode(deps, "<C-c>"))
```

### `:CodexSendSelection` (Visual Selection Only)

```text
User runs :CodexSendSelection from visual mode (e.g. :'<,'>CodexSendSelection)
    |
    v
commands.lua
    |- resolve_selection_command_opts(opts)
    |    |- resolve_visual_mode(opts)
    |    |    |- [no matching visual marks/range] -> notify error and stop
    |    |    \- [matching marks] -> "v" | "V" | CTRL-V
    |    \- return { line1, line2, visual_mode }
    \- codex.send_selection(selection_opts)
        |
        v
init.lua send_selection()
    |- ensure_setup()
    |- selection_send.resolve_selection_opts(deps, opts)
    |- selection.get_visual_selection(vim, selection_opts)
    |    |- resolve_range(vim_api, bufnr, opts)
    |    |- nvim_buf_get_lines(bufnr, start-1, end, false)
    |    \- return SelectionSpec { path, start_line, end_line, filetype, lines }
    |- nvim_visual.exit_visual_mode_if_active(vim) (best effort)
    |- formatter.format_selection(spec)
    |    \- build ACP selection ref (`@path#Lstart` or `@path#Lstart-end`) + fenced code block + trailing newline
    \- send_dispatch.dispatch_send(terminal_io.encode_bracketed_paste(payload), ...)
         |- [active + ready] -> provider.send(session.handle, text)
         |- [no active session] -> session_lifecycle.open_session(...)
         \- [not ready yet] -> queue + retry loop until ready/timeout
```

### `:CodexSendFile`

```text
User runs :CodexSendFile
    |
    v
commands.lua -> codex.send_file()
    |
    v
init.lua send_file()
    |- ensure_setup()
    |- selection.get_current_buffer_filepath(vim, opts)
    |    |- [opts.path provided] validate explicit file path and return cwd-relative filepath
    |    |- [invalid buffer] -> return nil, "buffer does not exist"
    |    |- [missing path] -> return nil, "current buffer has no file path"
    |    |- [non-file path] -> return nil, "current buffer path is not a regular file"
    |    \- return cwd-relative filepath
    |- formatter.format_buffer_ref(path)
    |    \- build ACP file ref (`@path`) with trailing space
    \- send_dispatch.dispatch_send(terminal_io.encode_bracketed_paste(payload), ...)
         |- [opts.focus == false] -> open_focus=false, post_focus=false
         |- [opts.focus ~= false] -> open_focus=true, post_focus=true
         |- [active + ready] -> provider.send(session.handle, text)
         |- [no active session] -> session_lifecycle.open_session(...)
         \- [not ready yet] -> queue + retry loop until ready/timeout
```

### `:CodexMentionFile [path]` and `:CodexMentionDirectory [path]`

```text
User runs :CodexMentionFile [path] (or :CodexMentionDirectory [path])
    |
    v
commands.lua -> codex.mention_file(path_or_nil) (or codex.mention_directory(path_or_nil))
    |
    v
init.lua mention_file(path[, opts]) / mention_directory(path[, opts]) -> mention module
    |- ensure_setup()
    |- resolve path (arg or current buffer path via %:p / %:p:h)
    |- [missing path] -> log + return false, "current buffer has no file/directory path"
    |- path.to_relative(...)
    |- [directory only] path.ensure_dir_trailing_separator(...)
    \- mention.dispatch(relative_path)
         |- formatter.format_mention(relative_path)
         |- [active + alive] provider.focus(handle) before prompt capture
         |- capture_terminal_prompt_input() (best effort; nearest valid prompt head within lookback)
         |- mention_payload = clear_line_sequence + mention_text
             \- send_dispatch.dispatch_send(mention_payload, { open_focus=true, pre_focus=true, command_path="/mention", on_sent=... })
                  |- on_sent: submit Enter for /mention (multiline capture -> channel send, otherwise feedkeys path)
                  |- on_sent: restore captured prompt input via delayed dispatch_send(...)
                  \- [opts.post_execute] callback once at terminal completion (success/failure)
```

### `execute_slash_command()` (Mention-Style Autosubmit)

`execute_slash_command({ command = ..., args = ... })` runs slash commands with
the same mention-style pre-clear flow used by in-process `resume`:

```text
init.lua -> execute_slash_command(opts)
    |- ensure_setup()
    \- wrapper_command.execute_slash_command(opts)
         |- validate opts table
         |- normalize command + optional args -> command_path ("/<command>")
         |- [active + alive session] provider.focus(handle) before capture
         |- capture prompt input (best effort; nearest valid prompt head, strict compact marker parsing)
         |- [captured input] vim.fn.setreg('"', captured_input)
         |- payload = clear_line_sequence + command_path
         \- send_dispatch.dispatch_send(payload, {
              open_focus = true,
              pre_focus = true,
              command_path = command_path,
              on_sent = function()
                submit Enter for command_path
                (multiline capture -> channel send, otherwise feedkeys path)
              end,
            })
```

Notes:

- `opts.command` is required and may include or omit a leading `/`.
- `opts.args` is optional; empty or whitespace-only args are ignored.
- Existing prompt input is copied to the unnamed register (`"`), then cleared.
- Multiline continuation lines are normalized to strip prompt gutter padding
  before save.
- Successful non-empty save emits a WARN notification.
- If an active session buffer cannot be introspected (`unavailable_buffer`)
  before clear, a WARN notification is emitted.
- Input is not restored after command submission.
- Wrapper command submission is atomic per queue item, so rapid consecutive
  calls keep FIFO command ordering.

Example custom user command wiring lives in [`docs/recipes.md`](./recipes.md).

### `:CodexResume` and `:CodexResume!`

```text
User runs :CodexResume (or :CodexResume!)
    |
    v
commands.lua -> codex.resume({ last = opts.bang })
    |
    v
init.lua resume(opts)
    |- ensure_setup()
    |- session_lifecycle.get_active_session_and_provider(deps, config)
    |- [active + alive session] -> execute_slash_command({ command = "resume" })
    \- [no active/alive session]
         |- args = { "resume" }
         |- if opts.last then args += "--last"
         \- session_lifecycle.open_session(deps, config, args, focus=true)
```
