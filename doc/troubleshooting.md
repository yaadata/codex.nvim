# Troubleshooting

## Capture Logs

Add these fields to your existing setup options, then restart Neovim:

```lua
log = {
  level = "debug",
  verbose = true,
},
```

Clear old entries, reproduce once, and inspect the results:

```vim
:lua require("codex").logs.clear()
" Reproduce the issue.
:lua vim.print(require("codex").logs.get())
```

To copy the results, if a clipboard provider is available:

```vim
:lua vim.fn.setreg("+", vim.inspect(require("codex").logs.get()))
```

After debugging, restore `log.level = "warn"` and `log.verbose = false` in your
configuration.

## Common Checks

- If the terminal does not open, confirm the configured executable runs outside
  Neovim and inspect `require("codex").get_config()` for the resolved launch and
  provider options.
- If text appears but is not submitted, `prompt_builder.send()` pastes without
  Enter. Use `prompt_builder.submit()` when you want to submit it.
- If a builtin reports a capture failure, open and focus the terminal and retry.
- If help is missing, run `:helptags {path-to-codex.nvim}/doc`.

## Issue Reports

Include your Neovim version, plugin commit, agent version, terminal provider,
relevant configuration, reproduction steps, and captured logs.

For implementation details, browse [`lua/codex/`](../lua/codex/). For test
commands, see [contributing.md](contributing.md).
