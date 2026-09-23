---@brief Health check for dock.nvim - run with `:checkhealth dock`.
---
---Reports the Neovim version, the command `setup()` registered, and the
---options that differ from the defaults.

local M = {}

local health = vim.health

---Check the Neovim version against the plugin's minimum (see
---`plugin/dock.lua`). Silent on a supported version: a health check is for
---what is wrong, not for what is unremarkable.
local function _check_requirements()
    if vim.fn.has("nvim-0.10") ~= 1 then
        health.start("dock: requirements")
        health.error("dock.nvim requires Neovim >= 0.10")
    end
end

---`setup()` registers the command, under whatever `command` names, so its
---absence is how a missing (or deliberately disabled) `setup()` shows up.
local function _check_command()
    health.start("dock: command")

    local name = require("dock.config").current.command
    if not name or name == "" then
        health.info("`command` is unset, so no user command is registered")
    elseif vim.fn.exists(":" .. name) == 2 then
        health.ok((":%s is registered"):format(name))
    else
        health.warn((":%s is not registered"):format(name), {
            "require('dock').setup() has not been called yet",
        })
    end
end

---Options that are valid but have no default, so `defaults[key]` is nil for
---them and the unknown-key test below would otherwise call them misspellings.
local _OPTIONAL = {
    ["shell.cmd"] = true,
    ["shell.cwd"] = true,
}

---Collect the options whose value differs from the default, as flat paths with
---the value now in force. Lists are compared whole rather than descended into:
---a list-valued option is one option, not one option per element.
---@param current table
---@param defaults table
---@param prefix string  path of the enclosing table, "" at the top level
---@param out table[]
---@return table[]
local function _diff_config(current, defaults, prefix, out)
    for key, value in pairs(current) do
        local path = prefix .. tostring(key)
        local default = defaults[key]
        if type(value) == "table" and type(default) == "table" and not vim.islist(value) then
            _diff_config(value, default, path .. ".", out)
        elseif not vim.deep_equal(value, default) then
            table.insert(out, {
                path    = path,
                value   = vim.inspect(value, { newline = " ", indent = "" }),
                unknown = default == nil and not _OPTIONAL[path],
            })
        end
    end
    return out
end

---Report the options that differ from the defaults - the whole config would be
---mostly untouched defaults, and the point here is what this user changed.
---Anything set that the plugin does not define is flagged: `setup()` merges
---`opts` wholesale, so a misspelled option is kept silently.
local function _check_config()
    health.start("dock: configuration")

    local config = require("dock.config")
    local diffs  = _diff_config(config.current, config.defaults(), "", {})
    table.sort(diffs, function(a, b) return a.path < b.path end)

    if #diffs == 0 then
        health.ok("every option is at its default")
        return
    end

    local lines = {}
    for _, entry in ipairs(diffs) do
        table.insert(lines, ("  %s = %s"):format(entry.path, entry.value))
    end
    health.ok(("%d option%s differ%s from the defaults:\n%s")
        :format(#diffs, #diffs == 1 and "" or "s", #diffs == 1 and "s" or "",
            table.concat(lines, "\n")))

    for _, entry in ipairs(diffs) do
        if entry.unknown then
            health.warn(("`%s` is not an option dock defines"):format(entry.path), {
                "Check its spelling against the options listed in the README",
            })
        end
    end
end

function M.check()
    _check_requirements()
    _check_command()
    _check_config()
end

return M
