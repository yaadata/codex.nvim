---@param overrides table|nil
---@return codex.ProfileConfig
local function make_profile(overrides)
  local base = {
    profile_identifier = "default",
    profile_name = "default",
    terminal = {
      provider = "native",
      provider_opts = {
        native = {
          window = "vsplit",
          vsplit = { side = "right", size_pct = 25 },
          hsplit = { side = "bottom", size_pct = 35 },
          float = { width_pct = 60, height_pct = 50, border = "rounded" },
        },
      },
    },
  }
  return vim.tbl_deep_extend("force", base, overrides or {})
end

---@param marker table|nil
---@return integer bufnr
local function make_terminal_buffer(marker)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_var(bufnr, "codex_terminal", marker or {
    provider = "native",
    cmd = "codex",
    cwd = vim.fn.getcwd(),
    profile_identifier = "default",
  })
  return bufnr
end

---@param total integer
---@param pct integer
---@return integer
local function expected_size(total, pct)
  return math.max(1, math.floor(total * pct / 100))
end

---@param bufnr integer
---@param width integer
---@return integer winid
local function show_in_vsplit(bufnr, width)
  vim.cmd("vsplit")
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.api.nvim_win_set_width(winid, width)
  return winid
end

---@param bufnr integer
---@param height integer
---@return integer winid
local function show_in_hsplit(bufnr, height)
  vim.cmd("split")
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.api.nvim_win_set_height(winid, height)
  return winid
end

describe("codex.session.is_visible", function()
  local codex

  before_each(function()
    package.loaded["codex"] = nil
    codex = require("codex")
    codex.setup({
      profiles = {
        default = {
          auto_start = false,
          terminal = { provider = "native", provider_opts = { native = { window = "vsplit" } } },
        },
      },
    })
  end)

  after_each(function()
    codex.deactivate()
    package.loaded["codex"] = nil
    vim.cmd("silent! only")
    vim.cmd("silent! tabonly")
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local ok, marker = pcall(vim.api.nvim_buf_get_var, bufnr, "codex_terminal")
      if ok and marker and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  it("is true once the terminal is displayed in a window", function()
    -- ========= [A]rrange =========
    local bufnr = make_terminal_buffer()
    assert.is_false(codex.session.is_visible())

    -- ========= [A]ct     =========
    show_in_vsplit(bufnr, 12)

    -- ========= [A]ssert  =========
    assert.is_true(codex.session.is_visible())
  end)

  it("is false when the terminal has no window", function()
    -- ========= [A]rrange =========
    make_terminal_buffer() -- never shown

    -- ========= [A]ct     =========
    local visible = codex.session.is_visible()

    -- ========= [A]ssert  =========
    assert.is_false(visible)
  end)

  it("is false when the terminal is only shown in another tabpage", function()
    -- ========= [A]rrange =========
    local bufnr = make_terminal_buffer()
    vim.cmd("tabnew")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.cmd("tabprevious")

    -- ========= [A]ct     =========
    local visible = codex.session.is_visible()

    -- ========= [A]ssert  =========
    assert.is_false(visible)
  end)

  it("is true on the tabpage that displays the terminal", function()
    -- ========= [A]rrange =========
    local bufnr = make_terminal_buffer()
    vim.cmd("tabnew")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)

    -- ========= [A]ct     =========
    local visible = codex.session.is_visible()

    -- ========= [A]ssert  =========
    assert.is_true(visible)
  end)

  it("stays true after the terminal process exited", function()
    -- ========= [A]rrange =========
    local bufnr = make_terminal_buffer({
      provider = "native",
      profile_identifier = "default",
      exited = true,
    })
    show_in_vsplit(bufnr, 12)
    assert.is_false(codex.session.is_running())

    -- ========= [A]ct     =========
    local visible = codex.session.is_visible()

    -- ========= [A]ssert  =========
    assert.is_true(visible)
  end)

  it("ignores a terminal belonging to a different profile", function()
    -- ========= [A]rrange =========
    show_in_vsplit(make_terminal_buffer({ provider = "native", profile_identifier = "work" }), 12)

    -- ========= [A]ct     =========
    local visible = codex.session.is_visible()

    -- ========= [A]ssert  =========
    assert.is_false(visible)
  end)

  it("is false when the plugin is not set up", function()
    -- ========= [A]rrange =========
    show_in_vsplit(make_terminal_buffer(), 12)
    codex.deactivate()
    package.loaded["codex"] = nil
    codex = require("codex")

    -- ========= [A]ct     =========
    local visible = codex.session.is_visible()

    -- ========= [A]ssert  =========
    assert.is_false(visible)
  end)
end)

describe("codex.session.resize", function()
  local codex

  before_each(function()
    package.loaded["codex"] = nil
    codex = require("codex")
    codex.setup({
      profiles = {
        default = {
          auto_start = false,
          terminal = {
            provider = "native",
            provider_opts = {
              native = {
                window = "vsplit",
                vsplit = { side = "right", size_pct = 25 },
                hsplit = { side = "bottom", size_pct = 35 },
                float = { width_pct = 60, height_pct = 50, border = "rounded" },
              },
            },
          },
        },
      },
    })
  end)

  after_each(function()
    codex.deactivate()
    package.loaded["codex"] = nil
    vim.cmd("silent! only")
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local ok, marker = pcall(vim.api.nvim_buf_get_var, bufnr, "codex_terminal")
      if ok and marker and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  it("restores a vertical split to the configured size_pct", function()
    -- ========= [A]rrange =========
    local winid = show_in_vsplit(make_terminal_buffer(), 12)
    assert.are_not.equal(expected_size(vim.o.columns, 25), 12)

    -- ========= [A]ct     =========
    codex.session.resize()

    -- ========= [A]ssert  =========
    assert.equal(expected_size(vim.o.columns, 25), vim.api.nvim_win_get_width(winid))
  end)

  it("restores a horizontal split to the configured size_pct", function()
    -- ========= [A]rrange =========
    local winid = show_in_hsplit(make_terminal_buffer(), 3)

    -- ========= [A]ct     =========
    codex.session.resize()

    -- ========= [A]ssert  =========
    assert.equal(expected_size(vim.o.lines, 35), vim.api.nvim_win_get_height(winid))
  end)

  it("uses an explicitly passed profile instead of the active one", function()
    -- ========= [A]rrange =========
    local winid = show_in_vsplit(make_terminal_buffer(), 12)

    -- ========= [A]ct     =========
    codex.session.resize(make_profile({
      terminal = { provider_opts = { native = { vsplit = { size_pct = 45 } } } },
    }))

    -- ========= [A]ssert  =========
    assert.equal(expected_size(vim.o.columns, 45), vim.api.nvim_win_get_width(winid))
  end)

  it("restores a float to the configured size and re-centers it", function()
    -- ========= [A]rrange =========
    local winid = vim.api.nvim_open_win(make_terminal_buffer(), true, {
      relative = "editor",
      width = 10,
      height = 5,
      row = 0,
      col = 0,
      style = "minimal",
    })

    -- ========= [A]ct     =========
    codex.session.resize()

    -- ========= [A]ssert  =========
    local config = vim.api.nvim_win_get_config(winid)
    local width = expected_size(vim.o.columns, 60)
    local height = expected_size(vim.o.lines, 50)
    assert.equal(width, config.width)
    assert.equal(height, config.height)
    assert.equal(math.floor((vim.o.lines - height) / 2), config.row)
    assert.equal(math.floor((vim.o.columns - width) / 2), config.col)
  end)

  it("keeps a float's border and title", function()
    -- ========= [A]rrange =========
    local winid = vim.api.nvim_open_win(make_terminal_buffer(), true, {
      relative = "editor",
      width = 10,
      height = 5,
      row = 0,
      col = 0,
      style = "minimal",
      border = "single",
      title = "codex",
      title_pos = "left",
    })

    -- ========= [A]ct     =========
    codex.session.resize()

    -- ========= [A]ssert  =========
    local config = vim.api.nvim_win_get_config(winid)
    assert.is_false(config.external)
    assert.equal("left", config.title_pos)
    assert.equal("codex", config.title[1][1])
  end)

  it("leaves a snacks float to its provider", function()
    -- ========= [A]rrange =========
    local winid = vim.api.nvim_open_win(
      make_terminal_buffer({ provider = "snacks", profile_identifier = "default" }),
      true,
      { relative = "editor", width = 10, height = 5, row = 0, col = 0, style = "minimal" }
    )

    -- ========= [A]ct     =========
    codex.session.resize()

    -- ========= [A]ssert  =========
    local config = vim.api.nvim_win_get_config(winid)
    assert.equal(10, config.width)
    assert.equal(5, config.height)
  end)

  it("still resizes a terminal shown only in another tabpage", function()
    -- ========= [A]rrange =========
    local bufnr = make_terminal_buffer()
    vim.cmd("tabnew")
    local winid = show_in_vsplit(bufnr, 12) -- a real split, not a lone leaf window
    vim.cmd("tabprevious")

    -- ========= [A]ct     =========
    codex.session.resize(make_profile())

    -- ========= [A]ssert  =========
    assert.equal(expected_size(vim.o.columns, 25), vim.api.nvim_win_get_width(winid))
  end)

  it("does nothing when the profile terminal is not visible", function()
    -- ========= [A]rrange =========
    make_terminal_buffer() -- created but never shown in a window
    vim.cmd("vsplit") -- a second window so a bogus resize would be visible
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(winid, 17)

    -- ========= [A]ct     =========
    codex.session.resize()

    -- ========= [A]ssert  =========
    assert.equal(17, vim.api.nvim_win_get_width(winid))
  end)

  it("ignores a terminal belonging to a different profile", function()
    -- ========= [A]rrange =========
    local bufnr = make_terminal_buffer({ provider = "native", profile_identifier = "work" })
    local winid = show_in_vsplit(bufnr, 12)

    -- ========= [A]ct     =========
    codex.session.resize()

    -- ========= [A]ssert  =========
    assert.equal(12, vim.api.nvim_win_get_width(winid))
  end)

  it("matches a marker without a profile_identifier as the default profile", function()
    -- ========= [A]rrange =========
    local winid = show_in_vsplit(make_terminal_buffer({ provider = "native" }), 12)

    -- ========= [A]ct     =========
    codex.session.resize()

    -- ========= [A]ssert  =========
    assert.equal(expected_size(vim.o.columns, 25), vim.api.nvim_win_get_width(winid))
  end)

  it("is a no-op when the plugin is not set up", function()
    -- ========= [A]rrange =========
    local winid = show_in_vsplit(make_terminal_buffer(), 12)
    codex.deactivate()
    package.loaded["codex"] = nil
    codex = require("codex")

    -- ========= [A]ct     =========
    codex.session.resize()

    -- ========= [A]ssert  =========
    assert.equal(12, vim.api.nvim_win_get_width(winid))
  end)
end)
