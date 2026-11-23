---@return codex.SessionStore
local function new()
  ---@class codex.SessionStore
  local M = {}

  ---@type table<string, codex.SessionState>
  local sessions = {}
  ---@type table<string, string>
  local active_by_profile = {}
  local counter = 0

  ---@param session codex.SessionState|nil
  ---@return nil
  local function clear_active(session)
    if session and active_by_profile[session.profile_identifier] == session.id then
      active_by_profile[session.profile_identifier] = nil
    end
  end

  --- Create a new session from the given spec, store it, and set it as active for its profile.
  ---@param spec codex.SessionSpec
  ---@return string id
  function M.create(spec)
    counter = counter + 1
    local id = "session_" .. counter
    local profile_identifier = spec.profile_identifier or "default"

    sessions[id] = {
      id = id,
      handle = spec.handle,
      cmd = spec.cmd,
      cwd = spec.cwd,
      provider_name = spec.provider_name,
      profile_identifier = profile_identifier,
      config = spec.config,
      alive = true,
    }

    active_by_profile[profile_identifier] = id
    return id
  end

  --- Look up a session by its id.
  ---@param id string
  ---@return codex.SessionState|nil
  function M.get(id)
    return sessions[id]
  end

  --- Return the currently active session for `profile_identifier` (defaults to "default"), or nil.
  ---@param profile_identifier? string
  ---@return codex.SessionState|nil
  function M.get_active(profile_identifier)
    local id = active_by_profile[profile_identifier or "default"]
    return id and sessions[id] or nil
  end

  --- Set the active session id for a profile; pass nil to clear that profile's active session.
  ---@param id string|nil
  ---@param profile_identifier? string
  ---@return nil
  function M.set_active(id, profile_identifier)
    if id == nil then
      active_by_profile[profile_identifier or "default"] = nil
      return
    end
    local session = sessions[id]
    local target_profile = profile_identifier
      or (session and session.profile_identifier)
      or "default"
    active_by_profile[target_profile] = id
  end

  --- Mark a session as no longer alive and clear it from active if it was active.
  ---@param id string
  ---@return nil
  function M.mark_dead(id)
    local session = sessions[id]
    if session then
      session.alive = false
      clear_active(session)
    end
  end

  --- Remove a session from the store entirely and clear it from active if needed.
  ---@param id string
  ---@return nil
  function M.remove(id)
    local session = sessions[id]
    clear_active(session)
    sessions[id] = nil
  end

  --- Return a list of all stored sessions.
  ---@return codex.SessionState[]
  function M.list()
    ---@type codex.SessionState[]
    local result = {}
    for _, session in pairs(sessions) do
      table.insert(result, session)
    end
    return result
  end

  --- Clear all sessions, active mappings, and reset the id counter.
  ---@return nil
  function M.reset()
    sessions = {}
    active_by_profile = {}
    counter = 0
  end

  return M
end

local M = new()
M.new = new
return M
