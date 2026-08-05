local config = require("dock.config")

---@class dock.commands
local M      = {}

local _registered = nil ---@type string?  name of the command currently registered

---@type table<string, fun(args: string[], bang: boolean)>
local _actions = {}

_actions.open = function()
    require("dock").open({ enter = true })
end

--- `:Dock close` hides the dock in this tabpage; `:Dock! close` hides it in all
--- of them. Neither touches the tabs themselves.
_actions.close = function(_, bang)
    require("dock").close({ all = bang })
end

_actions.toggle = function()
    require("dock").toggle({ enter = true })
end

--- `:Dock shell` opens an interactive shell; `:Dock shell echo 3` runs that
--- command instead. The arguments are rejoined into one string so the user's
--- shell handles quoting, pipes and globs the way it does at a prompt.
_actions.shell = function(args)
    local cmd = #args > 0 and table.concat(args, " ") or nil
    require("dock").shell({ cmd = cmd })
end

_actions.next = function()
    require("dock").panel():cycle(1, { enter = true })
end

_actions.prev = function()
    require("dock").panel():cycle(-1, { enter = true })
end

_actions.jump = function(args)
    local ui = require("dock.util.ui")
    local n  = tonumber(args[1])
    if not n then
        ui.notify_warning("jump needs a tab number")
        return
    end
    if not require("dock").panel():jump(n, { enter = true }) then
        ui.notify_warning("no tab " .. n)
    end
end

--- `clean` asks every source to shed what it no longer needs — `:Dock clean 3`
--- asks only the tab numbered 3. Each source answers for itself, so a tab whose
--- work is still going simply stays; nothing here overrides that.
_actions.clean = function(args)
    local n = args[1] and tonumber(args[1]) or nil
    if args[1] and not n then
        require("dock.util.ui").notify_warning("clean takes a tab number, or nothing")
        return
    end

    local cleaned = require("dock").clean(n)
    local ui      = require("dock.util.ui")
    if cleaned == 0 then
        ui.notify_info("nothing to clean")
    else
        ui.notify_info(("closed %d tab%s"):format(cleaned, cleaned == 1 and "" or "s"))
    end
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
            require("dock.util.ui").notify_warning("unknown subcommand: " .. sub)
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
