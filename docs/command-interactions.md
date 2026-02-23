# Command Interactions

## Overview

This document is the canonical reference for how `:Codex*` commands map from
`lua/codex/nvim/commands.lua` into the public API in `lua/codex/init.lua` (the
facade) and then into `session_lifecycle`, `send_dispatch`, `mention`, and
provider collaborators.

## Command Mapping

| User Command                    | Entry Function                   | Primary Path                                          |
| ------------------------------- | -------------------------------- | ----------------------------------------------------- |
| `:Codex`                        | `codex.toggle()`                 | Toggle active terminal or open a focused session      |
| `:Codex!`                       | `codex.open(true)`               | Force-open and focus terminal                         |
| `:CodexFocus`                   | `codex.focus()`                  | Focus active session or open one                      |
| `:CodexClose`                   | `codex.close()`                  | Close active session and reset queue                  |
| `:CodexClearInput`              | `codex.clear_input()`            | Send `<C-c>` to active session                        |
| `:CodexSend`                    | `codex.send_selection(opts)`     | Collect selection, format, send via queue             |
| `:CodexMentionFile [path]`      | `codex.mention_file(path)`       | Build `/mention` payload for file and submit          |
| `:CodexMentionDirectory [path]` | `codex.mention_directory(path)`  | Build `/mention` payload for directory and submit     |
| `:CodexResume`                  | `codex.resume({ last = false })` | In-process `/resume` or launch `codex resume`         |
| `:CodexResume!`                 | `codex.resume({ last = true })`  | Launch `codex resume --last` when opening new process |
| `:CodexModel`                   | `codex.set_model()`              | Slash command wrapper (`/model`)                      |
| `:CodexStatus`                  | `codex.show_status()`            | Slash command wrapper (`/status`)                     |
| `:CodexPermissions`             | `codex.show_permissions()`       | Slash command wrapper (`/permissions`)                |
| `:CodexCompact`                 | `codex.compact()`                | Slash command wrapper (`/compact`)                    |
| `:CodexReview [instructions]`   | `codex.review(instructions)`     | Slash command wrapper (`/review ...`)                 |
| `:CodexDiff`                    | `codex.show_diff()`              | Slash command wrapper (`/diff`)                       |

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
    |- commands.register()
    |- keymaps.register(config)
    |    |- unregister stale Codex keymaps from previous setup
    |    |- skip keymaps when keymaps=false
    |    |- skip mapping collisions unless keymaps_force=true
    |    \- register n/x mappings for Codex actions
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

### `:CodexSend` (Range or Visual Selection)

```text
User runs :CodexSend (e.g. :'<,'>CodexSend)
    |
    v
commands.lua
    |- build selection_opts from opts.line1/opts.line2
    |- resolve_visual_mode(opts) when command range matches visual marks
    \- codex.send_selection(selection_opts)
        |
        v
init.lua send_selection()
    |- ensure_setup()
    |- selection.get_visual_selection(vim, opts)
    |    |- resolve_range(vim_api, bufnr, opts)
    |    |- nvim_buf_get_lines(bufnr, start-1, end, false)
    |    \- return SelectionSpec { path, start_line, end_line, filetype, lines }
    |- formatter.format_selection(spec)
    |    \- build fenced code block with adaptive backtick fencing
    \- send_dispatch.dispatch_send(terminal_io.encode_bracketed_paste(payload), ...)
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
init.lua mention_file(path) / mention_directory(path) -> mention module
    |- ensure_setup()
    |- resolve path (arg or current buffer path via %:p / %:p:h)
    |- [missing path] -> log + return false, "current buffer has no file/directory path"
    |- path.to_relative(...)
    \- mention.dispatch(relative_path)
         |- formatter.format_mention(relative_path)
         |- [active + alive] provider.focus(handle) before prompt capture
         |- capture_terminal_prompt_input() (best effort)
         |- mention_payload = clear_line_sequence + mention_text
         \- send_dispatch.dispatch_send(mention_payload, { open_focus=true, pre_focus=true, command_path="/mention", on_sent=... })
              |- on_sent: submit_with_enter_key("/mention")
              \- on_sent: restore captured prompt input via delayed dispatch_send(...)
```

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
    |- [active + alive session] -> send_command("resume") (in-process /resume)
    \- [no active/alive session]
         |- args = { "resume" }
         |- if opts.last then args += "--last"
         \- session_lifecycle.open_session(deps, config, args, focus=true)
```

### Slash Command Wrappers

These commands all route through `send_command()`, which normalizes the slash
command, builds `"/<command>\n"`, and calls:

```text
send_dispatch.dispatch_send(payload, {
  open_focus = true,
  pre_focus = true,
  command_path = "/<command>",
})
```

| User Command                  | API Method             | `send_command(...)` Input   | Command Path             |
| ----------------------------- | ---------------------- | --------------------------- | ------------------------ |
| `:CodexModel`                 | `set_model()`          | `"model"`                   | `/model`                 |
| `:CodexStatus`                | `show_status()`        | `"status"`                  | `/status`                |
| `:CodexPermissions`           | `show_permissions()`   | `"permissions"`             | `/permissions`           |
| `:CodexCompact`               | `compact()`            | `"compact"`                 | `/compact`               |
| `:CodexReview`                | `review(nil)`          | `"review"`                  | `/review`                |
| `:CodexReview <instructions>` | `review(instructions)` | `"review " .. instructions` | `/review <instructions>` |
| `:CodexDiff`                  | `show_diff()`          | `"diff"`                    | `/diff`                  |
