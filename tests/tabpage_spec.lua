local dock = require("dock")

---@return integer bufnr
local function scratch()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })
    return buf
end

--- Back to one tabpage with no groups. The panel is a singleton that outlives
--- any one test, so wipe it back to a known state rather than rebuilding it.
local function reset()
    for _, group in ipairs(dock.groups()) do group:remove() end
    dock.close({ all = true })
    vim.cmd("silent! tabonly")
end

---@param tab? integer
---@return integer?
local function shown(tab)
    local win = dock.panel():win(tab)
    return win and vim.api.nvim_win_get_buf(win) or nil
end

describe("dock across tabpages", function()
    local src

    before_each(function()
        reset()
        src = dock.source("tabspec")
    end)

    after_each(reset)

    it("shares one panel between tabpages", function()
        local panel = dock.panel()
        vim.cmd("tabnew")
        assert.are.equal(panel, dock.panel())
    end)

    it("shows the same groups in every tabpage", function()
        local group = src:group({ label = "build" })
        local buf   = scratch()
        group:page({ buf = buf })
        local first = vim.api.nvim_get_current_tabpage()

        vim.cmd("tabnew")
        assert.are.equal(1, #dock.groups())
        assert.are.equal(group, dock.groups()[1])

        -- a fresh view of the same panel, on the same page
        dock.open()
        assert.are.equal(buf, shown())
        assert.are.equal(buf, shown(first))
    end)

    it("opens and closes per tabpage without disturbing the others", function()
        src:group({ label = "build" }):page({ buf = scratch() })
        local first = vim.api.nvim_get_current_tabpage()

        vim.cmd("tabnew")
        assert.is_false(dock.panel():is_open())
        assert.is_true(dock.panel():is_open(first))

        dock.open()
        assert.is_true(dock.panel():is_open())

        dock.close()
        assert.is_false(dock.panel():is_open())
        assert.is_true(dock.panel():is_open(first))
        -- the tabs are untouched by hiding a window
        assert.are.equal(1, #dock.groups())
    end)

    it("closes every tabpage's dock with all = true", function()
        src:group({ label = "build" }):page({ buf = scratch() })
        local first = vim.api.nvim_get_current_tabpage()

        vim.cmd("tabnew")
        dock.open()
        dock.close({ all = true })

        assert.is_false(dock.panel():is_open())
        assert.is_false(dock.panel():is_open(first))
        assert.are.equal(1, #dock.groups())
    end)

    it("keeps every open dock on the same page", function()
        local group = src:group({ label = "build" })
        local a     = scratch()
        local b     = scratch()
        group:page({ buf = a, label = "out" })
        group:page({ buf = b, label = "err" })
        local first = vim.api.nvim_get_current_tabpage()

        vim.cmd("tabnew")
        dock.open()
        assert.are.equal(a, shown())

        -- jumping in one tabpage moves them all: one panel, one active page
        assert.is_true(dock.jump(3))
        assert.are.equal(b, shown())
        assert.are.equal(b, shown(first))
    end)

    it("shows a group added from another tabpage", function()
        src:group({ label = "one" }):page({ buf = scratch() })
        local first = vim.api.nvim_get_current_tabpage()

        vim.cmd("tabnew")
        dock.open()
        local buf = scratch()
        src:group({ label = "two" }):page({ buf = buf })

        assert.are.equal(2, #dock.groups())
        assert.are.equal(buf, shown())
        assert.are.equal(buf, shown(first))
    end)

    it("keeps the groups when a tabpage closes", function()
        local group = src:group({ label = "build" })
        local buf   = scratch()
        group:page({ buf = buf })

        vim.cmd("tabnew")
        dock.open()
        vim.cmd("tabclose")

        assert.is_false(group:is_removed())
        assert.are.equal(1, #dock.groups())
        assert.is_true(vim.api.nvim_buf_is_valid(buf))
        assert.are.equal(buf, shown())
    end)

    it("recovers every dock when the displayed buffer is deleted", function()
        local group = src:group({ label = "build" })
        local a     = scratch()
        local b     = scratch()
        group:page({ buf = a, label = "a" })
        group:page({ buf = b, label = "b" })
        local first = vim.api.nvim_get_current_tabpage()

        vim.cmd("tabnew")
        dock.open()
        assert.are.equal(a, shown())

        vim.api.nvim_buf_delete(a, { force = true })
        vim.wait(200, function() return dock.panel():is_open() end)
        assert.are.equal(b, shown())

        -- the other tabpage lost its window too; it comes back on re-entry
        vim.api.nvim_set_current_tabpage(first)
        vim.wait(200, function() return dock.panel():is_open() end)
        assert.is_true(dock.panel():is_open())
        assert.are.equal(b, shown())
    end)

    it("leaves no stray dock window behind on :wincmd T", function()
        local group = src:group({ label = "build" })
        local buf   = scratch()
        group:page({ buf = buf })
        local panel = dock.panel()

        vim.api.nvim_set_current_win(panel:win())
        -- `:wincmd T` is really "new window in a new tabpage, close this one":
        -- the dock goes with the window, and what lands over there is a plain
        -- window that happens to show the page buffer.
        vim.cmd("wincmd T")

        local moved = vim.api.nvim_get_current_win()
        assert.are.equal(0, vim.tbl_count(panel:wins()))
        assert.are.equal(buf, vim.api.nvim_win_get_buf(moved))
        assert.are.equal("", vim.wo[moved].winbar)
        assert.is_false(vim.wo[moved].winfixbuf)

        -- and the panel still has its tabs, ready to open here
        assert.are.equal(1, #dock.groups())
        dock.open()
        assert.is_true(panel:is_open())
        assert.are.equal(buf, shown())
    end)

    it("keeps one Shell tab across tabpages", function()
        local first = dock.shell()
        vim.cmd("stopinsert")

        vim.cmd("tabnew")
        local second = dock.shell()
        vim.cmd("stopinsert")

        assert.are.equal(first, second)
        assert.are.equal(1, #dock.groups())
        assert.are.equal(2, #first.pages)

        first:dispose()
        assert.are.equal(0, #dock.groups())
    end)
end)
