local ui = require("dock.util.ui")

local M = {}

---@class dock.util.TermHandle
---@field bufnr integer
---@field pid   integer
---@field stop  fun()  stop the spawned command

---@class dock.util.SpawnOpts
---@field bufname? string
---@field cwd?     string
---@field env?     table<string,string>
---@field on_exit? fun(code: integer)

---@param cmd  string|string[]
---@param opts dock.util.SpawnOpts
---@return integer? job_id, integer? pid, string? error
local function _start_job(cmd, opts)
    local job_id
    local exited

    local env = nil
    if opts.env and next(opts.env) then env = opts.env end
    if opts.cwd and vim.fn.has("win32") == 0 then
        env = env and vim.deepcopy(env) or {}
        env["PWD"] = opts.cwd
    end

    local start_ok, job_id_or_err = pcall(function()
        return vim.fn.jobstart(cmd, {
            term    = true,
            cwd     = opts.cwd,
            env     = env,
            on_exit = function(_, code)
                job_id = -1
                exited = true
                vim.schedule(function()
                    if opts.on_exit then opts.on_exit(code) end
                end)
            end,
        })
    end)

    if not start_ok then
        return nil, nil, tostring(job_id_or_err)
    end

    job_id = job_id_or_err
    if job_id < 0 then
        local program = type(cmd) == "table" and tostring(cmd[1]) or tostring(cmd)
        return nil, nil, "invalid command: " .. program
    end
    if job_id == 0 then
        return nil, nil, "invalid arguments"
    end

    local pid = 0
    if not exited then
        pid = vim.fn.jobpid(job_id)
    end
    return job_id, pid
end

--- Spawn a command in a terminal buffer.
--- Returns immediately with a handle, or nil plus an error message.
--- The terminal handles all output rendering, including ANSI colours.
---@param cmd    string|string[]
---@param opts   dock.util.SpawnOpts
---@param bufnr? integer  buffer to own the terminal (created automatically when nil)
---@return dock.util.TermHandle?, string?
function M.spawn(cmd, opts, bufnr)
    -- A terminal buffer must be in a window for jobstart {term=true}, so borrow a
    -- hidden full-editor float for the duration of the call.
    local own_buf
    if not bufnr then
        own_buf = true
        bufnr = vim.api.nvim_create_buf(false, true)
    end

    local spawn_win = ui.create_window(bufnr, false, {
        relative  = "editor",
        row       = 0,
        col       = 0,
        width     = vim.o.columns,
        height    = vim.o.lines,
        style     = "minimal",
        hide      = true,
        focusable = false,
        zindex    = 1,
    }, function() end)

    local saved_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(spawn_win)

    local job_id, job_pid, job_err = _start_job(cmd, opts)

    vim.api.nvim_set_current_win(saved_win)
    vim.api.nvim_win_close(spawn_win, true)

    if not job_id then
        if own_buf then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
        return nil, job_err
    end

    if own_buf then
        vim.bo[bufnr].buflisted = true
    end

    -- Once the job is gone the terminal contents are a dead scrollback; block the
    -- keys that would drop the user into insert mode on a buffer nothing reads.
    vim.api.nvim_create_autocmd("TermClose", {
        buffer   = bufnr,
        once     = true,
        callback = function()
            for _, key in ipairs({ "i", "a", "o", "I", "A", "O", "c", "cc", "C", "s", "S", "R", "." }) do
                vim.keymap.set("n", key, "<Nop>", { buffer = bufnr, nowait = true })
            end
            -- A user sitting in terminal mode when the job dies stays there,
            -- typing into nothing. Drop them into normal mode so the scrollback
            -- is immediately navigable. Scheduled: the mode cannot be changed
            -- from inside the TermClose callback itself.
            vim.schedule(function()
                if vim.api.nvim_get_current_buf() == bufnr
                    and vim.api.nvim_get_mode().mode:sub(1, 1) == "t" then
                    vim.cmd("stopinsert")
                end
            end)
        end,
    })

    if type(opts.bufname) == "string" and opts.bufname ~= "" then
        -- Renaming off `term://…` spins the old name into an unlisted alternate
        -- buffer; that alternate is `#` in this buffer's context, so we delete
        -- exactly it. Best-effort: on a name clash the rename no-ops and the
        -- term:// name is kept.
        if pcall(vim.api.nvim_buf_set_name, bufnr, opts.bufname) then
            vim.api.nvim_buf_call(bufnr, function()
                local alt = vim.fn.bufnr("#")
                if alt > 0 and alt ~= bufnr and not vim.api.nvim_buf_is_loaded(alt) then
                    pcall(vim.api.nvim_buf_delete, alt, { force = false })
                end
            end)
        end
    end

    return { ---@type dock.util.TermHandle
        bufnr = bufnr,
        pid   = job_pid or 0,
        stop  = function() vim.fn.jobstop(job_id) end,
    }
end

return M
