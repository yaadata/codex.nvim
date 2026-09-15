local send_skill = require("codex.context.skill_send")

local function make_env(opts)
  opts = opts or {}
  local dispatch_calls = {}
  local sender = send_skill.create({
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
  })

  return {
    dispatch_calls = dispatch_calls,
    sender = sender,
  }
end

describe("codex.context.send_skill", function()
  it("sends a non-plugin skill", function()
    -- ========= [A]rrange =========
    local env = make_env()
    -- ========= [A]ct     =========
    local ok = env.sender.send_skill({
      name = "code-comment",
    })
    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.dispatch_calls)
    assert.equals("\27[200~$code-comment \27[201~", env.dispatch_calls[1].text)
  end)

  it("sends a plugin skill", function()
    -- ========= [A]rrange =========
    local env = make_env()
    -- ========= [A]ct     =========
    local ok = env.sender.send_skill({
      plugin = "code",
      name = "comment",
    })
    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.dispatch_calls)
    assert.equals("\27[200~$code:comment \27[201~", env.dispatch_calls[1].text)
  end)

  it("rejects invalid skill name", function()
    -- ========= [A]rrange =========
    local env = make_env()
    -- ========= [A]ct     =========
    local ok, err = env.sender.send_skill({
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
    local ok, err = env.sender.send_skill({
      plugin = "%%%",
      name = "comment",
    })
    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.is_match("invalid plugin name", err)
  end)
end)
