local prompt_buffer = require("codex.runtime.prompt_buffer")

describe("prompt buffer operations", function()
  it("gradually building the send buffer", function()
    -- ========= [A]rrange =========
    local buffer = prompt_buffer.new()
    local code = [[`lua
local M = {}
`
]]
    assert.True(buffer:is_empty())
    buffer:add("$code:comment ")
    buffer:add("@example.lua#L1\n")
    buffer:add(code)
    assert.False(buffer:is_empty())
    -- ========= [A]ct     =========
    local text, fragments = buffer:take()
    -- ========= [A]ssert  =========
    assert.same({ "$code:comment ", "@example.lua#L1\n", code }, fragments)
    assert.equal("$code:comment @example.lua#L1\n" .. code, text)
    assert.True(buffer:is_empty())
  end)
end)
