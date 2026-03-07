local function make_fake_vim()
  local deferred = {}
  local scheduled = {}

  local function run_next_deferred()
    if #deferred == 0 then
      return false
    end

    local next_timer = table.remove(deferred, 1)
    next_timer.cb()
    return true
  end

  return {
    defer_fn = function(cb, delay_ms)
      table.insert(deferred, { cb = cb, delay_ms = delay_ms })
    end,
    schedule = function(cb)
      table.insert(scheduled, cb)
    end,
    _deferred = deferred,
    _scheduled = scheduled,
    _run_next_deferred = run_next_deferred,
  }
end

local function make_nested_queue(send_queue, fake_vim)
  local nested_ready = false
  local sent = {}
  local queue

  queue = send_queue.new({
    vim = fake_vim,
    retry_interval_ms = 25,
    process = function(item)
      if item.text == "first" and not item.retried then
        item.retried = true
        return "retry"
      end

      if item.text == "first" then
        queue:submit({ text = "nested" })
        table.insert(sent, "first")
        return "sent"
      end

      if item.text == "nested" and not nested_ready then
        return "retry"
      end

      table.insert(sent, item.text)
      return "sent"
    end,
  })

  return queue, sent, function(value)
    nested_ready = value
  end
end

describe("codex.runtime.send_queue", function()
  before_each(function()
    package.loaded["codex.runtime.send_queue"] = nil
  end)

  it("returns true without scheduling when process sends immediately", function()
    -- ========= [A]rrange =========
    local send_queue = require("codex.runtime.send_queue")
    local fake_vim = make_fake_vim()
    local calls = 0
    local queue = send_queue.new({
      vim = fake_vim,
      retry_interval_ms = 25,
      process = function()
        calls = calls + 1
        return "sent"
      end,
    })

    -- ========= [A]ct     =========
    local ok, err = queue:submit({ text = "hello" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(1, calls)
    assert.equals(0, #fake_vim._deferred)
  end)

  it("returns false with error when process drops immediately", function()
    -- ========= [A]rrange =========
    local send_queue = require("codex.runtime.send_queue")
    local fake_vim = make_fake_vim()
    local queue = send_queue.new({
      vim = fake_vim,
      retry_interval_ms = 25,
      process = function()
        return "drop", "boom"
      end,
    })

    -- ========= [A]ct     =========
    local ok, err = queue:submit({ text = "hello" })

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("boom", err)
    assert.equals(0, #fake_vim._deferred)
  end)

  it("schedules a single timer while retrying", function()
    -- ========= [A]rrange =========
    local send_queue = require("codex.runtime.send_queue")
    local fake_vim = make_fake_vim()
    local queue = send_queue.new({
      vim = fake_vim,
      retry_interval_ms = 25,
      process = function()
        return "retry"
      end,
    })
    queue:submit({ text = "first" })

    -- ========= [A]ct     =========
    queue:submit({ text = "second" })

    -- ========= [A]ssert  =========
    assert.equals(1, #fake_vim._deferred)
    assert.equals(25, fake_vim._deferred[1].delay_ms)
  end)

  it("flushes queued items in FIFO order", function()
    -- ========= [A]rrange =========
    local send_queue = require("codex.runtime.send_queue")
    local fake_vim = make_fake_vim()
    local ready = false
    local sent = {}
    local queue = send_queue.new({
      vim = fake_vim,
      retry_interval_ms = 25,
      process = function(item)
        if not ready then
          return "retry"
        end
        table.insert(sent, item.text)
        return "sent"
      end,
    })
    queue:submit({ text = "first" })
    queue:submit({ text = "second" })
    ready = true

    -- ========= [A]ct     =========
    local did_run = fake_vim._run_next_deferred()

    -- ========= [A]ssert  =========
    assert.is_true(did_run)
    assert.same({ "first", "second" }, sent)
  end)

  it("queues nested submit for later retry during flush without re-entrant corruption", function()
    -- ========= [A]rrange =========
    local send_queue = require("codex.runtime.send_queue")
    local fake_vim = make_fake_vim()
    local queue, sent = make_nested_queue(send_queue, fake_vim)
    queue:submit({ text = "first" })

    -- ========= [A]ct     =========
    local did_run = fake_vim._run_next_deferred()

    -- ========= [A]ssert  =========
    assert.is_true(did_run)
    assert.same({ "first" }, sent)
    assert.equals(1, #fake_vim._deferred)
  end)

  it("flushes nested submit on a later retry", function()
    -- ========= [A]rrange =========
    local send_queue = require("codex.runtime.send_queue")
    local fake_vim = make_fake_vim()
    local queue, sent, set_nested_ready = make_nested_queue(send_queue, fake_vim)
    queue:submit({ text = "first" })
    fake_vim._run_next_deferred()
    set_nested_ready(true)

    -- ========= [A]ct     =========
    local did_run = fake_vim._run_next_deferred()

    -- ========= [A]ssert  =========
    assert.is_true(did_run)
    assert.same({ "first", "nested" }, sent)
  end)

  it("reset clears queued items and flush flags", function()
    -- ========= [A]rrange =========
    local send_queue = require("codex.runtime.send_queue")
    local fake_vim = make_fake_vim()
    local queue = send_queue.new({
      vim = fake_vim,
      retry_interval_ms = 25,
      process = function()
        return "retry"
      end,
    })
    queue:submit({ text = "first" })

    -- ========= [A]ct     =========
    queue:reset()

    -- ========= [A]ssert  =========
    assert.equals(0, #queue._items)
    assert.is_false(queue._flush_active)
    assert.is_false(queue._flush_scheduled)
  end)

  it("ignores stale deferred flush after reset", function()
    -- ========= [A]rrange =========
    local send_queue = require("codex.runtime.send_queue")
    local fake_vim = make_fake_vim()
    local queue = send_queue.new({
      vim = fake_vim,
      retry_interval_ms = 25,
      process = function()
        return "retry"
      end,
    })
    queue:submit({ text = "first" })
    queue:reset()

    -- ========= [A]ct     =========
    local did_run = fake_vim._run_next_deferred()

    -- ========= [A]ssert  =========
    assert.is_true(did_run)
    assert.equals(0, #queue._items)
    assert.equals(0, #fake_vim._deferred)
  end)
end)
