local config = require("dock.config")

---@class dock.commands
local M      = {}

local _registered = nil ---@type string?  name of the command currently registered

---@type table<string, fun(args: string[], bang: boolean)>
local _actions = {}

_actions.open = function()
    require("dock").open({ enter = true })
end

_actions.close = function()
    require("dock").close()
end

_actions.toggle = function()
    require("dock").toggle({ enter = true })
end

_actions.shell = function()
    require("dock").shell()
end

_actions.next = function()
    require("dock").panel():cycle(1, { enter = true })
end

_actions.prev = function()
    require("dock").panel():cycle(-1, { enter = true })
end

_actions.jump = function(args)
    local ui = require("dock.tk.ui")
    local n  = tonumber(args[1])
    if not n then
        ui.notify_warning("jump needs a tab number")
        return
    end
    if not require("dock").panel():jump(n, { enter = true }) then
        ui.notify_warning("no tab " .. n)
    end
end

--- `dispose` closes one finished tab picked from a list; `dispose!` closes them
--- all. Busy tabs are never offered — a source marks a group busy precisely so a
--- bulk close cannot pull the buffer out from under a running job.
_actions.dispose = function(_, bang)
    local dock = require("dock")
    local ui       = require("dock.tk.ui")

    local groups   = dock.disposable()
    if #groups == 0 then
        ui.notify_info("no finished tabs to close")
        return
    end

    if bang then
        for _, group in ipairs(groups) do group:dispose() end
        return
    end

    vim.ui.select(groups, {
        prompt = "Close tab:",
        format_item = function(group)
            return string.format("%s  [%s]", group.label, group.status)
        end,
    }, function(choice)
        if choice then choice:dispose() end
    end)
end

local _SUBCOMMANDS = vim.tbl_keys(_actions)
table.sort(_SUBCOMMANDS)

--- Register the user command under the configured name, replacing a previously
--- registered one so `setup{ command = … }` can be called more than once.
function M.register()
    if not config.command or config.command == "" then
        M.unregister()
        return
    end
    if _registered == config.command then return end
    M.unregister()

    vim.api.nvim_create_user_command(config.command, function(cmd)
        local args = cmd.fargs
        local sub  = args[1]

        if not sub then
            _actions.toggle({}, cmd.bang)
            return
        end
        -- `:Dock 3` is shorthand for `:Dock jump 3`
        if tonumber(sub) then
            _actions.jump({ sub }, cmd.bang)
            return
        end

        local action = _actions[sub]
        if not action then
            require("dock.tk.ui").notify_warning("unknown subcommand: " .. sub)
            return
        end
        action(vim.list_slice(args, 2), cmd.bang)
    end, {
        nargs    = "*",
        bang     = true,
        desc     = "dock: shared buffer panel",
        complete = function(lead, line)
            -- only the first argument is a subcommand
            if line:match("^%s*%S+%s+%S*$") then
                return vim.tbl_filter(function(name)
                    return name:sub(1, #lead) == lead
                end, _SUBCOMMANDS)
            end
            return {}
        end,
    })

    _registered = config.command
end

function M.unregister()
    if _registered then
        pcall(vim.api.nvim_del_user_command, _registered)
        _registered = nil
    end
end

return M
