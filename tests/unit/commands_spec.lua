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

  it("registers Codex phase 1/2/3/4 commands with expected options", function()
    with_stubbed_command_registration(function(registered)
      require("codex.nvim.commands").register()

      assert.is_not_nil(registered.Codex)
      assert.is_not_nil(registered.CodexFocus)
      assert.is_not_nil(registered.CodexClose)
      assert.is_not_nil(registered.CodexSend)
      assert.is_not_nil(registered.CodexAdd)
      assert.is_not_nil(registered.CodexResume)
      assert.is_not_nil(registered.CodexModel)
      assert.is_not_nil(registered.CodexStatus)
      assert.is_not_nil(registered.CodexPermissions)
      assert.is_not_nil(registered.CodexCompact)
      assert.is_not_nil(registered.CodexReview)
      assert.is_not_nil(registered.CodexDiff)

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

      assert.equals("Close the active Codex terminal session", registered.CodexClose.opts.desc)
      assert.equals(0, registered.CodexClose.opts.nargs)

      assert.equals(
        "Send visual selection to Codex with file path and line range",
        registered.CodexSend.opts.desc
      )
      assert.equals(0, registered.CodexSend.opts.nargs)
      assert.is_true(registered.CodexSend.opts.range)

      assert.equals("Add file context to Codex via /mention", registered.CodexAdd.opts.desc)
      assert.equals("?", registered.CodexAdd.opts.nargs)
      assert.equals("file", registered.CodexAdd.opts.complete)

      assert.equals(
        "Resume Codex session picker (use ! to launch with --last when needed)",
        registered.CodexResume.opts.desc
      )
      assert.equals(0, registered.CodexResume.opts.nargs)
      assert.is_true(registered.CodexResume.opts.bang)

      assert.equals("Open Codex model picker", registered.CodexModel.opts.desc)
      assert.equals(0, registered.CodexModel.opts.nargs)

      assert.equals("Show Codex status summary", registered.CodexStatus.opts.desc)
      assert.equals(0, registered.CodexStatus.opts.nargs)

      assert.equals("Open Codex permissions selector", registered.CodexPermissions.opts.desc)
      assert.equals(0, registered.CodexPermissions.opts.nargs)

      assert.equals("Run Codex /compact in the active session", registered.CodexCompact.opts.desc)
      assert.equals(0, registered.CodexCompact.opts.nargs)

      assert.equals(
        "Run Codex /review (or /review <instructions>)",
        registered.CodexReview.opts.desc
      )
      assert.equals("*", registered.CodexReview.opts.nargs)

      assert.equals("Run Codex /diff in the active session", registered.CodexDiff.opts.desc)
      assert.equals(0, registered.CodexDiff.opts.nargs)
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

  it("dispatches :CodexClose to close", function()
    with_stubbed_command_registration(function(registered)
      local close_calls = 0

      package.loaded["codex"] = {
        close = function()
          close_calls = close_calls + 1
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexClose.callback()

      assert.equals(1, close_calls)
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

  it("dispatches :CodexSend with visual_mode when range matches visual marks", function()
    with_stubbed_command_registration(function(registered)
      local original_get_current_buf = vim.api.nvim_get_current_buf
      local original_get_mark = vim.api.nvim_buf_get_mark
      local original_visualmode = vim.fn.visualmode
      local calls = {}

      vim.api.nvim_get_current_buf = function()
        return 1
      end
      vim.api.nvim_buf_get_mark = function(_, mark)
        if mark == "<" then
          return { 2, 1 }
        end
        if mark == ">" then
          return { 6, 3 }
        end
        return { 0, 0 }
      end
      vim.fn.visualmode = function()
        return string.char(22)
      end

      package.loaded["codex"] = {
        send_selection = function(opts)
          table.insert(calls, opts)
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexSend.callback({ line1 = 2, line2 = 6, range = 2 })

      vim.api.nvim_get_current_buf = original_get_current_buf
      vim.api.nvim_buf_get_mark = original_get_mark
      vim.fn.visualmode = original_visualmode

      assert.equals(1, #calls)
      assert.same({ line1 = 2, line2 = 6, visual_mode = string.char(22) }, calls[1])
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

  it("dispatches :CodexResume and :CodexResume! with expected last flag", function()
    with_stubbed_command_registration(function(registered)
      local calls = {}

      package.loaded["codex"] = {
        resume = function(opts)
          table.insert(calls, opts)
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexResume.callback({ bang = false })
      registered.CodexResume.callback({ bang = true })

      assert.equals(2, #calls)
      assert.same({ last = false }, calls[1])
      assert.same({ last = true }, calls[2])
    end)
  end)

  it("dispatches :CodexModel to set_model", function()
    with_stubbed_command_registration(function(registered)
      local calls = 0

      package.loaded["codex"] = {
        set_model = function()
          calls = calls + 1
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexModel.callback()

      assert.equals(1, calls)
    end)
  end)

  it("dispatches :CodexStatus to show_status", function()
    with_stubbed_command_registration(function(registered)
      local calls = 0

      package.loaded["codex"] = {
        show_status = function()
          calls = calls + 1
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexStatus.callback()

      assert.equals(1, calls)
    end)
  end)

  it("dispatches :CodexPermissions to show_permissions", function()
    with_stubbed_command_registration(function(registered)
      local calls = 0

      package.loaded["codex"] = {
        show_permissions = function()
          calls = calls + 1
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexPermissions.callback()

      assert.equals(1, calls)
    end)
  end)

  it("dispatches :CodexCompact to compact", function()
    with_stubbed_command_registration(function(registered)
      local calls = 0

      package.loaded["codex"] = {
        compact = function()
          calls = calls + 1
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexCompact.callback()

      assert.equals(1, calls)
    end)
  end)

  it("dispatches :CodexReview without args as nil instructions", function()
    with_stubbed_command_registration(function(registered)
      local called = 0
      local received = "unset"

      package.loaded["codex"] = {
        review = function(instructions)
          called = called + 1
          received = instructions
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexReview.callback({ args = "" })

      assert.equals(1, called)
      assert.is_nil(received)
    end)
  end)

  it("dispatches :CodexReview with args to review(instructions)", function()
    with_stubbed_command_registration(function(registered)
      local calls = {}

      package.loaded["codex"] = {
        review = function(instructions)
          table.insert(calls, instructions)
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexReview.callback({ args = "focus on security" })

      assert.equals(1, #calls)
      assert.equals("focus on security", calls[1])
    end)
  end)

  it("dispatches :CodexDiff to show_diff", function()
    with_stubbed_command_registration(function(registered)
      local calls = 0

      package.loaded["codex"] = {
        show_diff = function()
          calls = calls + 1
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexDiff.callback()

      assert.equals(1, calls)
    end)
  end)
end)
