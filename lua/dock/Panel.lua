local config    = require("dock.config")
local fixedwin  = require("dock.tk.fixedwin")
local highlight = require("dock.highlight")
local throttle  = require("dock.tk.throttle")
local ui        = require("dock.tk.ui")
local winbar    = require("dock.winbar")

--- The panel: a fixed split whose winbar is a flat, numbered list of every
--- registered group's tabs. Groups belong to the panel *instance*, not to its
--- window — closing the panel only tears down the window, so re-opening restores
--- every tab exactly as it was.
---@class dock.Panel
---@field _win         integer?
---@field _augroup     integer?
---@field _groups      dock.Group[]
---@field _active      dock.Group?
---@field _active_page integer                    index into _active.pages; 0 when the group has none
---@field _shown_buf   integer?                   buffer currently in the window
---@field _closing_buf integer?                   buffer on screen when the window last closed, for one tick
---@field _ratio       number?                    last-known size ratio, persisted across open/close
---@field _targets     dock.Panel.Target[]    jump number → what it selects; rebuilt on every render
---@field _follow      dock.Group?            group allowed to take over even while the panel is focused
---@field _attached    table<integer, true>       buffers nvim_buf_attach has been called on
---@field _unread      table<integer, true>       buffers that gained lines while not visible
---@field _placeholder integer?
---@field _throttled_winbar fun()             coalesces the winbar redraws driven by buffer output
local Panel     = {}
Panel.__index   = Panel

---@class dock.Panel.Target
---@field group dock.Group
---@field page  integer  1-based page index, or 0 meaning "the group's best page"

local _instance = nil ---@type dock.Panel?

---@return dock.Panel
function Panel.new()
    local self = setmetatable({
        _groups      = {},
        _active_page = 0,
        _targets     = {},
        _attached    = {},
        _unread      = {},
    }, Panel)
    self._throttled_winbar = throttle.throttle_wrap(100, function()
        vim.schedule(function() self:_refresh_winbar() end)
    end)
    return self
end

--- The shared panel every source draws into.
---@return dock.Panel
function Panel.get()
    if not _instance then _instance = Panel.new() end
    return _instance
end

-- Window lifecycle

---@return boolean
function Panel:is_open()
    return self._win ~= nil and vim.api.nvim_win_is_valid(self._win)
end

--- True while the user has the panel window focused. Auto-takeover is suppressed
--- in that case, so background activity never yanks the view out from under
--- someone working inside the panel.
---@return boolean
function Panel:_is_focused()
    return self:is_open() and vim.api.nvim_get_current_win() == self._win
end

---@param opts? { enter?: boolean }
function Panel:open(opts)
    opts = opts or {}
    if self:is_open() then
        if opts.enter then vim.api.nvim_set_current_win(self._win) end
        return
    end

    highlight.setup()

    local axis, pos = config.split_spec()
    -- fixedwin owns the split creation, the fixed-size pinning, layout-change
    -- recovery, and the close lifecycle; on_delete hands back the last-known
    -- ratio (persisted for the next open) and runs our teardown.
    local win, augroup = fixedwin.create_fixed_win(
        axis,
        self._ratio or config.size,
        function(ratio)
            self._ratio = ratio
            self:_on_win_closed()
        end,
        { min = config.min_size, pos = pos, enter = opts.enter }
    )
    self._win, self._augroup = win, augroup

    ui.setlocal(win, "winfixbuf", true)
    ui.setlocal(win, "number", false)
    ui.setlocal(win, "relativenumber", false)
    ui.setlocal(win, "signcolumn", "no")
    ui.setlocal(win, "spell", false)
    ui.setlocal(win, "wrap", false)

    if not self._active or self._active:is_removed() then
        -- prefer the oldest still-working group, else the newest tab
        local pick = self._groups[#self._groups]
        for _, group in ipairs(self._groups) do
            if group:is_busy() then
                pick = group
                break
            end
        end
        self:_set_active(pick)
    end

    self:_show_active()
    self:_refresh_winbar()

    vim.api.nvim_create_autocmd("WinNew", {
        group    = augroup,
        callback = function()
            -- 'winbar' is copied onto a freshly split window, so splitting the
            -- panel leaves a sibling carrying our click regions that no render
            -- ever updates. Detect it and strip the panel-special options off.
            local new_win = vim.api.nvim_get_current_win()
            if self:is_open() and new_win ~= self._win
                and vim.wo[new_win].winbar ~= ""
                and vim.wo[new_win].winbar == vim.wo[self._win].winbar then
                vim.api.nvim_win_call(new_win, function()
                    vim.cmd("setlocal winbar< winfixheight< winfixwidth< winfixbuf< "
                        .. "number< relativenumber< signcolumn< spell< wrap<")
                end)
            end
        end,
    })

    vim.api.nvim_create_autocmd({ "WinResized", "ColorScheme" }, {
        group    = augroup,
        callback = function()
            if self:is_open() then
                highlight.setup()
                self:_refresh_winbar()
            end
        end,
    })
end

function Panel:close()
    if self:is_open() then
        -- fixedwin's on_delete saves the ratio and calls _on_win_closed.
        pcall(vim.api.nvim_win_close, self._win, false)
    end
end

---@param opts? { enter?: boolean }
function Panel:toggle(opts)
    if self:is_open() then
        self:close()
    else
        self:open(opts)
    end
end

function Panel:_on_win_closed()
    -- Deleting a buffer closes every window showing it, and Neovim emits
    -- WinClosed *before* any BufUnload/BufWipeout autocmd — there is no hook
    -- early enough to move the panel off the doomed buffer first. So record what
    -- was on screen; if that exact buffer unloads in this same tick, the close
    -- was collateral damage from the delete and _attach_buf reopens the panel.
    self._closing_buf = self._shown_buf
    vim.schedule(function() self._closing_buf = nil end)

    self._win         = nil
    self._augroup     = nil
    self._shown_buf   = nil
end

-- Buffer display

---@return integer bufnr
function Panel:_placeholder_buf()
    if not self._placeholder or not vim.api.nvim_buf_is_valid(self._placeholder) then
        local ns = vim.api.nvim_create_namespace("DockPlaceholder")
        self._placeholder = ui.create_scratch_buffer(false, { bufhidden = "hide", buflisted = false })
        vim.bo[self._placeholder].modifiable = true
        vim.api.nvim_buf_set_lines(self._placeholder, 0, -1, false, { "" })
        vim.bo[self._placeholder].modifiable = false
        vim.api.nvim_buf_set_extmark(self._placeholder, ns, 0, 0, {
            virt_text     = { { config.empty_text, "Comment" } },
            virt_text_pos = "overlay",
        })
    end
    return self._placeholder
end

---@param bufnr integer
function Panel:_attach_buf(bufnr)
    if self._attached[bufnr] then return end
    self._attached[bufnr] = true

    vim.api.nvim_buf_attach(bufnr, false, {
        on_lines = function()
            if self:is_open() and vim.api.nvim_win_get_buf(self._win) ~= bufnr then
                self._unread[bufnr] = true
                self._throttled_winbar()
            end
        end,
        on_detach = function()
            self._attached[bufnr] = nil
            self._unread[bufnr]   = nil
        end,
    })

    -- Drop the page when its buffer goes away. No augroup, so this outlives
    -- panel open/close cycles the way the buffer does.
    vim.api.nvim_create_autocmd("BufUnload", {
        buffer   = bufnr,
        once     = true,
        callback = function()
            self._attached[bufnr] = nil
            local took_panel_down = self._closing_buf == bufnr

            for _, group in ipairs(vim.list_slice(self._groups)) do
                group:remove_page(bufnr)
            end

            -- Restore the panel Neovim closed out from under us (see
            -- _on_win_closed), but only if there is still something to show —
            -- reopening an empty panel over a wiped last tab is just noise.
            if took_panel_down and #self._groups > 0 then
                vim.schedule(function()
                    if not self:is_open() then self:open() end
                end)
            end
        end,
    })
end

---@param bufnr integer
function Panel:_set_win_buf(bufnr)
    if not self:is_open() then return end
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    ui.setlocal(self._win, "winfixbuf", false)
    vim.api.nvim_win_set_buf(self._win, bufnr)
    ui.setlocal(self._win, "winfixbuf", true)
    self._unread[bufnr] = nil
    self._shown_buf     = bufnr
    if vim.bo[bufnr].buftype == "terminal" then
        local last = vim.api.nvim_buf_line_count(bufnr)
        pcall(vim.api.nvim_win_set_cursor, self._win, { last, 0 })
    end
end

--- Put the active group's active page in the window, falling back to the
--- group's best page and then to the placeholder buffer.
function Panel:_show_active()
    if not self:is_open() then return end

    local group = self._active
    local page  = group and group.pages[self._active_page] or nil

    if group and (not page or not vim.api.nvim_buf_is_valid(page.buf)) then
        self._active_page = self:_best_page(group)
        page              = group.pages[self._active_page]
    end

    local prev = self._shown_buf
    if page and vim.api.nvim_buf_is_valid(page.buf) then
        self:_set_win_buf(page.buf)
    else
        self:_set_win_buf(self:_placeholder_buf())
        page = nil
    end

    if group and group.on_activate and self._shown_buf ~= prev then
        group.on_activate(group, page)
    end
end

-- Active group / page selection

--- Index of the group's highest-priority page, or 0 when it has none.
---@param group dock.Group
---@return integer
function Panel:_best_page(group)
    local best_idx, best_pri = 0, nil
    for i, page in ipairs(group.pages) do
        if best_pri == nil or page.priority > best_pri then
            best_idx, best_pri = i, page.priority
        end
    end
    return best_idx
end

---@param group dock.Group?
---@param page_idx? integer
function Panel:_set_active(group, page_idx)
    -- Selecting anything but the followed group ends the follow.
    if group ~= self._follow then self._follow = nil end
    self._active      = group
    self._active_page = group and (page_idx or self:_best_page(group)) or 0
end

--- Advance to the active group's best page, but only when it outranks the page
--- already on screen — so a low-priority buffer appearing mid-run never pulls
--- the user off the output they are watching.
function Panel:_advance_best()
    local group = self._active
    if not group then return end
    local cur  = group.pages[self._active_page]
    local best = self:_best_page(group)
    if best == 0 then return end
    if not cur or group.pages[best].priority > cur.priority then
        self._active_page = best
    end
end

--- Whether background activity in `group` may change what is displayed: yes
--- unless the user is working inside the panel, and always for a followed group.
---@param group dock.Group
---@return boolean
function Panel:_may_follow(group)
    return self._follow == group or not self:_is_focused()
end

---@param group dock.Group
---@return boolean
function Panel:_should_takeover(group)
    -- "never" means never *steals* — with nothing on screen there is nothing to
    -- steal from, and an empty panel next to a populated winbar just looks broken.
    if not self._active or self._active:is_removed() then return true end
    if group.focus == "never" then return false end
    if group.focus == "always" then return true end
    return not self:_is_focused()
end

---@param group dock.Group
---@param page? dock.Page|integer
---@param buf?  integer
---@return integer? page index
function Panel:_resolve_page(group, page, buf)
    if buf then
        for i, p in ipairs(group.pages) do
            if p.buf == buf then return i end
        end
        return nil
    end
    if type(page) == "number" then
        return (page >= 1 and page <= #group.pages) and page or nil
    end
    if type(page) == "table" then
        for i, p in ipairs(group.pages) do
            if p == page then return i end
        end
    end
    return nil
end

--- Show a group, opening the panel if it is closed.
---@param group dock.Group
---@param opts? dock.ActivateOpts
function Panel:activate(group, opts)
    opts = opts or {}
    self:open()
    self:_set_active(group, self:_resolve_page(group, opts.page, opts.buf))
    self:_show_active()
    self:_refresh_winbar()
    if opts.enter and self:is_open() then
        vim.api.nvim_set_current_win(self._win)
    end
end

-- Group notifications (called from Group / Source)

---@param group      dock.Group
---@param auto_open? boolean  per-group override of config.auto_open
function Panel:_group_added(group, auto_open)
    self._groups[#self._groups + 1] = group

    if auto_open == nil then auto_open = config.auto_open end
    local takeover = self:_should_takeover(group)

    if auto_open and not self:is_open() then
        -- open() picks an active group itself when there is none; setting ours
        -- first keeps that choice consistent with the takeover decision.
        if takeover then self:_set_active(group) end
        self:open()
    end

    if takeover then
        self:_set_active(group)
        if group.focus == "always" then self._follow = group end
        self:_show_active()
    end
    self:_refresh_winbar()
end

---@param group dock.Group
function Panel:_group_changed(group)
    -- A followed group stops overriding the focus guard once it finishes, so its
    -- final update does not disturb someone working in the panel.
    if self._follow == group and not group:is_busy() then
        self._follow = nil
    end
    self:_refresh_winbar()
end

---@param group dock.Group
function Panel:_group_removed(group)
    local idx
    for i, g in ipairs(self._groups) do
        if g == group then
            idx = i
            break
        end
    end
    if not idx then return end

    table.remove(self._groups, idx)
    if self._follow == group then self._follow = nil end
    for _, page in ipairs(group.pages) do
        self._unread[page.buf] = nil
    end

    if self._active == group then
        -- Prefer the tab that slid into this slot, the way closing a tab works
        -- everywhere else; fall back to the newest.
        self:_set_active(self._groups[idx] or self._groups[#self._groups])
        -- Synchronous: the window must leave the buffer before a caller that is
        -- disposing this group deletes it.
        self:_show_active()
    end
    self:_refresh_winbar()
end

---@param group dock.Group
---@param page  dock.Page
---@param force boolean  caller insists this page goes on screen
function Panel:_page_added(group, page, force)
    self:_attach_buf(page.buf)

    if force then
        self:activate(group, { page = page })
        return
    end
    if group == self._active and self:_may_follow(group) then
        self:_advance_best()
        self:_show_active()
    end
    self:_refresh_winbar()
end

---@param group dock.Group
---@param page  dock.Page
function Panel:_page_removed(group, page)
    self._unread[page.buf] = nil

    if group == self._active then
        if self._active_page > #group.pages then
            self._active_page = #group.pages
        end
        self:_show_active()
    end

    if group.remove_when_empty and #group.pages == 0 then
        group:remove()
        return
    end
    self:_refresh_winbar()
end

-- Rendering

---@return dock.winbar.Tab[], dock.Panel.Target[]
function Panel:_build_tabs()
    local tabs, targets = {}, {}

    for _, group in ipairs(self._groups) do
        local badge      = group:badge_spec()
        local tab_num    = #targets + 1
        targets[tab_num] = { group = group, page = 0 }

        local unread     = false
        for _, page in ipairs(group.pages) do
            if self._unread[page.buf] then unread = true end
        end

        ---@type dock.winbar.Tab
        local tab = {
            num     = tab_num,
            label   = group.label,
            icon    = badge.icon,
            icon_hl = badge.hl,
            active  = group == self._active,
            unread  = unread,
            pages   = {},
        }

        -- A single page needs no page tab: the group tab already selects it.
        if #group.pages > 1 then
            for pi, page in ipairs(group.pages) do
                local page_num    = #targets + 1
                targets[page_num] = { group = group, page = pi }
                tab.pages[#tab.pages + 1] = {
                    num     = page_num,
                    label   = page.label,
                    current = tab.active and pi == self._active_page,
                    unread  = self._unread[page.buf] or false,
                }
            end
            -- page tabs carry the unread markers; don't double up on the group tab
            tab.unread = false
        end

        tabs[#tabs + 1] = tab
    end

    return tabs, targets
end

function Panel:_refresh_winbar()
    if not self:is_open() then return end
    local tabs, targets = self:_build_tabs()
    self._targets       = targets

    local text = winbar.build(tabs, vim.api.nvim_win_get_width(self._win), {
        separator  = config.winbar.separator,
        unread     = config.winbar.unread,
        numbers    = config.winbar.numbers,
        click      = "v:lua.__dock_click",
        empty_text = config.empty_text,
    })

    -- 'winbar' is global-local: `vim.wo[win].winbar = …` would also write the
    -- hidden global value, and every window without a local winbar would start
    -- rendering the panel's. Keep it local.
    ui.setlocal(self._win, "winbar", text)
end

-- Navigation

--- Select the nth tab. Numbering is flat across the whole winbar — every group
--- tab and every page tab gets one sequential number.
---@param n     integer
---@param opts? { enter?: boolean }
---@return boolean ok
function Panel:jump(n, opts)
    self:open()
    local _, targets = self:_build_tabs()
    self._targets    = targets

    local target = targets[n]
    if not target then return false end

    self:_set_active(target.group, target.page ~= 0 and target.page or nil)
    self:_show_active()
    self:_refresh_winbar()
    if opts and opts.enter and self:is_open() then
        vim.api.nvim_set_current_win(self._win)
    end
    return true
end

--- Step through the flat tab numbering, wrapping at both ends.
---@param delta integer
---@param opts? { enter?: boolean }
function Panel:cycle(delta, opts)
    self:open()
    local _, targets = self:_build_tabs()
    self._targets    = targets
    if #targets == 0 then return end

    local cur = 1
    for i, t in ipairs(targets) do
        if t.group == self._active and (t.page == self._active_page or t.page == 0) then
            cur = i
            -- an exact page match beats the group-tab fallback
            if t.page == self._active_page then break end
        end
    end

    self:jump((cur - 1 + delta) % #targets + 1, opts)
end

-- Queries

--- Every registered group, oldest first.
---@return dock.Group[]
function Panel:groups()
    return vim.list_slice(self._groups)
end

---@return dock.Group?
function Panel:active()
    return self._active
end

--- Groups that are not busy, i.e. safe to close in bulk.
---@return dock.Group[]
function Panel:disposable()
    local out = {}
    for _, group in ipairs(self._groups) do
        if not group:is_busy() then out[#out + 1] = group end
    end
    return out
end

-- Winbar click handler. The `%N@fn@` syntax needs a global, and there is exactly
-- one panel, so a single global is enough.
---@param num integer
function _G.__dock_click(num)
    Panel.get():jump(num)
end

return Panel
