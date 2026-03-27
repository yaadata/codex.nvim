if vim.fn.has("nvim-0.11.0") ~= 1 then
  vim.notify("codex.nvim requires Neovim >= 0.11.0", vim.log.levels.ERROR)
  return
end

if vim.g.loaded_codex then
  return
end
vim.g.loaded_codex = true
