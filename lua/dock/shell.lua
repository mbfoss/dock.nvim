local config = require("dock.config")
local term   = require("dock.util.term")
local ui     = require("dock.util.ui")

--- The one source dock ships itself: shells in a panel tab.
--- It is written against the public source/group API and nothing else, so it
--- doubles as the reference example for plugins embedding their own buffers.
---
--- Every shell lands in the same "Shell" group, one page per shell, labelled
--- with the command it runs — so a handful of open shells cost one tab, not one
--- tab each.
---@class dock.shell
local M      = {}

-- A shell tab keeps the same neutral glyph whether its shells are running or
-- have exited — unlike a task, "finished" is not a result worth colouring. Only
-- the `busy` flag differs, which is what keeps a live shell out of bulk disposal.
local _BADGE_LIVE = { icon = "❯", hl = "DockBadgeMuted", busy = true }
local _BADGE_DEAD = { icon = "❯", hl = "DockBadgeMuted" }

local _GROUP_ID   = "shell"

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

--- The shared shell group, created on first use. `remove_when_empty` drops it
--- again once its last shell buffer goes, so the tab never lingers empty.
---@return dock.Group
local function _group()
    local group = _get_source():group({
        id                = _GROUP_ID,
        label             = "Shell",
        badge             = _BADGE_LIVE,
        remove_when_empty = true,
        data              = { shells = {} },
        on_dispose        = function(g)
            for _, page in ipairs(vim.list_slice(g.pages)) do
                if vim.api.nvim_buf_is_valid(page.buf) then
                    pcall(vim.api.nvim_buf_delete, page.buf, { force = true })
                end
            end
        end,
    })
    -- Reusing a group whose shells had all exited: it is live again.
    group:set_badge(_BADGE_LIVE)
    return group
end

--- The tab stays busy while any of its shells is still running, so a single
--- finished command never makes the whole tab look disposable.
---@param group dock.Group
local function _refresh_badge(group)
    if group:is_removed() then return end
    for buf, shell in pairs(group.data.shells) do
        if not vim.api.nvim_buf_is_valid(buf) then
            group.data.shells[buf] = nil
        elseif not shell.exited then
            return
        end
    end
    group:set_badge(_BADGE_DEAD)
end

---@class dock.ShellOpts
---@field cmd?   string|string[]  defaults to config.shell.cmd, else 'shell'
---@field cwd?   string           defaults to config.shell.cwd
---@field label? string           page label; defaults to the command
---@field env?   table<string,string>

--- Run a shell — or any command — as a page of the shared "Shell" tab, focused
--- and in insert mode.
---
--- The page survives its command exiting, so the scrollback stays readable; it
--- is dropped when the terminal buffer is deleted, either by the user or by
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
    local shell = { exited = false }

    local handle, err = term.spawn(cmd, {
        cwd     = opts.cwd ~= nil and opts.cwd or _default_cwd(),
        env     = opts.env,
        on_exit = function()
            shell.exited = true
            if group then _refresh_badge(group) end
        end,
    })
    if not handle then
        ui.notify_error("shell failed to start: " .. tostring(err))
        return nil
    end

    group                          = _group()
    group.data.shells              = group.data.shells or {}
    group.data.shells[handle.bufnr] = shell

    group:page({ buf = handle.bufnr, label = label })
    group:activate({ buf = handle.bufnr, enter = true })
    vim.cmd("startinsert")

    return group
end

return M
