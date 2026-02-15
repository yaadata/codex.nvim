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

describe("codex.runtime.send_queue", function()
  before_each(function()
    package.loaded["codex.runtime.send_queue"] = nil
  end)

  it("returns true without scheduling when process sends immediately", function()
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

    local ok, err = queue:submit({ text = "hello" })

    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(1, calls)
    assert.equals(0, #fake_vim._deferred)
  end)

  it("returns false with error when process drops immediately", function()
    local send_queue = require("codex.runtime.send_queue")
    local fake_vim = make_fake_vim()
    local queue = send_queue.new({
      vim = fake_vim,
      retry_interval_ms = 25,
      process = function()
        return "drop", "boom"
      end,
    })

    local ok, err = queue:submit({ text = "hello" })

    assert.is_false(ok)
    assert.equals("boom", err)
    assert.equals(0, #fake_vim._deferred)
  end)

  it("schedules a single timer while retrying", function()
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
    queue:submit({ text = "second" })

    assert.equals(1, #fake_vim._deferred)
    assert.equals(25, fake_vim._deferred[1].delay_ms)
  end)

  it("flushes queued items in FIFO order", function()
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

    assert.equals(0, #sent)
    assert.equals(1, #fake_vim._deferred)

    ready = true
    fake_vim._run_next_deferred()

    assert.same({ "first", "second" }, sent)
  end)

  it("handles nested submit during flush without re-entrant corruption", function()
    local send_queue = require("codex.runtime.send_queue")
    local fake_vim = make_fake_vim()
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

    queue:submit({ text = "first" })
    assert.equals(1, #fake_vim._deferred)

    fake_vim._run_next_deferred()
    assert.same({ "first" }, sent)
    assert.equals(1, #fake_vim._deferred)

    nested_ready = true
    fake_vim._run_next_deferred()
    assert.same({ "first", "nested" }, sent)
  end)

  it("reset clears queued items and flush flags", function()
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
    assert.equals(1, #queue._items)
    assert.equals(1, #fake_vim._deferred)

    queue:reset()

    assert.equals(0, #queue._items)
    assert.is_false(queue._flush_active)
    assert.is_false(queue._flush_scheduled)

    fake_vim._run_next_deferred()
    assert.equals(0, #queue._items)
    assert.equals(0, #fake_vim._deferred)
  end)
end)
