--[[
usage:
  just test-one tests/unit/init_send_selection_spec.lua "add_selection buffers message and sends the visual payload"
]]

local file = vim.env.CODEX_TEST_FILE
local filter = vim.env.CODEX_TEST_FILTER

if not file or file == "" then
  error("environment variable CODEX_TEST_FILE is required")
end

if not filter or filter == "" then
  error("environment variable CODEX_TEST_FILTER is required")
end

-- start matching
-- Plenary registers tests through the global it function.
-- selene: allow(global_usage)
local original_it = _G.it
local matches = 0

-- selene: allow(global_usage)
_G.it = function(name, fn)
  if name:find(filter, 1, true) then
    matches = matches + 1
    return original_it(name, fn)
  end
end

local ok, err = pcall(dofile, file)

-- selene: allow(global_usage)
_G.it = original_it

if not ok then
  error(err, 0)
end

if matches == 0 then
  error(("no tests matched %q in %s"):format(filter, file))
end
