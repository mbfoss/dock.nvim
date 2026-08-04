local dock = require("dock")

---@return integer bufnr
local function scratch(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "hello" })
    return buf
end

--- The panel is a singleton that outlives any one test, so wipe it back to a
--- known state rather than rebuilding it.
local function reset()
    for _, group in ipairs(dock.groups()) do group:remove() end
    dock.close()
end

---@return dock.Panel
local function panel()
    return dock.panel()
end

--- Buffer currently displayed in this tabpage's dock window.
---@return integer?
local function shown()
    local win = panel():win()
    return win and vim.api.nvim_win_get_buf(win) or nil
end

describe("dock", function()
    local src

    before_each(function()
        reset()
        src = dock.source("spec")
    end)

    after_each(reset)

    describe("sources", function()
        it("returns the same handle for a name", function()
            assert.are.equal(dock.source("spec"), dock.source("spec"))
        end)

        it("reuses a group with the same id", function()
            local a = src:group({ id = "one", label = "one" })
            local b = src:group({ id = "one", label = "ignored" })
            assert.are.equal(a, b)
            assert.are.equal("one", a.label)
            assert.are.equal(1, #dock.groups())
        end)

        it("generates ids for anonymous groups", function()
            local a = src:group({ label = "a" })
            local b = src:group({ label = "b" })
            assert.are_not.equal(a.id, b.id)
            assert.are.equal(2, #dock.groups())
        end)

        it("scopes groups to their source", function()
            local other = dock.source("other")
            src:group({ label = "mine" })
            other:group({ label = "theirs" })
            assert.are.equal(1, #src:groups())
            assert.are.equal(1, #other:groups())
            assert.are.equal(2, #dock.groups())
            other:clear({ busy = true })
        end)
    end)

    describe("window", function()
        it("opens automatically when a group appears", function()
            assert.is_false(panel():is_open())
            src:group({ label = "build" })
            assert.is_true(panel():is_open())
        end)

        it("honours auto_open = false", function()
            src:group({ label = "build", auto_open = false })
            assert.is_false(panel():is_open())
        end)

        it("keeps groups across close and reopen", function()
            local group = src:group({ label = "build" })
            group:page({ buf = scratch() })
            dock.close()
            assert.is_false(panel():is_open())
            assert.are.equal(1, #dock.groups())

            dock.open()
            assert.is_true(panel():is_open())
            assert.are.equal(group.pages[1].buf, shown())
        end)

        it("shows a placeholder for a group with no pages", function()
            src:group({ label = "empty" })
            local buf = shown()
            assert.is_not_nil(buf)
            assert.are.equal("nofile", vim.bo[buf].buftype)
        end)
    end)

    describe("pages", function()
        it("displays a page as soon as it is added", function()
            local group = src:group({ label = "build" })
            local buf   = scratch()
            group:page({ buf = buf, label = "out" })
            assert.are.equal(buf, shown())
        end)

        it("ignores a duplicate buffer", function()
            local group = src:group({ label = "build" })
            local buf   = scratch()
            group:page({ buf = buf })
            group:page({ buf = buf })
            assert.are.equal(1, #group.pages)
        end)

        it("labels a page from its buffer name by default", function()
            local group = src:group({ label = "build" })
            local buf   = scratch()
            vim.api.nvim_buf_set_name(buf, "/tmp/dock-spec/output.log")
            local page = group:page({ buf = buf })
            assert.are.equal("output.log", page.label)
        end)

        it("advances to a higher-priority page", function()
            local group = src:group({ label = "build" })
            local low   = scratch()
            local high  = scratch()
            group:page({ buf = low, label = "out", priority = 0 })
            assert.are.equal(low, shown())
            group:page({ buf = high, label = "diag", priority = 10 })
            assert.are.equal(high, shown())
        end)

        it("stays put for a lower-priority page", function()
            local group = src:group({ label = "build" })
            local high  = scratch()
            local low   = scratch()
            group:page({ buf = high, label = "diag", priority = 10 })
            group:page({ buf = low, label = "out", priority = 0 })
            assert.are.equal(high, shown())
        end)

        it("switches to a lower-priority page when told to", function()
            local group = src:group({ label = "build" })
            local high  = scratch()
            local low   = scratch()
            group:page({ buf = high, priority = 10 })
            group:page({ buf = low, priority = 0, activate = true })
            assert.are.equal(low, shown())
        end)

        it("drops a page when its buffer is deleted", function()
            local group = src:group({ label = "build" })
            local a     = scratch()
            local b     = scratch()
            group:page({ buf = a, label = "a" })
            group:page({ buf = b, label = "b" })
            assert.are.equal(2, #group.pages)

            vim.api.nvim_buf_delete(a, { force = true })
            assert.are.equal(1, #group.pages)
        end)

        it("recovers the window when the displayed buffer is deleted", function()
            -- Neovim closes a window when the buffer it shows is deleted, and it
            -- does so before any autocmd can move the panel elsewhere.
            local group = src:group({ label = "build" })
            local a     = scratch()
            local b     = scratch()
            group:page({ buf = a, label = "a" })
            group:page({ buf = b, label = "b" })
            assert.are.equal(a, shown())

            vim.api.nvim_buf_delete(a, { force = true })
            vim.wait(200, function() return panel():is_open() end)

            assert.is_true(panel():is_open())
            assert.are.equal(b, shown())
        end)

        it("stays closed when the last tab's buffer is deleted", function()
            local group = src:group({ label = "only", remove_when_empty = true })
            local buf   = scratch()
            group:page({ buf = buf })

            vim.api.nvim_buf_delete(buf, { force = true })
            vim.wait(100, function() return panel():is_open() end)

            assert.is_false(panel():is_open())
            assert.are.equal(0, #dock.groups())
        end)

        it("never deletes a buffer on remove_page", function()
            local group = src:group({ label = "build" })
            local buf   = scratch()
            group:page({ buf = buf })
            group:remove_page(buf)
            assert.is_true(vim.api.nvim_buf_is_valid(buf))
        end)
    end)

    describe("focus policy", function()
        it("lets a new group take over by default", function()
            local first  = src:group({ label = "first" })
            local a      = scratch()
            first:page({ buf = a })

            local second = src:group({ label = "second" })
            local b      = scratch()
            second:page({ buf = b })
            assert.are.equal(b, shown())
        end)

        it("shows a focus = never group when nothing else is on screen", function()
            local only = src:group({ label = "only", focus = "never" })
            local buf  = scratch()
            only:page({ buf = buf })
            assert.are.equal(only, panel():active())
            assert.are.equal(buf, shown())
        end)

        it("keeps the view for focus = never", function()
            local first = src:group({ label = "first" })
            local a     = scratch()
            first:page({ buf = a })

            local dep   = src:group({ label = "dep", focus = "never" })
            dep:page({ buf = scratch() })
            assert.are.equal(a, shown())
        end)

        it("does not steal the view while the panel is focused", function()
            local first = src:group({ label = "first" })
            local a     = scratch()
            first:page({ buf = a })

            local prev  = vim.api.nvim_get_current_win()
            vim.api.nvim_set_current_win(panel():win())

            local second = src:group({ label = "second" })
            second:page({ buf = scratch() })
            assert.are.equal(a, shown())

            vim.api.nvim_set_current_win(prev)
        end)

        it("takes over even when focused for focus = always", function()
            local first = src:group({ label = "first" })
            first:page({ buf = scratch() })

            local prev = vim.api.nvim_get_current_win()
            vim.api.nvim_set_current_win(panel():win())

            local restarted = src:group({ label = "restarted", focus = "always" })
            local b         = scratch()
            restarted:page({ buf = b })
            assert.are.equal(b, shown())

            vim.api.nvim_set_current_win(prev)
        end)
    end)

    describe("navigation", function()
        it("numbers a single-page group with one number", function()
            local group = src:group({ label = "build" })
            group:page({ buf = scratch() })
            local _, targets = panel():_build_tabs()
            assert.are.equal(1, #targets)
        end)

        it("numbers a multi-page group per page and not the group", function()
            local group = src:group({ label = "build" })
            group:page({ buf = scratch(), label = "out" })
            group:page({ buf = scratch(), label = "err" })
            local tabs, targets = panel():_build_tabs()
            -- one per page; the group tab itself is not a target
            assert.are.equal(2, #targets)
            assert.is_nil(tabs[1].num)
        end)

        it("numbers pages from the group's own number", function()
            local one = src:group({ label = "one" })
            one:page({ buf = scratch() })

            local group = src:group({ label = "build" })
            local a     = scratch()
            local b     = scratch()
            group:page({ buf = a, label = "out" })
            group:page({ buf = b, label = "err" })

            -- tab 1 is the single-page group; this group's pages take 2 and 3
            assert.is_true(dock.jump(2))
            assert.are.equal(a, shown())
            assert.is_true(dock.jump(3))
            assert.are.equal(b, shown())
        end)

        it("jumps to a page by number", function()
            local group = src:group({ label = "build" })
            local a     = scratch()
            local b     = scratch()
            group:page({ buf = a, label = "out" })
            group:page({ buf = b, label = "err" })

            assert.is_true(dock.jump(1))
            assert.are.equal(a, shown())
            assert.is_true(dock.jump(2))
            assert.are.equal(b, shown())
        end)

        it("reports an out-of-range jump", function()
            src:group({ label = "build" }):page({ buf = scratch() })
            assert.is_false(dock.jump(99))
        end)

        it("cycles through tabs and wraps", function()
            local one = src:group({ label = "one" })
            one:page({ buf = scratch() })
            local two = src:group({ label = "two" })
            local b   = scratch()
            two:page({ buf = b })

            dock.jump(1)
            panel():cycle(1)
            assert.are.equal(b, shown())
            panel():cycle(1) -- wraps back to the first tab
            assert.are.equal(one.pages[1].buf, shown())
        end)
    end)

    describe("badges and disposal", function()
        it("takes busy from the caller's badge", function()
            local group = src:group({
                label = "build",
                badge = { icon = "▶", hl = "DockBadgeOk", busy = true },
            })
            assert.is_true(group:is_busy())
            group:set_badge({ icon = "✓", hl = "DockBadgeOk" })
            assert.is_false(group:is_busy())
        end)

        it("treats a group without a badge as idle", function()
            assert.is_false(src:group({ label = "plain" }):is_busy())
        end)

        it("excludes busy groups from disposable()", function()
            src:group({ label = "running", badge = { icon = "▶", hl = "DockBadgeOk", busy = true } })
            local done = src:group({ label = "done", badge = { icon = "✓", hl = "DockBadgeOk" } })
            local list = dock.disposable()
            assert.are.equal(1, #list)
            assert.are.equal(done, list[1])
        end)

        it("calls on_dispose so the source can free buffers", function()
            local buf    = scratch()
            local called = false
            local group  = src:group({
                label      = "build",
                on_dispose = function()
                    called = true
                    vim.api.nvim_buf_delete(buf, { force = true })
                end,
            })
            group:page({ buf = buf })
            group:dispose()

            assert.is_true(called)
            assert.is_true(group:is_removed())
            assert.is_false(vim.api.nvim_buf_is_valid(buf))
            assert.are.equal(0, #dock.groups())
        end)

        it("leaves buffers alone on remove()", function()
            local buf   = scratch()
            local group = src:group({ label = "build" })
            group:page({ buf = buf })
            group:remove()
            assert.is_true(vim.api.nvim_buf_is_valid(buf))
        end)

        it("removes a remove_when_empty group with its last page", function()
            local buf   = scratch()
            local group = src:group({ label = "shell", remove_when_empty = true })
            group:page({ buf = buf })
            assert.are.equal(1, #dock.groups())

            vim.api.nvim_buf_delete(buf, { force = true })
            assert.is_true(group:is_removed())
            assert.are.equal(0, #dock.groups())
        end)

        it("falls back to a neighbouring tab when the active one goes", function()
            local one = src:group({ label = "one" })
            local a   = scratch()
            one:page({ buf = a })
            local two = src:group({ label = "two" })
            two:page({ buf = scratch() })

            assert.are.equal(two, panel():active())
            two:remove()
            assert.are.equal(one, panel():active())
            assert.are.equal(a, shown())
        end)

        it("survives removing the last group", function()
            local group = src:group({ label = "only" })
            group:page({ buf = scratch() })
            group:remove()
            assert.is_nil(panel():active())
            assert.is_true(panel():is_open())
        end)
    end)

    describe("shell", function()
        it("opens a shell tab and drops it when the buffer goes", function()
            local group = dock.shell()
            assert.is_not_nil(group)
            assert.are.equal(1, #group.pages)

            local buf = group.pages[1].buf
            assert.are.equal("terminal", vim.bo[buf].buftype)
            assert.is_true(group:is_busy())

            vim.cmd("stopinsert")
            group:dispose()
            assert.is_true(group:is_removed())
            assert.is_false(vim.api.nvim_buf_is_valid(buf))
        end)

        it("gives every shell its own tab", function()
            local first  = dock.shell()
            local second = dock.shell()
            assert.are_not.equal(first, second)
            assert.are.equal(2, #dock.groups())
            assert.are.equal(1, #first.pages)
            assert.are.equal(1, #second.pages)

            vim.cmd("stopinsert")
            first:dispose()
            assert.are.equal(1, #dock.groups())
            second:dispose()
            assert.are.equal(0, #dock.groups())
        end)

        it("labels the tab with the command it runs", function()
            local group = dock.shell({ cmd = "echo 3" })
            assert.are.equal("echo 3", group.label)

            vim.cmd("stopinsert")
            group:dispose()
        end)

        it("numbers each shell tab on its own", function()
            local first  = dock.shell()
            local second = dock.shell()
            local _, targets = panel():_build_tabs()
            -- one number per shell: a single page each, so no bracketed list
            assert.are.equal(2, #targets)

            vim.cmd("stopinsert")
            first:dispose()
            second:dispose()
        end)
    end)
end)
