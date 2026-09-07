local Group = require("dock.Group")

--- A source is one plugin's handle on the shared panel. It namespaces the groups
--- that plugin owns, so `:Dock clean` and the other panel commands can act
--- on them without any plugin reaching into another's tabs.
---
--- Like the panel, a source is editor-wide: its groups are the same set no
--- matter which Neovim tabpage they were created from.
---@class dock.Source
---@field name    string
---@field _panel  dock.Panel
---@field _groups table<string, dock.Group>
---@field _seq    integer
local Source = {}
Source.__index = Source

---@param panel dock.Panel
---@param name  string
---@return dock.Source
function Source.new(panel, name)
    return setmetatable({
        name    = name,
        _panel  = panel,
        _groups = {},
        _seq    = 0,
    }, Source)
end

--- Create a tab in the panel.
---
--- Reusing an existing `id` returns that group instead of creating a second one,
--- so a source can call this idempotently for a long-lived tab.
---@param spec? dock.GroupSpec
---@return dock.Group
function Source:group(spec)
    spec = spec or {}
    if spec.id and self._groups[spec.id] then
        return self._groups[spec.id]
    end

    if not spec.id then
        self._seq = self._seq + 1
        spec = vim.tbl_extend("force", spec, {
            id = string.format("%s#%d", self.name, self._seq),
        })
    end

    local group = Group.new(self, self._panel, spec)
    self._groups[group.id] = group
    self._panel:_group_added(group, spec.auto_open)
    return group
end

---@param id string
---@return dock.Group?
function Source:get(id)
    return self._groups[id]
end

--- Called by Group:remove() once the group is detached from the panel.
---@param group dock.Group
function Source:_forget(group)
    self._groups[group.id] = nil
end

--- Every live group this source owns, in creation order.
---@return dock.Group[]
function Source:groups()
    local out = {}
    for _, group in ipairs(self._panel:groups()) do
        if group._source == self then out[#out + 1] = group end
    end
    return out
end

--- Ask every group this source owns to shed itself (see `Group:clean`).
---@return integer cleaned  how many tabs went away
function Source:clean()
    local n = 0
    for _, group in ipairs(self:groups()) do
        if group:clean() then n = n + 1 end
    end
    return n
end

--- Detach every group this source owns, without asking. The buffers are left
--- alone; this is for a source tearing its own tabs down, not for cleanup.
function Source:clear()
    for _, group in ipairs(self:groups()) do
        group:remove()
    end
end

return Source
