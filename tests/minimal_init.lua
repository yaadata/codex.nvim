-- Minimal init for running tests with nvim --headless
local source = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fn.fnamemodify(source, ":h:h")

vim.opt.rtp:prepend(plugin_root)

local function resolve_plenary_path(root)
  local candidates = {
    vim.env.CODEX_PLENARY_PATH,
    root .. "/.deps/plenary.nvim",
    vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"),
  }

  for _, path in ipairs(candidates) do
    if path and path ~= "" and vim.fn.isdirectory(path) == 1 then
      return path
    end
  end

  return nil
end

local plenary_path = resolve_plenary_path(plugin_root)
if not plenary_path then
  error(
    "codex.nvim tests: plenary.nvim not found. Set CODEX_PLENARY_PATH or clone to .deps/plenary.nvim"
  )
end
vim.opt.rtp:prepend(plenary_path)

vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.cmd("runtime plugin/plenary.vim")
