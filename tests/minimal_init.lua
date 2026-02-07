-- Minimal init for running tests with nvim --headless
local source = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fn.fnamemodify(source, ":h:h")

vim.opt.rtp:prepend(plugin_root)

-- Add plenary so test harness is available
local plenary_path = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:prepend(plenary_path)
end

vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.cmd("runtime plugin/plenary.vim")
