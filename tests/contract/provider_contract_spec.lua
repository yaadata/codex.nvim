local required_methods = {
  "is_available",
  "open",
  "discover_restorable",
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
          -- ========= [A]ct     =========
          local exported = provider[method]

          -- ========= [A]ssert  =========
          assert.is_function(exported, entry.name .. " is missing " .. method)
        end)
      end

      it("is_available returns a boolean", function()
        -- ========= [A]ct     =========
        local result = provider.is_available()

        -- ========= [A]ssert  =========
        assert.is_boolean(result)
      end)

      it("is_alive returns a boolean for nil handle", function()
        -- ========= [A]ct     =========
        local result = provider.is_alive(nil)

        -- ========= [A]ssert  =========
        assert.is_boolean(result)
      end)

      it("is_ready returns a boolean for nil handle", function()
        -- ========= [A]ct     =========
        local result = provider.is_ready(nil)

        -- ========= [A]ssert  =========
        assert.is_boolean(result)
      end)

      it("get_bufnr returns nil for nil handle", function()
        -- ========= [A]ct     =========
        local result = provider.get_bufnr(nil)

        -- ========= [A]ssert  =========
        assert.is_nil(result)
      end)
    end)
  end
end)
