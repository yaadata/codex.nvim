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

  it("registers Codex commands with expected options", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]ct     =========
      require("codex.nvim.commands").register()

      -- ========= [A]ssert  =========
      assert.is_not_nil(registered.Codex)
      assert.is_not_nil(registered.CodexFocus)
      assert.is_not_nil(registered.CodexClose)
      assert.is_not_nil(registered.CodexClearInput)
      assert.is_not_nil(registered.CodexSend)
      assert.is_not_nil(registered.CodexAddBuffer)
      assert.is_not_nil(registered.CodexMentionFile)
      assert.is_not_nil(registered.CodexMentionDirectory)
      assert.is_not_nil(registered.CodexResume)
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
        "Clear the active Codex terminal input line",
        registered.CodexClearInput.opts.desc
      )
      assert.equals(0, registered.CodexClearInput.opts.nargs)

      assert.equals(
        "Send visual selection to Codex with file path and line range",
        registered.CodexSend.opts.desc
      )
      assert.equals(0, registered.CodexSend.opts.nargs)
      assert.is_true(registered.CodexSend.opts.range)

      assert.equals(
        "Send current buffer path to Codex as ACP reference",
        registered.CodexAddBuffer.opts.desc
      )
      assert.equals(0, registered.CodexAddBuffer.opts.nargs)

      assert.equals("Mention a file in Codex via /mention", registered.CodexMentionFile.opts.desc)
      assert.equals("?", registered.CodexMentionFile.opts.nargs)
      assert.equals("file", registered.CodexMentionFile.opts.complete)

      assert.equals(
        "Mention a directory in Codex via /mention",
        registered.CodexMentionDirectory.opts.desc
      )
      assert.equals("?", registered.CodexMentionDirectory.opts.nargs)
      assert.equals("dir", registered.CodexMentionDirectory.opts.complete)

      assert.equals(
        "Resume Codex session picker (use ! to launch with --last when needed)",
        registered.CodexResume.opts.desc
      )
      assert.equals(0, registered.CodexResume.opts.nargs)
      assert.is_true(registered.CodexResume.opts.bang)
    end)
  end)

  it("dispatches :Codex to toggle", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
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

      -- ========= [A]ct     =========
      registered.Codex.callback({ bang = false })

      -- ========= [A]ssert  =========
      assert.equals(1, calls.toggle)
      assert.equals(0, #calls.open)
    end)
  end)

  it("dispatches :Codex! to open(true)", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
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
      -- ========= [A]ct     =========
      registered.Codex.callback({ bang = true })

      -- ========= [A]ssert  =========
      assert.equals(0, calls.toggle)
      assert.equals(1, #calls.open)
      assert.is_true(calls.open[1])
    end)
  end)

  it("dispatches :CodexFocus to focus", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local focus_calls = 0

      package.loaded["codex"] = {
        focus = function()
          focus_calls = focus_calls + 1
        end,
      }

      require("codex.nvim.commands").register()

      -- ========= [A]ct     =========
      registered.CodexFocus.callback()

      -- ========= [A]ssert  =========
      assert.equals(1, focus_calls)
    end)
  end)

  it("dispatches :CodexClose to close", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local close_calls = 0

      package.loaded["codex"] = {
        close = function()
          close_calls = close_calls + 1
        end,
      }

      require("codex.nvim.commands").register()

      -- ========= [A]ct     =========
      registered.CodexClose.callback()

      -- ========= [A]ssert  =========
      assert.equals(1, close_calls)
    end)
  end)

  it("dispatches :CodexClearInput to clear_input", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local clear_input_calls = 0

      package.loaded["codex"] = {
        clear_input = function()
          clear_input_calls = clear_input_calls + 1
        end,
      }

      require("codex.nvim.commands").register()

      -- ========= [A]ct     =========
      registered.CodexClearInput.callback()

      -- ========= [A]ssert  =========
      assert.equals(1, clear_input_calls)
    end)
  end)

  it("dispatches :CodexSend with range options", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local calls = {}

      package.loaded["codex"] = {
        send_selection = function(opts)
          table.insert(calls, opts)
        end,
      }

      require("codex.nvim.commands").register()

      -- ========= [A]ct     =========
      registered.CodexSend.callback({ line1 = 2, line2 = 6 })

      -- ========= [A]ssert  =========
      assert.equals(1, #calls)
      assert.same({ line1 = 2, line2 = 6 }, calls[1])
    end)
  end)

  it("dispatches :CodexSend with visual_mode when range matches visual marks", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
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
      -- ========= [A]ct     =========
      registered.CodexSend.callback({ line1 = 2, line2 = 6, range = 2 })
      vim.api.nvim_get_current_buf = original_get_current_buf
      vim.api.nvim_buf_get_mark = original_get_mark
      vim.fn.visualmode = original_visualmode
      -- ========= [A]ssert  =========
      assert.equals(1, #calls)
      assert.same({ line1 = 2, line2 = 6, visual_mode = string.char(22) }, calls[1])
    end)
  end)

  it("dispatches :CodexAddBuffer to send_buffer", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local calls = 0

      package.loaded["codex"] = {
        send_buffer = function()
          calls = calls + 1
        end,
      }

      require("codex.nvim.commands").register()

      -- ========= [A]ct     =========
      registered.CodexAddBuffer.callback()

      -- ========= [A]ssert  =========
      assert.equals(1, calls)
    end)
  end)

  it("dispatches :CodexMentionFile with explicit argument", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local paths = {}

      package.loaded["codex"] = {
        mention_file = function(path)
          table.insert(paths, path)
        end,
      }

      require("codex.nvim.commands").register()

      -- ========= [A]ct     =========
      registered.CodexMentionFile.callback({ args = "/tmp/test.lua" })

      -- ========= [A]ssert  =========
      assert.equals(1, #paths)
      assert.equals("/tmp/test.lua", paths[1])
    end)
  end)

  it("dispatches :CodexMentionFile without argument as nil", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local called = false
      local received_path = "unset"

      package.loaded["codex"] = {
        mention_file = function(path)
          called = true
          received_path = path
        end,
      }

      require("codex.nvim.commands").register()

      -- ========= [A]ct     =========
      registered.CodexMentionFile.callback({ args = "" })

      -- ========= [A]ssert  =========
      assert.is_true(called)
      assert.is_nil(received_path)
    end)
  end)

  it("dispatches :CodexMentionDirectory with explicit argument", function()
    -- ========= [A]rrange =========
    -- ========= [A]ct     =========
    -- ========= [A]ssert  =========
    with_stubbed_command_registration(function(registered)
      local paths = {}

      package.loaded["codex"] = {
        mention_directory = function(path)
          table.insert(paths, path)
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexMentionDirectory.callback({ args = "/tmp/" })

      assert.equals(1, #paths)
      assert.equals("/tmp/", paths[1])
    end)
  end)

  it("dispatches :CodexMentionDirectory without argument as nil", function()
    -- ========= [A]rrange =========
    -- ========= [A]ct     =========
    -- ========= [A]ssert  =========
    with_stubbed_command_registration(function(registered)
      local called = false
      local received_path = "unset"

      package.loaded["codex"] = {
        mention_directory = function(path)
          called = true
          received_path = path
        end,
      }

      require("codex.nvim.commands").register()
      registered.CodexMentionDirectory.callback({ args = "" })

      assert.is_true(called)
      assert.is_nil(received_path)
    end)
  end)

  it("dispatches :CodexResume and :CodexResume! with expected last flag", function()
    -- ========= [A]rrange =========
    -- ========= [A]ct     =========
    -- ========= [A]ssert  =========
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
end)
