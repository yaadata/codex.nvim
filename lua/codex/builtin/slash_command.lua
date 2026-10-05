local M = {}

local terminal_io = require("codex.runtime.terminal_io")

---@param command_opts codex.ExecuteSlashCommandOpts
---@return string? command_text
---@return codex.Error err
local function normalize_command(command_opts)
  if type(command_opts) ~= "table" then
    return nil, "execute_slash_command requires an opts table"
  end

  if type(command_opts.command) ~= "string" then
    return nil, "execute_slash_command requires opts.command"
  end

  local command_name = vim.trim(command_opts.command:gsub("^/+", ""))
  if command_name == "" then
    return nil, "execute_slash_command requires a non-empty opts.command"
  end

  local args = command_opts.args
  if args == nil then
    return command_name, nil
  end

  if type(args) ~= "string" then
    return nil, "execute_slash_command expects opts.args to be a string"
  end

  local trimmed_args = vim.trim(args)
  if trimmed_args == "" then
    return command_name, nil
  end

  return command_name .. " " .. trimmed_args, nil
end

---@param opts codex.ExecuteSlashCommandOpts
---@return codex.Error
function M.execute(opts)
  local command, normalize_err = normalize_command(opts)
  if normalize_err ~= nil then
    return normalize_err
  end
  ---@type codex.Api
  local codex = require("codex")
  local capture_ok, current_input = codex.input.get()
  if not capture_ok then
    return "failed to capture current input"
  end
  current_input = current_input or ""
  if current_input ~= "" then
    vim.fn.setreg("e", current_input)
  end
  ---@return codex.Error
  local function fallback(cause)
    -- fallback
    return "failed to construct command. input saved to vim register. error=" .. cause
  end

  local current_buffer = codex.prompt_builder.peak()
  local clear_ok, clear_err = codex.input.clear()
  if not clear_ok then
    return fallback(clear_err)
  end
  codex.prompt_builder.clear()

  local added, add_err = codex.prompt_builder.add("/" .. command)
  if not added then
    return fallback(add_err)
  end
  ---@type integer
  local delay = terminal_io.get_submit_input_delay_ms()
  vim.defer_fn(function()
    local sent, send_err = codex.prompt_builder.send()
    if not sent then
      codex.prompt_builder.join(current_buffer)
      vim.notify(fallback(send_err), vim.log.levels.ERROR)
      return
    end
    if current_input == "" then
      codex.prompt_builder.join(current_buffer)
    else
      vim.defer_fn(function()
        codex.prompt_builder.add(current_input)
        local restore_sent, restore_err = codex.prompt_builder.send()
        if not restore_sent then
          vim.notify(fallback(restore_err), vim.log.levels.ERROR)
        end
        codex.prompt_builder.join(current_buffer)
      end, delay)
    end
  end, delay)

  return add_err
end

return M
