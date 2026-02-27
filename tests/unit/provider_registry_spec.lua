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
      local provider, name = registry.resolve("native")
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
      local provider, name = registry.resolve("auto")
      assert.is_not_nil(provider)
      -- In test env, snacks is not installed, so should fall back to native
      assert.equals("native", name)
    end)

    it("caches auto resolution after first detection", function()
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

        local provider_1, name_1 = registry.resolve("auto")
        local provider_2, name_2 = registry.resolve("auto")

        assert.same(native_provider, provider_1)
        assert.same(provider_1, provider_2)
        assert.equals("native", name_1)
        assert.equals(name_1, name_2)
        assert.equals(1, snacks_checks)
      end)
    end)

    it("re-detects auto resolution after registry reset", function()
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
        local _, second_name = registry.resolve("auto")

        assert.equals("native", first_name)
        assert.equals("native", second_name)
        assert.equals(2, snacks_checks)
      end)
    end)

    it("errors on unknown provider", function()
      assert.has_error(function()
        registry.resolve("nonexistent")
      end)
    end)

    it("errors on removed provider name", function()
      assert.has_error(function()
        registry.resolve("external")
      end)
    end)
  end)
end)
