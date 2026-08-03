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
---     local src   = require("dock").source("myplugin")
---     local group = src:group({ label = "build", badge = RUNNING })
---     group:page({ buf = out_buf, label = "out" })
---     group:set_badge(DONE)
---
---@class dock
local M      = {}

local _sources = {} ---@type table<string, dock.Source>

--- Configure dock. Entirely optional — every entry has a default and the
--- panel works untouched. Safe to call more than once.
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

---@param opts? { enter?: boolean }
function M.open(opts)
    Panel.get():open(opts)
end

function M.close()
    Panel.get():close()
end

---@param opts? { enter?: boolean }
function M.toggle(opts)
    Panel.get():toggle(opts)
end

--- Select the nth tab. Numbering is flat across the winbar: every group tab and
--- every page tab has one sequential number.
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

--- Groups that are not busy, i.e. safe to close.
---@return dock.Group[]
function M.disposable()
    return Panel.get():disposable()
end

--- Run a shell — or a command — as a page of the shared "Shell" tab (builtin
--- source).
---@param opts? dock.ShellOpts
---@return dock.Group?
function M.shell(opts)
    return require("dock.shell").open(opts)
end

return M
