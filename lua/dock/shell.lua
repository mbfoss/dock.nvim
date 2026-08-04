local config = require("dock.config")
local term   = require("dock.util.term")
local ui     = require("dock.util.ui")

--- The one source dock ships itself: shells in a panel tab.
--- It is written against the public source/group API and nothing else, so it
--- doubles as the reference example for plugins embedding their own buffers.
---
--- Every shell is its own tab, labelled with the command it runs, so each one is
--- a single number away in the winbar.
---@class dock.shell
local M      = {}

-- A shell tab keeps the same neutral glyph whether its shell is running or has
-- exited — unlike a task, "finished" is not a result worth colouring. Only the
-- `busy` flag differs, which is what keeps a live shell out of bulk disposal.
local _BADGE_LIVE = { icon = "❯", hl = "DockBadgeMuted", busy = true }
local _BADGE_DEAD = { icon = "❯", hl = "DockBadgeMuted" }

local _source     = nil ---@type dock.Source?

---@return dock.Source
local function _get_source()
    if not _source then
        -- required lazily: dock/init.lua pulls this module in, so a top-level
        -- require here would be a cycle.
        _source = require("dock").source("shell")
    end
    return _source
end

---@return string|string[]
local function _default_cmd()
    if config.shell.cmd then return config.shell.cmd end
    -- The trailing `--` is a no-op argument that stops Neovim from tearing the
    -- terminal buffer down the moment the shell exits, so the scrollback stays
    -- readable in the tab. It is not part of the label.
    return { vim.o.shell, "--" }
end

---@return string?
local function _default_cwd()
    local cwd = config.shell.cwd
    if type(cwd) == "function" then return cwd() end
    return cwd
end

--- Page label for a command: the program's basename plus its arguments, so
--- `{ "git", "log" }` and `"echo 3"` read as `git log` and `echo 3`.
---@param cmd string|string[]
---@return string
local function _label(cmd)
    local words ---@type string[]
    if type(cmd) == "table" then
        words = cmd
    else
        words = vim.split(cmd, "%s+", { trimempty = true })
    end
    if #words == 0 then return "shell" end

    local out = { vim.fn.fnamemodify(words[1], ":t") }
    for i = 2, #words do out[#out + 1] = words[i] end
    return table.concat(out, " ")
end

--- A tab for one shell. `remove_when_empty` drops it when its terminal buffer
--- goes, so the tab never lingers without a shell behind it.
---@param label string
---@return dock.Group
local function _group(label)
    return _get_source():group({
        label             = label,
        badge             = _BADGE_LIVE,
        remove_when_empty = true,
        on_dispose        = function(g)
            for _, page in ipairs(vim.list_slice(g.pages)) do
                if vim.api.nvim_buf_is_valid(page.buf) then
                    pcall(vim.api.nvim_buf_delete, page.buf, { force = true })
                end
            end
        end,
    })
end

---@class dock.ShellOpts
---@field cmd?   string|string[]  defaults to config.shell.cmd, else 'shell'
---@field cwd?   string           defaults to config.shell.cwd
---@field label? string           tab label; defaults to the command
---@field env?   table<string,string>

--- Run a shell — or any command — as its own tab, focused and in insert mode.
---
--- The tab survives its command exiting, so the scrollback stays readable; it is
--- dropped when the terminal buffer is deleted, either by the user or by
--- disposing the tab.
---@param opts? dock.ShellOpts
---@return dock.Group?
function M.open(opts)
    opts = opts or {}

    local cmd   = opts.cmd or _default_cmd()
    -- Labelled off the requested command, not `cmd`: the default carries a `--`
    -- that is plumbing, not something worth reading in the tab bar.
    local label = opts.label or _label(opts.cmd or config.shell.cmd or vim.o.shell)

    local group ---@type dock.Group?  forward ref, captured by on_exit

    local handle, err = term.spawn(cmd, {
        cwd     = opts.cwd ~= nil and opts.cwd or _default_cwd(),
        env     = opts.env,
        on_exit = function()
            -- The tab stops being busy when its shell exits, which is what lets
            -- a bulk dispose sweep it up; the scrollback stays until then.
            if group and not group:is_removed() then
                group:set_badge(_BADGE_DEAD)
            end
        end,
    })
    if not handle then
        ui.notify_error("shell failed to start: " .. tostring(err))
        return nil
    end

    group = _group(label)
    group:page({ buf = handle.bufnr, label = label })
    group:activate({ buf = handle.bufnr, enter = true })
    vim.cmd("startinsert")

    return group
end

return M
