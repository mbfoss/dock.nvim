---@class dock.winbar
local M = {}

-- The winbar is assembled as a list of items so overflow can be measured before
-- the string is produced. Each item is `{ kind, text }`:
--   kind 1 — croppable visible text (group and page labels)
--   kind 2 — fixed visible text (icons, numbers, punctuation)
--   kind 3 — zero-width escapes (highlight groups, click regions)
-- Only kinds 1 and 2 occupy columns, so `%#Group#` / `%N@fn@` runs never skew
-- the width budget.

local _CROP, _FIXED, _ZERO = 1, 2, 3

--- Shortest a cropped label may become before the cropper gives up on it.
local _MIN_LABEL = 2

---@class dock.winbar.Page
---@field num     integer  global jump number
---@field label   string
---@field current boolean  currently displayed in the panel
---@field unread  boolean  gained lines while not visible

---@class dock.winbar.Tab
---@field num     integer  global jump number for the group's own tab
---@field label   string
---@field icon    string
---@field icon_hl string
---@field active  boolean  this group owns the displayed buffer
---@field unread  boolean  unseen output somewhere in the group; only set when it draws no page tabs
---@field pages   dock.winbar.Page[]  page tabs; empty when the group has a single page

---@class dock.winbar.Opts
---@field separator  string   between adjacent group tabs
---@field unread     string   marker for a page tab with unseen output
---@field numbers    boolean  prefix tabs with their jump number
---@field click      string   vimscript function ref for `%N@…@` click regions
---@field empty_text string   rendered when there are no tabs at all

---@param items {[1]: integer, [2]: string}[]
---@param width integer
---@return string
local function _flatten(items, width)
    local total, croppable = 0, {} ---@type integer, integer[]
    local widths = {} ---@type table<integer, integer>

    for i, it in ipairs(items) do
        if it[1] ~= _ZERO then
            local w = vim.fn.strdisplaywidth(it[2])
            widths[i] = w
            total = total + w
            if it[1] == _CROP then croppable[#croppable + 1] = i end
        end
    end

    -- Shave one column at a time off whichever label is currently widest. Costs
    -- a pass per overflowing column but keeps short labels legible instead of
    -- charging every label an equal share of the overflow.
    while total > width do
        local widest, widest_w = nil, _MIN_LABEL
        for _, i in ipairs(croppable) do
            if widths[i] > widest_w then widest, widest_w = i, widths[i] end
        end
        if not widest then break end
        widths[widest] = widths[widest] - 1
        total = total - 1
    end

    local out = {}
    for i, it in ipairs(items) do
        local text = it[2]
        if it[1] == _CROP then
            local target = widths[i]
            if target < vim.fn.strdisplaywidth(text) then
                text = vim.fn.strcharpart(text, 0, math.max(target - 1, 1)) .. "…"
            end
        end
        out[#out + 1] = text
    end
    return table.concat(out)
end

--- Render the winbar for a set of group tabs, cropping labels to fit `width`.
---@param tabs  dock.winbar.Tab[]
---@param width integer
---@param opts  dock.winbar.Opts
---@return string
function M.build(tabs, width, opts)
    if #tabs == 0 then
        return "%#WinBar# %#DockBadgeMuted#" .. opts.empty_text .. "%#WinBar#"
    end

    local items = {} ---@type {[1]: integer, [2]: string}[]
    local function push(kind, text) items[#items + 1] = { kind, text } end

    ---@param num integer
    local function open_click(num)
        push(_ZERO, string.format("%%%d@%s@", num, opts.click))
    end
    local function close_click()
        push(_ZERO, "%X")
    end

    ---@param num integer
    ---@return string
    local function prefix(num)
        return opts.numbers and (num .. ":") or ""
    end

    for ti, tab in ipairs(tabs) do
        local tab_hl = tab.active and "%#DockActiveTab#" or "%#WinBar#"

        if ti > 1 then
            push(_ZERO, "%#DockBadgeMuted#")
            push(_FIXED, opts.separator)
        end
        push(_FIXED, " ")

        open_click(tab.num)
        push(_ZERO, "%#" .. tab.icon_hl .. "#")
        push(_FIXED, tab.icon .. " ")
        push(_ZERO, tab_hl)
        push(_FIXED, prefix(tab.num))
        push(_CROP, tab.label)
        if tab.unread then
            push(_ZERO, "%#DockUnread#")
            push(_FIXED, opts.unread)
        end
        close_click()

        if #tab.pages > 0 then
            push(_FIXED, " [")
            for pi, page in ipairs(tab.pages) do
                if pi > 1 then
                    push(_ZERO, "%#DockBadgeMuted#")
                    push(_FIXED, "|")
                end
                open_click(page.num)
                -- A page that is neither current nor part of the active group is
                -- muted, so the eye lands on what is actually on screen.
                push(_ZERO, page.current and tab_hl or "%#DockBadgeMuted#")
                push(_FIXED, prefix(page.num))
                push(_CROP, page.label)
                if page.unread then
                    push(_ZERO, "%#DockUnread#")
                    push(_FIXED, opts.unread)
                end
                close_click()
            end
            push(_ZERO, tab_hl)
            push(_FIXED, "]")
        end

        push(_ZERO, "%#WinBar#")
        push(_FIXED, " ")
    end

    return _flatten(items, width)
end

return M
