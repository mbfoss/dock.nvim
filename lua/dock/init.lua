local Panel  = require("dock.Panel")
local Source = require("dock.Source")
local config = require("dock.config")

--- dock.nvim — one shared, docked window that any number of plugins can show
--- their buffers in.
---
--- A plugin claims a namespace with `source()`, then creates a `group` per tab
--- and a `page` per buffer inside it. dock owns the window, the tab bar, the
--- numbering, and the focus rules; the plugin owns its buffers and never has to
--- think about window layout.
---
--- The panel is editor-wide: every Neovim tabpage shows the same groups, the
--- same tab bar and the same page. Only the window is per-tabpage, so each tab
--- opens and closes its own view of it.
---
---     local src   = require("dock").source("myplugin")
---     local group = src:group({ label = "build", badge = RUNNING })
---     group:page({ buf = out_buf, label = "out" })
---     group:set_badge(DONE)
---
---@class dock
local M      = {}

local _sources = {} ---@type table<string, dock.Source>

--- Configure dock. Entirely optional — every entry has a default and dock
--- works untouched. Safe to call more than once.
---@param opts? dock.Config
function M.setup(opts)
    config.apply(opts)
    require("dock.commands").register()
end

--- Claim a namespace in the panel. Call once per plugin and keep the handle;
--- repeated calls with the same name return the same source.
---@param name string
---@return dock.Source
function M.source(name)
    assert(type(name) == "string" and name ~= "", "dock: source needs a name")
    if not _sources[name] then
        _sources[name] = Source.new(Panel.get(), name)
    end
    return _sources[name]
end

--- The shared panel, for the handful of operations that are not per-group.
---@return dock.Panel
function M.panel()
    return Panel.get()
end

--- Show the dock in the current tabpage.
---@param opts? { enter?: boolean }
function M.open(opts)
    Panel.get():open(opts)
end

--- Hide the dock in the current tabpage; `{ all = true }` hides it in every one.
--- The groups are kept either way.
---@param opts? { all?: boolean }
function M.close(opts)
    Panel.get():close(opts)
end

---@param opts? { enter?: boolean }
function M.toggle(opts)
    Panel.get():toggle(opts)
end

--- Select the nth tab. Numbering is flat across the winbar: one sequential
--- number per selectable tab — the group tab when it has a single page, each
--- page tab when it has several.
---@param n     integer
---@param opts? { enter?: boolean }
---@return boolean ok
function M.jump(n, opts)
    return Panel.get():jump(n, opts)
end

--- Every registered group, oldest first.
---@return dock.Group[]
function M.groups()
    return Panel.get():groups()
end

--- Ask sources to shed what they no longer need: every tab, or just the one a
--- winbar number selects. Each group answers for itself and may keep everything
--- (see `Group:clean`), so this reports how many tabs actually went.
---@param n? integer  tab number as shown in the winbar; omit to ask every tab
---@return integer cleaned
function M.clean(n)
    local panel = Panel.get()
    if n then
        local group = panel:group_at(n)
        return (group and group:clean()) and 1 or 0
    end
    local cleaned = 0
    for _, group in ipairs(panel:groups()) do
        if group:clean() then cleaned = cleaned + 1 end
    end
    return cleaned
end

--- Run a shell — or a command — in its own tab (builtin source).
---@param opts? dock.ShellOpts
---@return dock.Group?
function M.shell(opts)
    return require("dock.shell").open(opts)
end

return M
