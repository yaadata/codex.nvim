local M = {}

local sessions = {}
local active_id = nil
local counter = 0

function M.create(spec)
  counter = counter + 1
  local id = "session_" .. counter

  sessions[id] = {
    id = id,
    handle = spec.handle,
    cmd = spec.cmd,
    cwd = spec.cwd,
    provider_name = spec.provider_name,
    alive = true,
  }

  active_id = id
  return id
end

function M.get(id)
  return sessions[id]
end

function M.get_active()
  if active_id then
    return sessions[active_id]
  end
  return nil
end

function M.set_active(id)
  active_id = id
end

function M.mark_dead(id)
  if sessions[id] then
    sessions[id].alive = false
  end
  if active_id == id then
    active_id = nil
  end
end

function M.remove(id)
  sessions[id] = nil
  if active_id == id then
    active_id = nil
  end
end

function M.list()
  local result = {}
  for _, session in pairs(sessions) do
    table.insert(result, session)
  end
  return result
end

function M.reset()
  sessions = {}
  active_id = nil
  counter = 0
end

return M
