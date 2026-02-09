local function with_stubbed_vim_api(run)
  local original_create_autocmd = vim.api.nvim_create_autocmd
  local autocmds = {}

  vim.api.nvim_create_autocmd = function(event, spec)
    table.insert(autocmds, { event = event, spec = spec })
    return #autocmds
  end

  local ok, err = pcall(run, autocmds)
  vim.api.nvim_create_autocmd = original_create_autocmd

  if not ok then
    error(err)
  end
end

describe("codex.providers.snacks", function()
  before_each(function()
    package.loaded["snacks"] = nil
    package.loaded["codex.providers.snacks"] = nil
  end)

  it("registers a TermClose autocmd when on_exit callback is provided", function()
    with_stubbed_vim_api(function(autocmds)
      local terminal = { buf = 42 }
      package.loaded["snacks"] = {
        terminal = function()
          return terminal
        end,
      }

      local provider = require("codex.providers.snacks")
      local exited = {}
      local handle = provider.open(
        "codex",
        {},
        {},
        { terminal = { provider_opts = {} } },
        true,
        function(cb_handle)
          table.insert(exited, cb_handle)
        end
      )

      assert.equals(1, #autocmds)
      assert.equals("TermClose", autocmds[1].event)
      assert.equals(42, autocmds[1].spec.buffer)
      assert.is_true(autocmds[1].spec.once)

      autocmds[1].spec.callback()
      assert.equals(1, #exited)
      assert.same(handle, exited[1])
    end)
  end)

  it("does not register TermClose autocmd when on_exit callback is missing", function()
    with_stubbed_vim_api(function(autocmds)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, { terminal = { provider_opts = {} } }, true, nil)

      assert.equals(0, #autocmds)
    end)
  end)
end)
