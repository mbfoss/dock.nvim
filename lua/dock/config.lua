---@class dock.Config
---@field command     string                          user command name; false-y disables it
---@field position    "bottom"|"top"|"left"|"right"   where the dock splits
---@field size        number                          fraction of editor lines/columns (0..1)
---@field min_size    integer                         floor in lines/columns
---@field auto_open   boolean                         open the dock when a source adds a group
---@field empty_text  string                          shown when there is no page to show
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
local _defaults = {
    command    = "Dock",
    position   = "bottom",
    size       = 0.22,
    min_size   = 6,
    auto_open  = true,
    empty_text = "No pages",

    winbar     = {
        separator = "│",
        unread    = "•",
        numbers   = true,
    },

    shell      = {},
}

local M = {}

--- The live options, at the defaults until `apply()` applies the user's. Always
--- this same table: `apply()` refills it in place, so a module may capture it
--- once at its top (`local config = require("dock.config").current`) and never
--- see a stale value.
---@type dock.Config
M.current = vim.deepcopy(_defaults)

--- The configuration as it shipped. A fresh deep copy every call, so the caller
--- may keep or mutate it.
---@return dock.Config
function M.defaults()
    return vim.deepcopy(_defaults)
end

--- Overwrite `dst` from `src` key by key: a key `src` lacks is dropped, and a
--- table on both sides recurses instead of being swapped in. A list is a value,
--- not a table to merge into, so naming one replaces it outright. Nothing
--- reachable from `current` is ever replaced, and nothing stale is left behind.
local function _refill(dst, src)
    for k in pairs(dst) do
        if src[k] == nil then dst[k] = nil end
    end
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" and not vim.islist(v) then
            _refill(dst[k], v)
        else
            dst[k] = type(v) == "table" and vim.deepcopy(v) or v
        end
    end
end

--- Merge user options over the defaults. Starting from a copy of the defaults
--- rather than from `current` means no key of an earlier call can survive into
--- a later one.
---@param opts dock.Config?
function M.apply(opts)
    local merged = vim.deepcopy(_defaults)
    for k, v in pairs(opts or {}) do
        if type(v) == "table" and type(merged[k]) == "table" and not vim.islist(v) then
            merged[k] = vim.tbl_deep_extend("force", merged[k], v)
        else
            merged[k] = v
        end
    end
    _refill(M.current, merged)
end

--- Split spec for the configured position: which axis fixedwin pins and which
--- placement modifier puts the split on the right edge of the editor.
---@return "height"|"width" axis, string pos
function M.split_spec()
    local pos = M.current.position
    if pos == "top" then return "height", "topleft" end
    if pos == "left" then return "width", "topleft" end
    if pos == "right" then return "width", "botright" end
    return "height", "botright"
end

return M
