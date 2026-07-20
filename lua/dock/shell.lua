local config = require("dock.config")
local term   = require("dock.tk.term")
local ui     = require("dock.tk.ui")

--- The one source dock ships itself: an interactive shell in a panel tab.
--- It is written against the public source/group API and nothing else, so it
--- doubles as the reference example for plugins embedding their own buffers.
---@class dock.shell
local M      = {}

-- A shell tab keeps the same neutral glyph whether the shell is running or has
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
    -- readable in the tab.
    return { vim.o.shell, "--" }
end

---@return string?
local function _default_cwd()
    local cwd = config.shell.cwd
    if type(cwd) == "function" then return cwd() end
    return cwd
end

---@class dock.ShellOpts
---@field cmd?   string|string[]  defaults to config.shell.cmd, else 'shell'
---@field cwd?   string           defaults to config.shell.cwd
---@field label? string           tab label; defaults to the command's basename
---@field env?   table<string,string>

--- Open an interactive shell in its own panel tab, focused and in insert mode.
---
--- The tab survives the shell exiting — it is only dropped when its terminal
--- buffer is deleted, either by the user or by disposing the tab.
---@param opts? dock.ShellOpts
---@return dock.Group?
function M.open(opts)
    opts = opts or {}

    local cmd   = opts.cmd or _default_cmd()
    local label = opts.label
        or (type(cmd) == "table" and cmd[1] and vim.fn.fnamemodify(cmd[1], ":t"))
        or (type(cmd) == "string" and vim.fn.fnamemodify(vim.split(cmd, " ")[1], ":t"))
        or "shell"

    local group ---@type dock.Group?  forward ref, captured by on_exit

    local handle, err = term.spawn(cmd, {
        cwd     = opts.cwd ~= nil and opts.cwd or _default_cwd(),
        env     = opts.env,
        on_exit = function()
            if group and not group:is_removed() then
                group:set_badge(_BADGE_DEAD)
            end
        end,
    })
    if not handle then
        ui.notify_error("shell failed to start: " .. tostring(err))
        return nil
    end

    group = _get_source():group({
        label             = label,
        badge             = _BADGE_LIVE,
        -- the tab lives exactly as long as its terminal buffer does
        remove_when_empty = true,
        data              = { handle = handle },
        on_dispose        = function(g)
            local buf = g.data.handle.bufnr
            if vim.api.nvim_buf_is_valid(buf) then
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
            end
        end,
    })

    group:page({ buf = handle.bufnr, label = label })
    group:activate({ enter = true })
    vim.cmd("startinsert")

    return group
end

return M
