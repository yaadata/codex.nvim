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

---@class codex.HookContext
---@field event string
---@field config codex.Config
---@field provider? string
---@field bufnr? integer
---@field winid? integer
---@field cmd? string
---@field cwd? string

---@alias codex.LifecycleHook fun(ctx: codex.HookContext)

---@class codex.HooksConfig
---@field on_setup? codex.LifecycleHook
---@field on_terminal_open? codex.LifecycleHook
---@field on_terminal_restore? codex.LifecycleHook
---@field on_terminal_close? codex.LifecycleHook

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
---@field hooks codex.HooksConfig

---@class codex.SessionSpec
---@field handle codex.ProviderHandle
---@field cmd string
---@field cwd string
---@field provider_name string

---@class codex.Session: codex.SessionSpec
---@field id string
---@field alive boolean

---@class codex.ResumeOpts
---@field harness? codex.AgentHarness
---@field last? boolean Use `codex resume --last` only when launching a new process.

---@alias codex.ProviderHandle table

---@class codex.RestoredSessionSpec
---@field handle codex.ProviderHandle
---@field cmd string
---@field cwd string
---@field bufnr integer
---@field winid? integer

---@class codex.Provider
---@field is_available fun(): boolean
---@field open fun(cmd: string, args: string[], env: table<string, string>, config: codex.Config, focus: boolean, on_exit?: fun(handle: codex.ProviderHandle): nil): codex.ProviderHandle|nil, codex.Error
---@field discover_restorable fun(config: codex.Config): codex.RestoredSessionSpec[]
---@field attach_restored fun(handle: codex.ProviderHandle, config: codex.Config, on_exit?: fun(handle: codex.ProviderHandle): nil): codex.Outcome, codex.Error
---@field close fun(handle: codex.ProviderHandle|nil): boolean, codex.Error
---@field send fun(handle: codex.ProviderHandle|nil, text: string): codex.Outcome, codex.Error
---@field focus fun(handle: codex.ProviderHandle|nil): boolean, codex.Error
---@field toggle fun(handle: codex.ProviderHandle|nil, cmd: string, args: string[], env: table<string, string>, config: codex.Config): codex.ProviderHandle|nil, string|nil
---@field is_alive fun(handle: codex.ProviderHandle|nil): boolean
---@field is_ready fun(handle: codex.ProviderHandle|nil): boolean
---@field get_bufnr fun(handle: codex.ProviderHandle|nil): integer|nil

-- Sending skills

---@class codex.AgentSkillCreateOptions
---@field dispatch_send fun(text: string, opts?: codex.DispatchSendOpts): codex.Outcome, codex.Error

---@class codex.AgentSkill
---@field send fun(opts?: codex.AgentSkillOptions): codex.Outcome, codex.Error
---@field prompt_payload fun(opts?: codex.AgentSkillOptions): string, codex.Error

-- Commands

---@class codex.Commands
---@field register fun(codex: codex.Api)
---@field unregister fun()

---@class codex.WrapperCommandCreateOpts
---@field get_deps fun(): table
---@field get_config fun(): table
---@field dispatch_send fun(text: string, opts: codex.DispatchSendOpts): codex.Outcome, string|nil

---@class codex.ExecuteSlashCommandOpts
---@field command string
---@field args? string

---@class codex.UserCommandOpts
---@field bang boolean
---@field line1 integer
---@field line2 integer
---@field range integer
---@field args string

---@class codex.AddFileOpts
---@field bufnr? integer
---@field path? string

---@class codex.PromptBuffer
---@field add fun(self, fragment: string)
---@field is_empty fun(self): boolean
---@field join fun(self, fragment: codex.PromptBufferArray)
---@field peak fun(): codex.PromptBufferArray
---@field reset fun(self)
---@field take fun(self): string, table

---@class codex.PromptBuilder
---@field add fun(text: string): codex.Outcome, codex.Error
---@field add_file fun(opts?: codex.AddFileOpts): codex.Outcome, codex.Error
---@field add_selection fun(opts?: codex.SelectionOpts): codex.Outcome, codex.Error
---@field clear fun(): codex.Outcome, codex.Error
---@field join fun(arr: codex.PromptBufferArray)
---@field peak fun(): codex.PromptBufferArray
---@field submit fun(): codex.Outcome, codex.Error
---@field send fun(): codex.Outcome, codex.Error

---@class codex.Input
---@field get fun(): codex.Outcome, string?
---@field clear fun(): codex.Outcome, string?
---@field copy fun(): codex.Outcome, string?
---@field feedkey fun(key: string): codex.Outcome, codex.Error

---@class codex.Logs
---@field get fun(): codex.LogEntry[]
---@field clear fun()

---@class codex.Session
---@field open fun(focus?: boolean, args?: string[])
---@field resume fun(opts?: codex.ResumeOpts): codex.Outcome, string?
---@field close fun()
---@field toggle fun()
---@field focus fun()
---@field unfocus fun(): boolean, string?
---@field is_running fun(): boolean
---@field is_focused fun(): boolean

---@class codex.Api
---@field setup fun(opts?: codex.Config)
---@field deactivate fun()
---@field get_config fun(): codex.Config?
---@field logs codex.Logs
---@field input codex.Input
---@field prompt_builder codex.PromptBuilder
---@field session codex.Session

-- Mention

---@class codex.MentionOpts
---@field get_deps fun(): table
---@field get_config fun(): table
---@field dispatch_send fun(text: string, opts?: codex.DispatchSendOpts): codex.Outcome, string|nil

---@class codex.Mention
---@field mention_file fun(path?: string): codex.Outcome, codex.Error
---@field mention_directory fun(path?: string): codex.Outcome, codex.Error

-- Selection

---@class codex.SelectionAddCreateOpts
---@field get_deps fun(): table
---@field get_prompt_buffer fun(): codex.PromptBuffer

---@class codex.SelectionAdd
---@field buffer fun(opts?: codex.SelectionOpts): codex.Outcome, string|nil
---@field log_collection_failure fun(subject: "selection"|"buffer", err: string|nil): nil

---@class codex.SelectionOpts
---@field line1? integer
---@field line2? integer
---@field start_col? integer
---@field end_col? integer
---@field bufnr? integer
---@field visual_mode? string

---@class codex.BufferPathOpts
---@field bufnr? integer
---@field path? string

---@class codex.Selection
---@field errors { BUFFER_NOT_FOUND: string, NO_FILEPATH: string, INVALID_FILEPATH: string, NO_SELECTION: string }
---@field get_current_buffer_filepath fun(vim_api?: table, opts?: codex.BufferPathOpts): string?, string?
---@field get_visual_selection fun(vim_api?: table, opts?: codex.SelectionOpts): codex.SelectionSpec?, string?

-- Formatter

---@class codex.Formatter
---@field format_selection fun(spec?: codex.SelectionSpec): string
---@field format_buffer_ref fun(filepath: string): string
---@field format_mention fun(filepath?: string): string

-- Queue

---@class codex.SendQueueOpts
---@field vim table
---@field retry_interval_ms integer
---@field process fun(item: table): codex.SendResult, codex.Error

---@class codex.SendQueue
---@field _vim table
---@field _retry_interval_ms integer
---@field _process fun(item: table): codex.SendResult, codex.Error
---@field _items table[]
---@field _flush_scheduled boolean
---@field _flush_active boolean

-- Send dispatch

---@class codex.SendDispatch
---@field dispatch_send fun(text: string, opts?: codex.DispatchSendOpts): codex.Outcome, codex.Error
---@field process_pending_send_item fun(item: codex.PendingSend): codex.SendResult, codex.Error

---@class codex.PendingSend
---@field text string
---@field open_focus boolean
---@field pre_focus boolean
---@field post_focus boolean
---@field command_path string|nil
---@field on_sent fun()|nil
---@field created_at integer
---@field opened_in_dispatch boolean
---@field reopen_attempted boolean
---@field has_attempted boolean

---@class codex.DispatchSendOpts
---@field open_focus? boolean
---@field pre_focus? boolean
---@field post_focus? boolean
---@field command_path? string
---@field on_sent? fun()

---@class codex.SendDispatchOpts
---@field get_deps fun(): table
---@field get_config fun(): table
---@field get_send_queue fun(): codex.SendQueue
---@field open_session fun(args: string[], focus: boolean)

---@alias codex.Error string|nil

return {}
