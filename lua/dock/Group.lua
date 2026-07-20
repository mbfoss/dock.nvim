local config = require("dock.config")

--- A group is one tab in the panel: a label, a status badge, and an ordered list
--- of pages (buffers). The owning source mutates it through these methods; every
--- mutator notifies the panel so the winbar and the displayed buffer stay in
--- sync. A group outlives the panel window — closing the panel does not discard
--- it, and re-opening restores every tab.
---@class dock.Group
---@field id                string
---@field label             string
---@field status            string
---@field pages             dock.Page[]
---@field data              table                 free-form, owned by the source
---@field focus             "auto"|"never"|"always"
---@field badge             dock.Badge?       explicit badge; overrides the status lookup
---@field remove_when_empty boolean               drop the tab once its last page goes away
---@field on_dispose        fun(group: dock.Group)?   called by :dispose() so the source can free buffers
---@field on_activate       fun(group: dock.Group, page: dock.Page?)?
---@field _source           dock.Source
---@field _panel            dock.Panel
---@field _removed          boolean
local Group = {}
Group.__index = Group

---@class dock.Page
---@field buf      integer
---@field label    string
---@field priority integer  highest priority page wins when the panel auto-advances

---@class dock.GroupSpec
---@field id?                string                  stable id for source:get(); defaults to a generated one
---@field label?             string                  tab text; defaults to the id
---@field status?            string                  key into the badge table; default "idle"
---@field badge?             dock.Badge          explicit badge, bypassing the status lookup
---@field focus?             "auto"|"never"|"always" how eagerly the tab takes over the panel; default "auto"
---@field data?              table
---@field remove_when_empty? boolean
---@field auto_open?         boolean                 override config.auto_open for this group
---@field on_dispose?        fun(group: dock.Group)
---@field on_activate?       fun(group: dock.Group, page: dock.Page?)

---@param source dock.Source
---@param panel  dock.Panel
---@param spec   dock.GroupSpec
---@return dock.Group
function Group.new(source, panel, spec)
    return setmetatable({
        id                = spec.id,
        label             = spec.label or spec.id,
        status            = spec.status or "idle",
        badge             = spec.badge,
        focus             = spec.focus or "auto",
        pages             = {},
        data              = spec.data or {},
        remove_when_empty = spec.remove_when_empty or false,
        on_dispose        = spec.on_dispose,
        on_activate       = spec.on_activate,
        _source           = source,
        _panel            = panel,
        _removed          = false,
    }, Group)
end

--- Resolve the badge to draw: an explicit `badge` wins, then the source's own
--- status table, then the global one, then the `idle` fallback.
---@return dock.Badge
function Group:badge_spec()
    if self.badge then return self.badge end
    return self._source.badges[self.status]
        or config.badges[self.status]
        or config.badges.idle
end

--- True while the group is still working. Busy groups are excluded from
--- `dock.disposable()` so an in-flight job is never swept up by a bulk close.
---@return boolean
function Group:is_busy()
    return self:badge_spec().busy == true
end

---@return boolean
function Group:is_removed()
    return self._removed
end

---@class dock.PageSpec
---@field buf       integer
---@field label?    string   defaults to the buffer's basename, else "buf N"
---@field priority? integer  default 0
---@field activate? boolean  force this page on screen, bypassing the priority comparison

--- Append a page (buffer) to the group.
---
--- The panel advances to it only when it outranks whatever is on screen, so a
--- source can add a low-priority log buffer without yanking the user off the
--- output they are reading. Pass `activate = true` to insist.
---@param spec dock.PageSpec
---@return dock.Page?
function Group:page(spec)
    if self._removed then return nil end
    assert(type(spec.buf) == "number", "dock: page requires a buffer number")
    if not vim.api.nvim_buf_is_valid(spec.buf) then return nil end

    for _, p in ipairs(self.pages) do
        if p.buf == spec.buf then return p end
    end

    local name = vim.api.nvim_buf_get_name(spec.buf)
    ---@type dock.Page
    local page = {
        buf      = spec.buf,
        label    = spec.label
            or (name ~= "" and vim.fn.fnamemodify(name, ":t"))
            or ("buf " .. spec.buf),
        priority = spec.priority or 0,
    }
    self.pages[#self.pages + 1] = page
    self._panel:_page_added(self, page, spec.activate == true)
    return page
end

--- Remove a page. Never touches the buffer itself — buffers are borrowed from
--- the source, which owns their lifetime.
---@param page dock.Page|integer  a page, or the buffer number of one
---@return boolean removed
function Group:remove_page(page)
    local buf = type(page) == "number" and page or page.buf
    for i, p in ipairs(self.pages) do
        if p.buf == buf then
            table.remove(self.pages, i)
            self._panel:_page_removed(self, p)
            return true
        end
    end
    return false
end

---@param status string
---@return dock.Group self
function Group:set_status(status)
    if self.status ~= status then
        self.status = status
        self._panel:_group_changed(self)
    end
    return self
end

---@param label string
---@return dock.Group self
function Group:set_label(label)
    if self.label ~= label then
        self.label = label
        self._panel:_group_changed(self)
    end
    return self
end

---@param badge dock.Badge?  nil restores the status-driven badge
---@return dock.Group self
function Group:set_badge(badge)
    self.badge = badge
    self._panel:_group_changed(self)
    return self
end

---@class dock.ActivateOpts
---@field page?  dock.Page|integer  a page, or its 1-based index; defaults to the group's best page
---@field buf?   integer                select the page showing this buffer; takes precedence over `page`
---@field enter? boolean                move the cursor into the panel window

--- Put this group on screen, opening the panel if needed.
---@param opts? dock.ActivateOpts
---@return dock.Group self
function Group:activate(opts)
    if not self._removed then
        self._panel:activate(self, opts)
    end
    return self
end

--- Detach the group from the panel. Buffers are left alone; use `dispose()` when
--- the source should clean them up too.
function Group:remove()
    if self._removed then return end
    self._removed = true
    self._source._groups[self.id] = nil
    self._panel:_group_removed(self)
end

--- Remove the group and let the source release its buffers via `on_dispose`.
--- This is what the panel's own close/dispose commands call.
function Group:dispose()
    if self._removed then return end
    local on_dispose = self.on_dispose
    -- Detach first: the panel must move off any buffer the source is about to
    -- delete, or deleting it would tear down the panel window with it.
    self:remove()
    if on_dispose then on_dispose(self) end
end

return Group
