local required_methods = {
  "is_available",
  "open",
  "close",
  "send",
  "focus",
  "toggle",
  "is_alive",
  "is_ready",
  "get_bufnr",
}

local provider_modules = {
  { name = "native", path = "codex.providers.native" },
  { name = "snacks", path = "codex.providers.snacks" },
}

describe("provider contract", function()
  for _, entry in ipairs(provider_modules) do
    describe(entry.name .. " provider", function()
      local provider

      before_each(function()
        provider = require(entry.path)
      end)

      for _, method in ipairs(required_methods) do
        it("exports " .. method .. " as a function", function()
          assert.is_function(provider[method], entry.name .. " is missing " .. method)
        end)
      end

      it("is_available returns a boolean", function()
        local result = provider.is_available()
        assert.is_boolean(result)
      end)

      it("is_alive returns a boolean for nil handle", function()
        local result = provider.is_alive(nil)
        assert.is_boolean(result)
      end)

      it("is_ready returns a boolean for nil handle", function()
        local result = provider.is_ready(nil)
        assert.is_boolean(result)
      end)

      it("get_bufnr returns nil for nil handle", function()
        local result = provider.get_bufnr(nil)
        assert.is_nil(result)
      end)
    end)
  end
end)
