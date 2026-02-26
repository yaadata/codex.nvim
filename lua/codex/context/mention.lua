local terminal_io = require("codex.runtime.terminal_io")
local session_lifecycle = require("codex.state.session_lifecycle")
local prompt_submit = require("codex.context.prompt_submit")

---@class codex.MentionOpts
---@field get_deps fun(): table
---@field get_config fun(): table
---@field dispatch_send fun(text: string, opts?: codex.DispatchSendOpts): codex.SendResult, string|nil

local M = {}

---Creates a mention orchestration instance with the given accessors.
---@param opts codex.MentionOpts
---@return { mention_file: fun(path?: string): codex.SendResult, string|nil, mention_directory: fun(path?: string): codex.SendResult, string|nil, dispatch: fun(resolved_path: string): codex.SendResult, string|nil }
function M.create(opts)
  local get_deps = opts.get_deps
  local get_config = opts.get_config
  local dispatch_send = opts.dispatch_send

  ---Sends `/mention` for an already-resolved relative path, auto-submits, and restores prompt input.
  ---@param resolved_path string Relative path to mention.
  ---@return codex.SendResult ok True when mention payload is sent.
  ---@return string|nil err
  local function dispatch_mention(resolved_path)
    local deps = get_deps()
    local config = get_config()
    local mention = deps.formatter.format_mention(resolved_path)

    local session, provider = session_lifecycle.get_active_session_and_provider(deps, config)
    if session_lifecycle.session_is_alive(session, provider) then
      -- Capture depends on terminal buffer/window state; focus first to ensure buffer visibility.
      provider.focus(session.handle)
    end

    local existing_input = prompt_submit.capture_prompt_input(get_deps, get_config)
    local mention_payload = terminal_io.encode_clear_line_for_mention(deps) .. mention
    return dispatch_send(mention_payload, {
      open_focus = true,
      pre_focus = true,
      command_path = "/mention",
      on_sent = function()
        deps.vim.defer_fn(function()
          local submit_ok, submit_err =
            prompt_submit.submit_with_enter_key(get_deps, get_config, "/mention")
          if not submit_ok then
            deps.logger.error("failed to submit /mention: %s", submit_err)
            return
          end

          if not existing_input or existing_input == "" then
            return
          end

          deps.vim.defer_fn(function()
            local restore_ok, restore_err = dispatch_send(existing_input, {
              open_focus = true,
              post_focus = true,
            })
            if not restore_ok then
              deps.logger.error("failed to restore terminal input after /mention: %s", restore_err)
            end
          end, terminal_io.RESTORE_INPUT_DELAY_MS)
        end, terminal_io.SUBMIT_INPUT_DELAY_MS)
      end,
    })
  end

  ---Sends `/mention` for a file, auto-submits it, then restores previously captured prompt input.
  ---@param path? string Explicit file path to mention. When nil, uses current buffer path.
  ---@return codex.SendResult ok True when mention payload is sent.
  ---@return string|nil err
  local function mention_file(path)
    local deps = get_deps()
    local resolved_path = path
    if resolved_path == nil then
      resolved_path = deps.vim.fn.expand("%:p")
    end

    if not resolved_path or resolved_path == "" then
      local err = "current buffer has no file path"
      deps.logger.error("failed to mention file: %s", err)
      return false, err
    end

    resolved_path = deps.path.to_relative(deps.vim, resolved_path)
    return dispatch_mention(resolved_path)
  end

  ---Sends `/mention` for a directory, auto-submits it, then restores previously captured prompt input.
  ---@param path? string Explicit directory path to mention. When nil, uses current buffer's directory.
  ---@return codex.SendResult ok True when mention payload is sent.
  ---@return string|nil err
  local function mention_directory(path)
    local deps = get_deps()
    local resolved_path = path
    if resolved_path == nil then
      local buf_path = deps.vim.fn.expand("%:p")
      if not buf_path or buf_path == "" then
        local err = "current buffer has no directory path"
        deps.logger.error("failed to mention directory: %s", err)
        return false, err
      end
      resolved_path = deps.vim.fn.expand("%:p:h")
    end

    if not resolved_path or resolved_path == "" then
      local err = "current buffer has no directory path"
      deps.logger.error("failed to mention directory: %s", err)
      return false, err
    end

    resolved_path = deps.path.to_relative(deps.vim, resolved_path)
    resolved_path = deps.path.ensure_dir_trailing_separator(deps.vim, resolved_path)
    return dispatch_mention(resolved_path)
  end

  return {
    mention_file = mention_file,
    mention_directory = mention_directory,
    dispatch = dispatch_mention,
  }
end

return M
