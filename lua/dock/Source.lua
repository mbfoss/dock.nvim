local Group = require("dock.Group")

--- A source is one plugin's handle on the shared panel. It namespaces the groups
--- that plugin owns, so `dock.disposable()` and the panel commands can act on
--- them without any plugin reaching into another's tabs.
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

--- Every live group this source owns, in creation order.
---@return dock.Group[]
function Source:groups()
    local out = {}
    for _, group in ipairs(self._panel:groups()) do
        if group._source == self then out[#out + 1] = group end
    end
    return out
end

--- Dispose every group this source owns, `on_dispose` included.
---@param opts? { busy?: boolean }  busy = true also disposes groups still working
function Source:clear(opts)
    local busy = opts and opts.busy
    for _, group in ipairs(self:groups()) do
        if busy or not group:is_busy() then group:dispose() end
    end
end

return Source
