---@meta

---@alias codex.ProviderName
---| "auto"
---| "native"
---| "snacks"

---@alias codex.LogLevel
---| "debug"
---| "info"
---| "warn"
---| "error"

---@class codex.LogConfig
---@field level codex.LogLevel
---@field verbose boolean

---@class codex.LogEntry
---@field seq integer
---@field timestamp integer
---@field level codex.LogLevel
---@field message string
---@field verbose boolean

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

---@class codex.StartupConfig
---@field timeout_ms number
---@field retry_interval_ms number
---@field grace_ms number

---@class codex.TerminalKeymapBinding
---@field mode string|string[]
---@field action fun()
---@field desc? string

---@alias codex.TerminalKeymapConfig table<string, codex.TerminalKeymapBinding>

---@class codex.TerminalConfig
---@field provider codex.ProviderName
---@field auto_close boolean
---@field startup codex.StartupConfig
---@field keymaps codex.TerminalKeymapConfig
---@field provider_opts codex.ProviderOptsConfig

---@class codex.NativeProviderOpts
---@field window codex.WindowType
---@field vsplit codex.VsplitConfig
---@field hsplit codex.HsplitConfig
---@field float codex.FloatConfig

---@class codex.ProviderOptsConfig
---@field native codex.NativeProviderOpts
---@diagnostic disable-next-line: undefined-doc-name
---@field snacks snacks.terminal.Opts|table<string, any>

---@class codex.LaunchConfig
---@field cmd string
---@field args string[]
---@field env table<string, string>
---@field auto_start boolean
---@field cwd string|nil

---@class codex.Config
---@field launch codex.LaunchConfig
---@field terminal codex.TerminalConfig
---@field log codex.LogConfig

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

---@class codex.MentionCommandOpts
---@field post_execute? fun(ok: boolean, err: string|nil)

---@class codex.SendBufferOpts
---@field bufnr? integer
---@field path? string
---@field focus? boolean

---@class codex.UserCommandOpts
---@field bang boolean
---@field line1 integer
---@field line2 integer
---@field range integer
---@field args string

return {}
