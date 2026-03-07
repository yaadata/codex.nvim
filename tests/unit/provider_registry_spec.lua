local registry = require("codex.providers")

local function with_stubbed_provider_modules(stubs, run)
  local original_snacks = package.loaded["codex.providers.snacks"]
  local original_native = package.loaded["codex.providers.native"]

  package.loaded["codex.providers.snacks"] = stubs.snacks
  package.loaded["codex.providers.native"] = stubs.native

  local ok, err = pcall(run)

  package.loaded["codex.providers.snacks"] = original_snacks
  package.loaded["codex.providers.native"] = original_native

  if not ok then
    error(err)
  end
end

describe("codex.providers registry", function()
  before_each(function()
    registry.reset()
  end)

  describe("resolve", function()
    it("resolves 'native' to native provider", function()
      -- ========= [A]rrange =========

      -- ========= [A]ct     =========
      local provider, name = registry.resolve("native")

      -- ========= [A]ssert  =========
      assert.is_not_nil(provider)
      assert.equals("native", name)
      assert.is_function(provider.open)
      assert.is_function(provider.close)
      assert.is_function(provider.send)
      assert.is_function(provider.focus)
      assert.is_function(provider.toggle)
      assert.is_function(provider.is_alive)
      assert.is_function(provider.is_available)
      assert.is_function(provider.get_bufnr)
    end)

    it("resolves 'auto' to native when snacks is unavailable", function()
      -- ========= [A]rrange =========

      -- ========= [A]ct     =========
      local provider, name = registry.resolve("auto")

      -- ========= [A]ssert  =========
      assert.is_not_nil(provider)
      assert.equals("native", name)
    end)

    it("caches auto resolution after first detection", function()
      -- ========= [A]rrange =========
      local snacks_checks = 0
      local snacks_provider = {
        is_available = function()
          snacks_checks = snacks_checks + 1
          return false
        end,
      }
      local native_provider = {
        is_available = function()
          return true
        end,
      }

      with_stubbed_provider_modules({
        snacks = snacks_provider,
        native = native_provider,
      }, function()
        registry.reset()
        local first_provider, first_name = registry.resolve("auto")

        -- ========= [A]ct     =========
        local second_provider, second_name = registry.resolve("auto")

        -- ========= [A]ssert  =========
        assert.same(native_provider, first_provider)
        assert.same(first_provider, second_provider)
        assert.equals("native", first_name)
        assert.equals(first_name, second_name)
        assert.equals(1, snacks_checks)
      end)
    end)

    it("re-detects auto resolution after registry reset", function()
      -- ========= [A]rrange =========
      local snacks_checks = 0
      local snacks_provider = {
        is_available = function()
          snacks_checks = snacks_checks + 1
          return false
        end,
      }
      local native_provider = {
        is_available = function()
          return true
        end,
      }

      with_stubbed_provider_modules({
        snacks = snacks_provider,
        native = native_provider,
      }, function()
        registry.reset()
        local _, first_name = registry.resolve("auto")
        registry.reset()

        -- ========= [A]ct     =========
        local _, second_name = registry.resolve("auto")

        -- ========= [A]ssert  =========
        assert.equals("native", first_name)
        assert.equals("native", second_name)
        assert.equals(2, snacks_checks)
      end)
    end)

    it("errors on unknown provider", function()
      -- ========= [A]rrange =========
      local provider_name = "nonexistent"

      -- ========= [A]ct     =========
      local ok = pcall(registry.resolve, provider_name)

      -- ========= [A]ssert  =========
      assert.is_false(ok)
    end)

    it("errors on removed provider name", function()
      -- ========= [A]rrange =========
      local provider_name = "external"

      -- ========= [A]ct     =========
      local ok = pcall(registry.resolve, provider_name)

      -- ========= [A]ssert  =========
      assert.is_false(ok)
    end)
  end)
end)
