local M = {}

function M.is_available()
  return true
end

function M.open()
  return {}
end

function M.close()
  return true
end

function M.send()
  return true
end

function M.focus()
  return true
end

function M.toggle()
  return {}
end

function M.is_alive()
  return false
end

function M.get_bufnr()
  return nil
end

return M
