local M = {}

M.keymaps = require("codex.builtin.keymaps")

--- Sends a slash command to the agent harness. The behavior of this
--- function follows these steps:
---   - Saves in-progress inputs to the agent harness to a vim register
---   - Clears the input in the agent harness
---   - Sends the slash command
---
---```lua
---local builtin = require("codex.builtin")
---local err = builtin.execute_slash_command({
---                        command = "status",
---                     })
---if err == nil then
---   vim.notify("failed to execute slash command (error=" .. err .. ")")
---end
---```
---The above would submit the following input to the agent harness `/status`
---
---Its possible to add additional arguments to the slash command. In the example
---below we use a skill named "code-review" for illustrative purposes.
---
---
---```lua
---local builtin = require("codex.builtin")
---local err = builtin.execute_slash_command({
---                        command = "codex-review",
---                        args = "critical issues"
---                     })
---if err == nil then
---   vim.notify("failed to execute slash command (error=" .. err .. ")")
---end
---```
---The above would submit the following input to the agent harness
---
---```
---/code-review critical issues
---```
---
---@param args codex.ExecuteSlashCommandOpts
---@return codex.Error
M.execute_slash_command = function(opts)
  return require("codex.builtin.slash_command").execute(opts)
end

--- Formats an agent skill to the specification of the agent harness
--- Most agent harness use `/{skill_name}` for invoking {skill_name}.
---
--- For codex cli:
--- ```lua
---local builtin = require("codex.builtin")
---local enum = require("codex.enums.skill_style")
---local skill = builtin.format_skill({
---                 name = "review",
---              }, enum.SLASH)
--- ```
---
---
--- now skill = `$skill`
---
--- This can be passed into prompt_builder to be sent to the agent harness.
---
--- ```lua
--- local codex = require("codex")
--- codex.prompt_builder.add(skill)
--- codex.prompt_builder.send()
--- ```
---@param opts codex.AgentSkillOptions
---@param style? codex.AgentSkillStyle
---@return codex.Error error
M.format_skill = function(opts, style)
  return require("codex.builtin.skill").format(opts, style)
end

--- Sends the following to the agent terminal buffer.
---
--- `/mention path/to/file.extension`
---
--- if path is empty, the method fallbacks to `vim.fn.expand("%:p")`
---
--- This functionality is mainly exclusive to the openai codex harness
--- https://learn.chatgpt.com/docs/developer-commands?surface=cli#cli-highlight-files-with-mention
---@param path string?
---@return codex.Error
M.mention_file = function(path)
  return require("codex.builtin.mention").file(path)
end

--- Sends the following to the agent terminal buffer.
---
--- `/mention path/to/directory`
---
--- if path is empty, the method fallbacks to `vim.fn.expand("%:p:h")`
---
--- This functionality is mainly exclusive to the openai codex harness
--- https://learn.chatgpt.com/docs/developer-commands?surface=cli#cli-highlight-files-with-mention
---@param path string?
---@return codex.Error
M.mention_directory = function(path)
  return require("codex.builtin.mention").directory(path)
end

--- Resume the agent harness. The default behavior is with with the codex cli harness.
---
--- ```
--- local builtin = require('codex.builtin')
--- local err = builtin.resume()
--- ```
---
--- Specify an agent harness with CLAUDE or PI.
---
--- ```
--- local enum = require('codex.enum.harness')
--- local builtin = require('codex.builtin')
--- local err = builtin.resume({
---   harness = enum.CLAUDE,
--- })
--- ````
---
--- if you want to resume the last session:
---
---
--- ```
--- local enum = require('codex.enum.harness')
--- local builtin = require('codex.builtin')
--- local err = builtin.resume({
---    last = true,
--- })
--- ````
---@param opts? codex.ResumeOpts
---@return codex.Error
M.resume = function(opts)
  return require("codex.builtin.resume").resume(opts)
end

return M
