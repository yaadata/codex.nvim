local store = require("codex.state.session_store")

describe("codex.state.session_store", function()
  before_each(function()
    store.reset()
  end)

  describe("create", function()
    it("returns an id", function()
      local id =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      assert.is_string(id)
      assert.truthy(id:match("^session_"))
    end)

    it("sets the new session as active", function()
      local id =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      local active = store.get_active()
      assert.is_not_nil(active)
      assert.equals(id, active.id)
    end)

    it("stores session fields", function()
      local handle = { bufnr = 1 }
      local id =
        store.create({ handle = handle, cmd = "codex", cwd = "/home", provider_name = "snacks" })
      local session = store.get(id)
      assert.equals(handle, session.handle)
      assert.equals("codex", session.cmd)
      assert.equals("/home", session.cwd)
      assert.equals("snacks", session.provider_name)
      assert.is_true(session.alive)
    end)
  end)

  describe("get", function()
    it("returns nil for unknown id", function()
      assert.is_nil(store.get("nonexistent"))
    end)
  end)

  describe("mark_dead", function()
    it("sets alive to false", function()
      local id =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      store.mark_dead(id)
      local session = store.get(id)
      assert.is_false(session.alive)
    end)

    it("clears active if it was the active session", function()
      local id =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      store.mark_dead(id)
      assert.is_nil(store.get_active())
    end)
  end)

  describe("remove", function()
    it("deletes the session", function()
      local id =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      store.remove(id)
      assert.is_nil(store.get(id))
      assert.is_nil(store.get_active())
    end)
  end)

  describe("set_active", function()
    it("changes the active session", function()
      local id1 =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      local id2 =
        store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      assert.equals(id2, store.get_active().id)
      store.set_active(id1)
      assert.equals(id1, store.get_active().id)
    end)
  end)

  describe("list", function()
    it("returns empty table when no sessions", function()
      assert.same({}, store.list())
    end)

    it("returns all sessions", function()
      store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      store.create({ handle = {}, cmd = "codex", cwd = "/tmp", provider_name = "native" })
      assert.equals(2, #store.list())
    end)
  end)
end)
