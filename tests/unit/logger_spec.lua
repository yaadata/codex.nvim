describe("codex.logger", function()
  local logger
  local original_notify
  local notify_calls

  before_each(function()
    package.loaded["codex.logger"] = nil
    logger = require("codex.logger")
    original_notify = vim.notify
    notify_calls = {}
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end
    logger.set_level("warn")
    logger.set_verbose(false)
    logger.clear_logs()
  end)

  after_each(function()
    vim.notify = original_notify
  end)

  it("captures and notifies only entries that pass the level filter", function()
    -- ========= [A]rrange =========
    logger.info("info message")

    -- ========= [A]ct     =========
    logger.warn("warn %s", "message")

    -- ========= [A]ssert  =========
    assert.equals(1, #notify_calls)
    assert.equals("[codex] warn message", notify_calls[1].msg)

    local logs = logger.get_logs()
    assert.equals(1, #logs)
    assert.is_true(logs[1].seq > 0)
    assert.equals("warn", logs[1].level)
    assert.equals("warn message", logs[1].message)
    assert.is_false(logs[1].verbose)
  end)

  it("records verbose debug entries without sending notifications", function()
    -- ========= [A]rrange =========
    logger.set_level("debug")
    logger.set_verbose(true)

    -- ========= [A]ct     =========
    logger.vdebug("detail %d", 7)

    -- ========= [A]ssert  =========
    assert.equals(0, #notify_calls)
    local logs = logger.get_logs()
    assert.equals(1, #logs)
    assert.is_true(logs[1].seq > 0)
    assert.equals("debug", logs[1].level)
    assert.equals("detail 7", logs[1].message)
    assert.is_true(logs[1].verbose)
  end)

  it("sorts collected logs by monotonic seq when deferred entries flush later", function()
    -- ========= [A]rrange =========
    logger.set_level("debug")
    logger.set_verbose(true)
    logger.vdebug("first")

    -- ========= [A]ct     =========
    logger.warn("second")

    -- ========= [A]ssert  =========
    local logs = logger.get_logs()
    assert.equals(2, #logs)
    assert.equals("first", logs[1].message)
    assert.equals("second", logs[2].message)
    assert.is_true(logs[1].seq < logs[2].seq)
  end)

  it("drops verbose debug entries when verbose mode is disabled", function()
    -- ========= [A]rrange =========
    logger.set_level("debug")
    logger.set_verbose(false)

    -- ========= [A]ct     =========
    logger.vdebug("detail")

    -- ========= [A]ssert  =========
    assert.equals(0, #notify_calls)
    assert.equals(0, #logger.get_logs())
  end)

  it("keeps only the latest 1000 captured log entries", function()
    -- ========= [A]rrange =========
    logger.set_level("debug")
    logger.set_verbose(true)

    for i = 1, 1004 do
      logger.vdebug("entry %d", i)
    end

    -- ========= [A]ct     =========
    logger.vdebug("entry %d", 1005)

    -- ========= [A]ssert  =========
    local logs = logger.get_logs()
    assert.equals(1000, #logs)
    assert.equals("entry 6", logs[1].message)
    assert.equals("entry 1005", logs[#logs].message)
  end)

  it("clears captured logs", function()
    -- ========= [A]rrange =========
    logger.warn("one")

    -- ========= [A]ct     =========
    logger.clear_logs()

    -- ========= [A]ssert  =========
    assert.equals(0, #logger.get_logs())
  end)

  it("clears deferred non-critical logs", function()
    -- ========= [A]rrange =========
    logger.set_level("debug")
    logger.debug("queued")

    -- ========= [A]ct     =========
    logger.clear_logs()

    -- ========= [A]ssert  =========
    assert.equals(0, #logger.get_logs())
  end)
end)
