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

---@alias codex.WindowType
---| "vsplit"
---| "hsplit"
---| "float"

---@class codex.VsplitConfig
---@field side "left"|"right"
---@field size_pct number

---@class codex.HsplitConfig
---@field side "top"|"bottom"
---@field size_pct number

---@class codex.FloatConfig
---@field width_pct number
---@field height_pct number
---@field border string
---@field title string
---@field title_pos "left"|"center"|"right"

---@class codex.NavKeymapConfig
---@field left string|false
---@field down string|false
---@field up string|false
---@field right string|false

---@class codex.TerminalKeymapConfig
---@field toggle string|false
---@field close string|false
---@field nav codex.NavKeymapConfig|false

---@class codex.KeymapConfig
---@field toggle string|false
---@field open string|false
---@field focus string|false
---@field close string|false
---@field send string|false
---@field add string|false
---@field resume string|false
---@field model string|false
---@field status string|false
---@field permissions string|false
---@field compact string|false
---@field review string|false
---@field diff string|false

---@class codex.TerminalConfig
---@field provider codex.ProviderName
---@field window codex.WindowType
---@field vsplit codex.VsplitConfig
---@field hsplit codex.HsplitConfig
---@field float codex.FloatConfig
---@field auto_close boolean
---@field startup_timeout_ms number
---@field startup_retry_interval_ms number
---@field startup_grace_ms number
---@field keymaps codex.TerminalKeymapConfig
---@field provider_opts table<string, table>

---@class codex.Config
---@field cmd string
---@field args string[]
---@field env table<string, string>
---@field auto_start boolean
---@field terminal codex.TerminalConfig
---@field cwd string|nil
---@field log_level codex.LogLevel
---@field keymaps codex.KeymapConfig|false
---@field keymaps_force boolean

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
---@field is_ready fun(handle: codex.ProviderHandle|nil): boolean
---@field get_bufnr fun(handle: codex.ProviderHandle|nil): integer|nil

---@class codex.UserCommandOpts
---@field bang boolean
---@field line1 integer
---@field line2 integer
---@field range integer
---@field args string

return {}
