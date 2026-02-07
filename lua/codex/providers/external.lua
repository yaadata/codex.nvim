local M = {}

function M.is_available()
  return false
end

local function not_implemented()
  return false, "external provider is not yet implemented"
end

function M.open()
  return nil, "external provider is not yet implemented"
end

M.close = not_implemented
M.send = not_implemented
M.focus = not_implemented

function M.toggle()
  return nil, "external provider is not yet implemented"
end

function M.is_alive()
  return false
end

function M.get_bufnr()
  return nil
end

return M
