local store = require("codex.state.session_store")

describe("codex.state.session_store", function()
  before_each(function()
    store.reset()
  end)

  describe("create", function()
    it("returns an id", function()
      -- ========= [A]rrange =========
      local session = { handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" }

      -- ========= [A]ct     =========
      local id = store.create(session)

      -- ========= [A]ssert  =========
      assert.is_string(id)
      assert.truthy(id:match("^session_"))
    end)

    it("sets the new session as active", function()
      -- ========= [A]rrange =========
      local session = { handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" }

      -- ========= [A]ct     =========
      local id = store.create(session)

      -- ========= [A]ssert  =========
      local active = store.get_active()
      assert.is_not_nil(active)
      assert.equals(id, active.id)
    end)

    it("stores session fields", function()
      -- ========= [A]rrange =========
      local handle = { bufnr = 1 }
      local new_session = {
        handle = handle,
        cmd = "codex",
        cwd = "/home",
        provider_name = "snacks",
      }

      -- ========= [A]ct     =========
      local id = store.create(new_session)

      -- ========= [A]ssert  =========
      local stored_session = store.get(id)
      assert.equals(handle, stored_session.handle)
      assert.equals("codex", stored_session.cmd)
      assert.equals("/home", stored_session.cwd)
      assert.equals("snacks", stored_session.provider_name)
      assert.is_true(stored_session.alive)
    end)
  end)

  describe("get", function()
    it("returns nil for unknown id", function()
      -- ========= [A]rrange =========
      local session_id = "nonexistent"

      -- ========= [A]ct     =========
      local session = store.get(session_id)

      -- ========= [A]ssert  =========
      assert.is_nil(session)
    end)
  end)

  describe("mark_dead", function()
    it("sets alive to false", function()
      -- ========= [A]rrange =========
      local id =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })

      -- ========= [A]ct     =========
      store.mark_dead(id)

      -- ========= [A]ssert  =========
      local session = store.get(id)
      assert.is_false(session.alive)
    end)

    it("clears active if it was the active session", function()
      -- ========= [A]rrange =========
      local id =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })

      -- ========= [A]ct     =========
      store.mark_dead(id)

      -- ========= [A]ssert  =========
      assert.is_nil(store.get_active())
    end)
  end)

  describe("remove", function()
    it("deletes the session", function()
      -- ========= [A]rrange =========
      local id =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })

      -- ========= [A]ct     =========
      store.remove(id)

      -- ========= [A]ssert  =========
      assert.is_nil(store.get(id))
      assert.is_nil(store.get_active())
    end)
  end)

  describe("set_active", function()
    it("changes the active session", function()
      -- ========= [A]rrange =========
      local id1 =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })

      -- ========= [A]ct     =========
      store.set_active(id1)

      -- ========= [A]ssert  =========
      assert.equals(id1, store.get_active().id)
    end)
  end)

  describe("list", function()
    it("returns empty table when no sessions", function()
      -- ========= [A]rrange =========

      -- ========= [A]ct     =========
      local sessions = store.list()

      -- ========= [A]ssert  =========
      assert.same({}, sessions)
    end)

    it("returns all sessions", function()
      -- ========= [A]rrange =========
      store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })

      -- ========= [A]ct     =========
      local sessions = store.list()

      -- ========= [A]ssert  =========
      assert.equals(2, #sessions)
    end)
  end)
end)
