---@class dock.Badge
---@field icon  string    single-cell glyph shown before the tab label
---@field hl    string    highlight group for the glyph

--- A group is one tab in the panel: a label, an optional badge, and an ordered
--- list of pages (buffers). The owning source mutates it through these methods;
--- every mutator notifies the panel so the winbar and the displayed buffer stay
--- in sync. A group outlives the panel window — closing the panel does not
--- discard it, and re-opening restores every tab, in whichever tabpage the dock
--- is opened next.
---@class dock.Group
---@field id                string
---@field label             string
---@field pages             dock.Page[]
---@field data              table                 free-form, owned by the source
---@field focus             "auto"|"never"|"always"
---@field badge             dock.Badge?           glyph drawn before the tab label; none when nil
---@field busy              boolean               the group is still working
---@field remove_when_empty boolean               drop the tab once its last page goes away
---@field on_clean          fun(group: dock.Group)?   called by :clean() so the source can shed what it no longer needs
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
---@field badge?             dock.Badge              glyph drawn before the tab label
---@field busy?              boolean                 the group is still working; default false
---@field focus?             "auto"|"never"|"always" how eagerly the tab takes over the panel; default "auto"
---@field data?              table
---@field remove_when_empty? boolean
---@field auto_open?         boolean                 override config.auto_open for this group
---@field on_clean?          fun(group: dock.Group)  asked to shed the tab; ignoring the request is valid
---@field on_activate?       fun(group: dock.Group, page: dock.Page?)

---@param source dock.Source
---@param panel  dock.Panel
---@param spec   dock.GroupSpec
---@return dock.Group
function Group.new(source, panel, spec)
    return setmetatable({
        id                = spec.id,
        label             = spec.label or spec.id,
        badge             = spec.badge,
        busy              = spec.busy or false,
        focus             = spec.focus or "auto",
        pages             = {},
        data              = spec.data or {},
        remove_when_empty = spec.remove_when_empty or false,
        on_clean          = spec.on_clean,
        on_activate       = spec.on_activate,
        _source           = source,
        _panel            = panel,
        _removed          = false,
    }, Group)
end

--- True while the group is still working. Presentation only: the panel prefers
--- a busy tab when it has to pick one to show. Whether a tab may go is never
--- dock's call — see `clean()`.
---@return boolean
function Group:is_busy()
    return self.busy
end

---@param busy boolean
---@return dock.Group self
function Group:set_busy(busy)
    busy = busy and true or false
    if self.busy ~= busy then
        self.busy = busy
        self._panel:_group_changed(self)
    end
    return self
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

---@param label string
---@return dock.Group self
function Group:set_label(label)
    if self.label ~= label then
        self.label = label
        self._panel:_group_changed(self)
    end
    return self
end

---@param badge dock.Badge?  nil draws the tab without a glyph
---@return dock.Group self
function Group:set_badge(badge)
    if self.badge ~= badge then
        self.badge = badge
        self._panel:_group_changed(self)
    end
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

--- Detach the group from the panel. Buffers are left alone — the source owns
--- them, and decides in `on_clean` whether they outlive the tab.
function Group:remove()
    if self._removed then return end
    self._removed = true
    self._source:_forget(self)
    self._panel:_group_removed(self)
end

--- Ask the source to shed this tab: release the buffers it no longer needs and
--- drop the tab when it is done with them.
---
--- A clean is a hint, not an order. dock has no idea whether a buffer still
--- matters, so it never deletes one and never removes a tab on its own — it
--- asks, and the source answers by doing whatever is right for it, including
--- nothing. A group with no `on_clean` keeps everything.
---@return boolean removed  whether the tab is gone now
function Group:clean()
    if self._removed then return true end
    if self.on_clean then self.on_clean(self) end
    return self._removed
end

return Group
