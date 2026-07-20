---@class dock.Badge
---@field icon  string    single-cell glyph shown before the tab label
---@field hl    string    highlight group for the glyph
---@field busy? boolean   the group is still working; busy groups are never auto-disposed

---@class dock.Config
---@field command     string                          user command name; false-y disables it
---@field position    "bottom"|"top"|"left"|"right"   where the panel splits
---@field size        number                          fraction of editor lines/columns (0..1)
---@field min_size    integer                         floor in lines/columns
---@field auto_open   boolean                         open the panel when a source adds a group
---@field empty_text  string                          shown when the panel holds no groups
---@field badges      table<string, dock.Badge>   status name → badge
---@field winbar      dock.Config.Winbar
---@field shell       dock.Config.Shell

---@class dock.Config.Winbar
---@field separator string  drawn between adjacent group tabs
---@field unread    string  marker appended to a page tab with unseen output
---@field numbers   boolean prefix each tab with its jump number

---@class dock.Config.Shell
---@field cmd?  string|string[]  defaults to 'shell' (with a no-op argument, see shell.lua)
---@field cwd?  string|fun():string?

---@type dock.Config
local M = {
    command    = "Dock",
    position   = "bottom",
    size       = 0.22,
    min_size   = 6,
    auto_open  = true,
    empty_text = "No panels",

    badges     = {
        running = { icon = "▶", hl = "DockBadgeOk", busy = true },
        waiting = { icon = "⧗", hl = "DockBadgeWarn", busy = true },
        ok      = { icon = "✓", hl = "DockBadgeOk" },
        failed  = { icon = "✗", hl = "DockBadgeErr" },
        stopped = { icon = "✗", hl = "DockBadgeHint" },
        idle    = { icon = "●", hl = "DockBadgeMuted" },
    },

    winbar     = {
        separator = "│",
        unread    = "•",
        numbers   = true,
    },

    shell      = {},
}

--- Merge user options into the live config table. Mutates in place so modules
--- that captured `require("dock.config")` at load time see the update.
---@param opts table?
function M.apply(opts)
    if not opts then return end
    for k, v in pairs(opts) do
        if type(v) == "table" and type(M[k]) == "table" and not vim.islist(v) then
            M[k] = vim.tbl_deep_extend("force", M[k], v)
        else
            M[k] = v
        end
    end
end

--- Split spec for the configured position: which axis fixedwin pins and which
--- placement modifier puts the split on the right edge of the editor.
---@return "height"|"width" axis, string pos
function M.split_spec()
    local pos = M.position
    if pos == "top" then return "height", "topleft" end
    if pos == "left" then return "width", "topleft" end
    if pos == "right" then return "width", "botright" end
    return "height", "botright"
end

return M
