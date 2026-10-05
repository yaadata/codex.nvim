local stub = require("luassert.stub")

local function with_stubbed_command_registration(run)
  local registered = {}

  stub(vim.api, "nvim_create_user_command", function(name, callback, opts)
    registered[name] = {
      callback = callback,
      opts = opts,
    }
  end)

  run(registered)
end

describe("codex.nvim command registration", function()
  local stub_snapshot

  before_each(function()
    stub_snapshot = assert:snapshot()
    package.loaded["codex"] = nil
    package.loaded["codex.nvim.commands"] = nil
  end)

  after_each(function()
    stub_snapshot:revert()
  end)

  it("registers Codex commands with expected options", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]ct     =========
      require("codex.nvim.commands").register(package.loaded["codex"])

      -- ========= [A]ssert  =========
      assert.is_not_nil(registered.Codex)
      assert.is_not_nil(registered.CodexFocus)
      assert.is_not_nil(registered.CodexClose)
      assert.is_not_nil(registered.CodexClearInput)
      assert.is_not_nil(registered.CodexSendSelection)
      assert.is_not_nil(registered.CodexSendFile)
      assert.is_not_nil(registered.CodexMentionFile)
      assert.is_not_nil(registered.CodexMentionDirectory)
      assert.equal(
        "Toggle Codex terminal (use ! to force open and focus)",
        registered.Codex.opts.desc
      )
      assert.is_true(registered.Codex.opts.bang)
      assert.equal(0, registered.Codex.opts.nargs)

      assert.equal(
        "Focus the Codex terminal, starting it if needed",
        registered.CodexFocus.opts.desc
      )
      assert.equal(0, registered.CodexFocus.opts.nargs)

      assert.equal("Close the active Codex terminal session", registered.CodexClose.opts.desc)
      assert.equal(0, registered.CodexClose.opts.nargs)

      assert.equal(
        "Clear the active Codex terminal input line",
        registered.CodexClearInput.opts.desc
      )
      assert.equal(0, registered.CodexClearInput.opts.nargs)

      assert.equal(
        "Send visual selection to Codex with file path and line range",
        registered.CodexSendSelection.opts.desc
      )
      assert.equal(0, registered.CodexSendSelection.opts.nargs)
      assert.is_true(registered.CodexSendSelection.opts.range)

      assert.equal(
        "Send current buffer path to Codex as ACP reference",
        registered.CodexSendFile.opts.desc
      )
      assert.equal(0, registered.CodexSendFile.opts.nargs)

      assert.equal("Mention a file in Codex via /mention", registered.CodexMentionFile.opts.desc)
      assert.equal("?", registered.CodexMentionFile.opts.nargs)
      assert.equal("file", registered.CodexMentionFile.opts.complete)

      assert.equal(
        "Mention a directory in Codex via /mention",
        registered.CodexMentionDirectory.opts.desc
      )
      assert.equal("?", registered.CodexMentionDirectory.opts.nargs)
      assert.equal("dir", registered.CodexMentionDirectory.opts.complete)
    end)
  end)

  it("dispatches :Codex to toggle", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local calls = { toggle = 0, open = {} }

      package.loaded["codex"] = {
        session = {
          toggle = function()
            calls.toggle = calls.toggle + 1
          end,
          open = function(focus)
            table.insert(calls.open, focus)
          end,
        },
      }
      require("codex.nvim.commands").register(package.loaded["codex"])

      -- ========= [A]ct     =========
      registered.Codex.callback({ bang = false })

      -- ========= [A]ssert  =========
      assert.equal(1, calls.toggle)
      assert.equal(0, #calls.open)
    end)
  end)

  it("dispatches :Codex! to open(true)", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local calls = { toggle = 0, open = {} }

      package.loaded["codex"] = {
        session = {
          toggle = function()
            calls.toggle = calls.toggle + 1
          end,
          open = function(focus)
            table.insert(calls.open, focus)
          end,
        },
      }

      require("codex.nvim.commands").register(package.loaded["codex"])
      -- ========= [A]ct     =========
      registered.Codex.callback({ bang = true })

      -- ========= [A]ssert  =========
      assert.equal(0, calls.toggle)
      assert.equal(1, #calls.open)
      assert.is_true(calls.open[1])
    end)
  end)

  it("dispatches :CodexFocus to focus", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local focus_calls = 0

      package.loaded["codex"] = {
        session = {
          focus = function()
            focus_calls = focus_calls + 1
          end,
        },
      }

      require("codex.nvim.commands").register(package.loaded["codex"])

      -- ========= [A]ct     =========
      registered.CodexFocus.callback()

      -- ========= [A]ssert  =========
      assert.equal(1, focus_calls)
    end)
  end)

  it("dispatches :CodexClose to close", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local close_calls = 0

      package.loaded["codex"] = {
        session = {
          close = function()
            close_calls = close_calls + 1
          end,
        },
      }

      require("codex.nvim.commands").register(package.loaded["codex"])

      -- ========= [A]ct     =========
      registered.CodexClose.callback()

      -- ========= [A]ssert  =========
      assert.equal(1, close_calls)
    end)
  end)

  it("dispatches :CodexClearInput to clear_input", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local clear_input_calls = 0

      package.loaded["codex"] = {
        input = {
          clear = function()
            clear_input_calls = clear_input_calls + 1
          end,
        },
      }

      require("codex.nvim.commands").register(package.loaded["codex"])

      -- ========= [A]ct     =========
      registered.CodexClearInput.callback()

      -- ========= [A]ssert  =========
      assert.equal(1, clear_input_calls)
    end)
  end)

  it("dispatches :CodexSendSelection with visual range options", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local calls = {}

      package.loaded["codex"] = {
        prompt_builder = {
          clear = function() end,
          add_selection = function(opts)
            table.insert(calls, opts)
          end,
          send = function() end,
        },
      }

      stub(vim.api, "nvim_get_current_buf", function()
        return 3
      end)
      stub(vim.api, "nvim_buf_get_mark", function(_, mark)
        if mark == "<" then
          return { 2, 0 }
        end
        return { 6, 4 }
      end)
      stub(vim.fn, "visualmode", function()
        return "V"
      end)

      require("codex.nvim.commands").register(package.loaded["codex"])

      -- ========= [A]ct     =========
      registered.CodexSendSelection.callback({ line1 = 2, line2 = 6, range = 2 })

      -- ========= [A]ssert  =========
      assert.equal(1, #calls)
      assert.same({ line1 = 2, line2 = 6, visual_mode = "V" }, calls[1])
    end)
  end)

  it("dispatches :CodexSendSelection with visual_mode when range matches visual marks", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local calls = {}

      stub(vim.api, "nvim_get_current_buf", function()
        return 1
      end)
      stub(vim.api, "nvim_buf_get_mark", function(_, mark)
        if mark == "<" then
          return { 2, 1 }
        end
        if mark == ">" then
          return { 6, 3 }
        end
        return { 0, 0 }
      end)
      stub(vim.fn, "visualmode", function()
        return string.char(22)
      end)

      package.loaded["codex"] = {
        prompt_builder = {
          clear = function() end,
          add_selection = function(opts)
            table.insert(calls, opts)
          end,
          send = function() end,
        },
      }

      require("codex.nvim.commands").register(package.loaded["codex"])
      -- ========= [A]ct     =========
      registered.CodexSendSelection.callback({ line1 = 2, line2 = 6, range = 2 })
      -- ========= [A]ssert  =========
      assert.equal(1, #calls)
      assert.same({ line1 = 2, line2 = 6, visual_mode = string.char(22) }, calls[1])
    end)
  end)

  it("rejects :CodexSendSelection outside visual mode", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local calls = {}
      local notifications = {}

      package.loaded["codex"] = {

        prompt_builder = {
          clear = function() end,
          add_selection = function(opts)
            table.insert(calls, opts)
          end,
          send = function() end,
        },
      }
      stub(vim, "notify", function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end)

      require("codex.nvim.commands").register(package.loaded["codex"])

      -- ========= [A]ct     =========
      registered.CodexSendSelection.callback({ line1 = 2, line2 = 6, range = 0 })

      -- ========= [A]ssert  =========
      assert.equal(0, #calls)
      assert.equal(1, #notifications)
      assert.equal(
        "[codex] :CodexSendSelection is only available from visual mode",
        notifications[1].msg
      )
      assert.equal(vim.log.levels.ERROR, notifications[1].level)
    end)
  end)

  it("dispatches :CodexSendFile to send_file", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local calls = 0

      package.loaded["codex"] = {
        prompt_builder = {
          clear = function() end,
          add_file = function()
            calls = calls + 1
          end,
          send = function() end,
        },
      }

      require("codex.nvim.commands").register(package.loaded["codex"])

      -- ========= [A]ct     =========
      registered.CodexSendFile.callback()

      -- ========= [A]ssert  =========
      assert.equal(1, calls)
    end)
  end)

  it("dispatches :CodexMentionFile with explicit argument", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local paths = {}
      local builtin = require("codex.builtin")
      stub(builtin, "mention_file", function(path)
        table.insert(paths, path)
      end)

      require("codex.nvim.commands").register(package.loaded["codex"])

      -- ========= [A]ct     =========
      registered.CodexMentionFile.callback({ args = "/tmp/test.lua" })

      -- ========= [A]ssert  =========
      assert.equal(1, #paths)
      assert.equal("/tmp/test.lua", paths[1])
    end)
  end)

  it("dispatches :CodexMentionFile without argument as nil", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local called = false
      local received_path = "unset"
      local builtin = require("codex.builtin")
      stub(builtin, "mention_file", function(path)
        called = true
        received_path = path
      end)

      require("codex.nvim.commands").register(package.loaded["codex"])

      -- ========= [A]ct     =========
      registered.CodexMentionFile.callback({ args = "" })

      -- ========= [A]ssert  =========
      assert.is_true(called)
      assert.is_nil(received_path)
    end)
  end)

  it("dispatches :CodexMentionDirectory with explicit argument", function()
    -- ========= [A]rrange =========
    with_stubbed_command_registration(function(registered)
      local paths = {}
      local builtin = require("codex.builtin")
      stub(builtin, "mention_directory", function(path)
        table.insert(paths, path)
      end)

      require("codex.nvim.commands").register(package.loaded["codex"])
      -- ========= [A]ct     =========
      registered.CodexMentionDirectory.callback({ args = "/tmp/" })

      -- ========= [A]ssert  =========
      assert.equal(1, #paths)
      assert.equal("/tmp/", paths[1])
    end)
  end)

  it("dispatches :CodexMentionDirectory without argument as nil", function()
    with_stubbed_command_registration(function(registered)
      -- ========= [A]rrange =========
      local called = false
      local received_path = "unset"
      local builtin = require("codex.builtin")
      stub(builtin, "mention_directory", function(path)
        called = true
        received_path = path
      end)
      require("codex.nvim.commands").register(package.loaded["codex"])
      -- ========= [A]ct     =========
      registered.CodexMentionDirectory.callback({ args = "" })

      -- ========= [A]ssert  =========
      assert.is_true(called)
      assert.is_nil(received_path)
    end)
  end)
end)
