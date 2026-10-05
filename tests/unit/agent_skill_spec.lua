local agent_skill = require("codex.context.agent_skill")
local send_buffer = require("codex.runtime.prompt_buffer")

local function make_env(opts)
  opts = opts or {}
  local dispatch_calls = {}
  local buffer = send_buffer.new()
  local mod = agent_skill.create({
    dispatch_send = function(text, send_opts)
      table.insert(dispatch_calls, {
        text = text,
        opts = send_opts,
      })

      if opts.dispatch_send then
        return opts.dispatch_send(text, send_opts)
      end
      return true
    end,
    send_buffer = buffer,
  })

  return {
    send_buffer = buffer,
    dispatch_calls = dispatch_calls,
    module = mod,
  }
end

describe("codex.context.agent_skill", function()
  it("sends a non-plugin skill", function()
    -- ========= [A]rrange =========
    local env = make_env()
    -- ========= [A]ct     =========
    local ok = env.module.send({
      name = "code-comment",
    })
    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equal(1, #env.dispatch_calls)
    assert.equal("\27[200~$code-comment\27[201~", env.dispatch_calls[1].text)
  end)

  it("sends a plugin skill", function()
    -- ========= [A]rrange =========
    local env = make_env()
    -- ========= [A]ct     =========
    local ok = env.module.send({
      plugin = "code",
      name = "comment",
    })
    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equal(1, #env.dispatch_calls)
    assert.equal("\27[200~$code:comment\27[201~", env.dispatch_calls[1].text)
  end)

  it("rejects invalid skill name", function()
    -- ========= [A]rrange =========
    local env = make_env()
    -- ========= [A]ct     =========
    local ok, err = env.module.send({
      plugin = "code",
      name = "!!!",
    })
    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.is_match("invalid skill name", err)
  end)

  it("rejects invalid plugin name", function()
    -- ========= [A]rrange =========
    local env = make_env()
    -- ========= [A]ct     =========
    local ok, err = env.module.send({
      plugin = "%%%",
      name = "comment",
    })
    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.is_match("invalid plugin name", err)
  end)
end)
