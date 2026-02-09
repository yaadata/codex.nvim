local function with_stubbed_command_registration(run)
  local original_create_user_command = vim.api.nvim_create_user_command
  local registered = {}

  vim.api.nvim_create_user_command = function(name, callback, opts)
    registered[name] = {
      callback = callback,
      opts = opts,
    }
  end

  local ok, err = pcall(run, registered)
  vim.api.nvim_create_user_command = original_create_user_command

  if not ok then
    error(err)
  end
end

describe("codex.nvim command registration", function()
  before_each(function()
    package.loaded["codex"] = nil
    package.loaded["codex.nvim.commands"] = nil
  end)

  it("registers Codex and CodexFocus commands", function()
    with_stubbed_command_registration(function(registered)
      require("codex.nvim.commands").register()

      assert.is_not_nil(registered.Codex)
      assert.is_not_nil(registered.CodexFocus)
      assert.is_not_nil(registered.CodexSend)
      assert.is_not_nil(registered.CodexAdd)

      assert.equals(
        "Toggle Codex terminal (use ! to force open and focus)",
        registered.Codex.opts.desc
      )
      assert.is_true(registered.Codex.opts.bang)
      assert.equals(0, registered.Codex.opts.nargs)

      assert.equals(
        "Focus the Codex terminal, starting it if needed",
        registered.CodexFocus.opts.desc
      )
      assert.equals(0, registered.CodexFocus.opts.nargs)

      assert.equals(
        "Send visual selection to Codex with file path and line range",
        registered.CodexSend.opts.desc
      )
      assert.equals(0, registered.CodexSend.opts.nargs)
      assert.is_true(registered.CodexSend.opts.range)

      assert.equals("Add file context to Codex via /mention", registered.CodexAdd.opts.desc)
      assert.equals("?", registered.CodexAdd.opts.nargs)
      assert.equals("file", registered.CodexAdd.opts.complete)
    end)
  end)

  it("dispatches :Codex to toggle", function()
    with_stubbed_command_registration(function(registered)
      local calls = { toggle = 0, open = {} }

      package.loaded["codex"] = {
        toggle = function()
          calls.toggle = calls.toggle + 1
        end,
        open = function(focus)
          table.insert(calls.open, focus)
        end,
      }

      require("codex.nvim.commands").register()
      registered.Codex.callback({ bang = false })

      assert.equals(1, calls.toggle)
      assert.equals(0, #calls.open)
    end)
  end)

  it("dispatches :Codex! to open(true)", function()
    with_stubbed_command_registration(function(registered)
      local calls = { toggle = 0, open = {} }

      package.loaded["codex"] = {
        toggle = function()
          calls.toggle = calls.toggle + 1
        end,
        open = function(focus)
          table.insert(calls.open, focus)
        end,
      }

      require("codex.nvim.commands").register()
      registered.Codex.callback({ bang = true })

      assert.equals(0, calls.toggle)
      assert.equals(1, #calls.open)
      assert.is_true(calls.open[1])
    end)
  end)

  it("dispatches :CodexFocus to focus", function()
    with_stubbed_command_registration(function(registered)
      local focus_calls = 0

      package.loaded["codex"] = {
        focus = function()
          focus_calls = focus_calls + 1
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexFocus.callback()

      assert.equals(1, focus_calls)
    end)
  end)

  it("dispatches :CodexSend with range options", function()
    with_stubbed_command_registration(function(registered)
      local calls = {}

      package.loaded["codex"] = {
        send_selection = function(opts)
          table.insert(calls, opts)
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexSend.callback({ line1 = 2, line2 = 6 })

      assert.equals(1, #calls)
      assert.same({ line1 = 2, line2 = 6 }, calls[1])
    end)
  end)

  it("dispatches :CodexAdd with explicit argument", function()
    with_stubbed_command_registration(function(registered)
      local paths = {}

      package.loaded["codex"] = {
        add_file = function(path)
          table.insert(paths, path)
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexAdd.callback({ args = "/tmp/test.lua" })

      assert.equals(1, #paths)
      assert.equals("/tmp/test.lua", paths[1])
    end)
  end)

  it("dispatches :CodexAdd without argument as nil", function()
    with_stubbed_command_registration(function(registered)
      local called = false
      local received_path = "unset"

      package.loaded["codex"] = {
        add_file = function(path)
          called = true
          received_path = path
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexAdd.callback({ args = "" })

      assert.is_true(called)
      assert.is_nil(received_path)
    end)
  end)
end)
