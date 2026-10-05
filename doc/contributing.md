# Contributing

## Setup

You need Neovim >= 0.12.0, Git, and `just`. Project tool versions are defined in
[`mise.toml`](../mise.toml); use Mise if those tools are not already available.

```sh
git clone https://codeberg.org/yaadata/codex.nvim.git
cd codex.nvim
mise install
just bootstrap-test-deps
just pre-commit-install
```

Run commands through `mise exec --` when you need the pinned tools.

## Checks

| Command                                                            | Purpose                                                                |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| `just test`                                                        | Bootstrap Plenary, then run unit and provider-contract tests           |
| `just test-unit`                                                   | Run each unit spec in an isolated Neovim process; four jobs by default |
| `just test-unit 1`                                                 | Run unit specs sequentially                                            |
| `just test-contract`                                               | Check the provider contract                                            |
| `just test-file tests/unit/config_spec.lua`                        | Run one spec                                                           |
| `just test-one tests/unit/config_spec.lua "merges user overrides"` | Run tests whose names contain the literal filter                       |
| `just fmt`                                                         | Format Lua and Markdown                                                |
| `just fmt-check`                                                   | Check formatting                                                       |
| `just lint`                                                        | Run Selene                                                             |
| `just pre-commit-run`                                              | Run all pre-commit checks                                              |

Recipes live in [`Justfile`](../Justfile). The test environment is defined in
[`tests/minimal_init.lua`](../tests/minimal_init.lua), and the name filter in
[`tests/test_filter.lua`](../tests/test_filter.lua). Vim help is formatted
manually; Markdown formatting does not cover it.

## Code and Tests

- Use LuaDoc annotations for public functions and shared types. Put a concise
  summary before the parameter and return tags. See
  [`types.lua`](../lua/codex/types.lua) for API contracts.
- Follow the existing module's structure. Consider deduplication at three
  occurrences, and only when they represent the same behavior.
- Preserve the owning API's return contract: core operations commonly return
  `ok, err`; builtin workflows return an error string or `nil`. Deferred
  failures cannot reach a caller through a synchronous return.
- Keep tests focused on observable behavior owned by the module. Command tests
  check dispatch; builtin tests check workflow choices. Avoid repeating terminal
  capture and delivery cases in every caller's spec.

Use explicit Arrange, Act, and Assert sections. Keep the operation under test
visible in Act; helpers may prepare fixtures, but should not hide that call.
Each test should have one action under test. Omit Arrange when unnecessary.

```lua
it("returns the resolved config", function()
  -- ========= [A]rrange =========
  local env = helpers.setup_with_deps()

  -- ========= [A]ct     =========
  local config = env.codex.get_config()

  -- ========= [A]ssert  =========
  assert.equal("codex-test", config.launch.cmd)
end)
```

Use [`init_spec_helpers.lua`](../tests/unit/helpers/init_spec_helpers.lua) for
mock factories and setup. Clear the relevant `package.loaded` entries when a
fresh module instance is needed.

Restore global overrides in `after_each`, including when assertions fail.
Luassert-managed stubs can use `assert:snapshot()` and `snapshot:revert()`. Keep
fake functions as plain Lua functions when production code checks their type.
`_deps.vim` does not replace global `vim` calls; redirect those explicitly when
testing builtin timers, register writes, or notifications.

## Adding Behavior

1. Choose the owner using the [architecture boundaries](architecture.md).
   Agent-specific commands and launch arguments belong in `codex.builtin`.
2. Add focused tests with the call under test visible. For user commands, test
   argument forwarding by stubbing the API the callback actually calls.
3. Update shared types and user-facing help when signatures or behavior change.
   Keep README examples brief; link to code for implementation details.
4. Run the relevant specs, lint, and formatting checks. Run the full suite
   before committing. See the provider guidance in
   [architecture.md](architecture.md) when adding a provider.

## Commits and Releases

Use focused branches and Conventional Commits:

```text
<type>(<scope>): <subject>
```

Allowed types, scopes, and checks are defined in
[`.pre-commit-config.yaml`](../.pre-commit-config.yaml). Fix failing hooks
rather than bypassing them with `--no-verify`.

For a release, update the README tag reference and keep the release link pointed
at [Codeberg releases](https://codeberg.org/yaadata/codex.nvim/releases).
