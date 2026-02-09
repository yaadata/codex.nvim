---@meta

---@alias codex.ProviderName
---| "auto"
---| "native"
---| "snacks"
---| "external"
---| "none"

---@alias codex.LogLevel
---| "debug"
---| "info"
---| "warn"
---| "error"

---@class codex.TerminalConfig
---@field provider codex.ProviderName
---@field split_side "left"|"right"
---@field split_width_pct number
---@field auto_close boolean
---@field provider_opts table<string, table>

---@class codex.Config
---@field cmd string
---@field args string[]
---@field env table<string, string>
---@field auto_start boolean
---@field terminal codex.TerminalConfig
---@field cwd string|nil
---@field log_level codex.LogLevel

---@class codex.SessionSpec
---@field handle codex.ProviderHandle
---@field cmd string
---@field cwd string
---@field provider_name string

---@class codex.Session: codex.SessionSpec
---@field id string
---@field alive boolean

---@alias codex.ProviderHandle table

---@class codex.Provider
---@field is_available fun(): boolean
---@field open fun(cmd: string, args: string[], env: table<string, string>, config: codex.Config, focus: boolean, on_exit?: fun(handle: codex.ProviderHandle): nil): codex.ProviderHandle|nil, string|nil
---@field close fun(handle: codex.ProviderHandle|nil): boolean, string|nil
---@field send fun(handle: codex.ProviderHandle|nil, text: string): boolean, string|nil
---@field focus fun(handle: codex.ProviderHandle|nil): boolean, string|nil
---@field toggle fun(handle: codex.ProviderHandle|nil, cmd: string, args: string[], env: table<string, string>, config: codex.Config): codex.ProviderHandle|nil, string|nil
---@field is_alive fun(handle: codex.ProviderHandle|nil): boolean
---@field get_bufnr fun(handle: codex.ProviderHandle|nil): integer|nil

---@class codex.UserCommandOpts
---@field bang boolean
---@field line1 integer
---@field line2 integer
---@field args string

return {}
