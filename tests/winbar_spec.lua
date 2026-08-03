local winbar = require("dock.winbar")

local OPTS   = {
    separator  = "│",
    unread     = "•",
    numbers    = true,
    click      = "v:lua.__dock_click",
    empty_text = "No panels",
}

---@param spec table
---@return dock.winbar.Tab
local function tab(spec)
    return vim.tbl_extend("force", {
        num     = 1,
        label   = "build",
        icon    = "▶",
        icon_hl = "DockBadgeOk",
        active  = false,
        unread  = false,
        pages   = {},
    }, spec)
end

--- Visible width of a rendered winbar: strip the zero-width statusline escapes
--- (`%#Group#`, `%N@fn@`, `%X`) the same way Neovim does when it lays the bar out.
---@param s string
---@return integer
local function visible_width(s)
    local plain = s
        :gsub("%%#[^#]*#", "")
        :gsub("%%%d+@[^@]*@", "")
        :gsub("%%X", "")
    return vim.fn.strdisplaywidth(plain)
end

describe("winbar.build", function()
    it("renders a placeholder when there are no tabs", function()
        local out = winbar.build({}, 80, OPTS)
        assert.is_truthy(out:find("No panels", 1, true))
    end)

    it("numbers group tabs sequentially", function()
        local out = winbar.build({
            tab({ num = 1, label = "build" }),
            tab({ num = 2, label = "test" }),
        }, 80, OPTS)
        assert.is_truthy(out:find("1:build", 1, true))
        assert.is_truthy(out:find("2:test", 1, true))
    end)

    it("draws no glyph for a tab without a badge", function()
        local bare = tab({})
        bare.icon, bare.icon_hl = nil, nil
        local out = winbar.build({ bare }, 80, OPTS)
        assert.is_nil(out:find("▶", 1, true))
        assert.is_truthy(out:find("1:build", 1, true))
    end)

    it("omits numbers when disabled", function()
        local opts = vim.tbl_extend("force", OPTS, { numbers = false })
        local out  = winbar.build({ tab({ label = "build" }) }, 80, opts)
        assert.is_nil(out:find("1:build", 1, true))
        assert.is_truthy(out:find("build", 1, true))
    end)

    it("emits a click region per tab and per page", function()
        local out = winbar.build({
            tab({
                num   = 1,
                pages = {
                    { num = 2, label = "out", current = true,  unread = false },
                    { num = 3, label = "err", current = false, unread = false },
                },
            }),
        }, 80, OPTS)
        for _, n in ipairs({ 1, 2, 3 }) do
            assert.is_truthy(out:find("%" .. n .. "@v:lua.__dock_click@", 1, true))
        end
    end)

    it("marks unread pages", function()
        local out = winbar.build({
            tab({
                num   = 1,
                pages = {
                    { num = 2, label = "out", current = false, unread = true },
                    { num = 3, label = "err", current = true,  unread = false },
                },
            }),
        }, 80, OPTS)
        assert.is_truthy(out:find("DockUnread", 1, true))
    end)

    it("marks a single-page group on its own tab", function()
        local out = winbar.build({ tab({ unread = true }) }, 80, OPTS)
        assert.is_truthy(out:find("DockUnread", 1, true))
    end)

    it("highlights the active tab", function()
        local out = winbar.build({ tab({ active = true }) }, 80, OPTS)
        assert.is_truthy(out:find("DockActiveTab", 1, true))
    end)

    describe("overflow", function()
        it("crops to the available width", function()
            local tabs = {}
            for i = 1, 5 do
                tabs[i] = tab({ num = i, label = "a-very-long-group-label-" .. i })
            end
            local out = winbar.build(tabs, 80, OPTS)
            assert.is_true(visible_width(out) <= 80)
        end)

        it("stops cropping at a legible floor rather than erasing labels", function()
            -- With more tabs than columns the bar cannot fit; labels bottom out
            -- at two characters instead of vanishing, and Neovim truncates the
            -- tail. Documented so the floor stays deliberate.
            local tabs = {}
            for i = 1, 12 do
                tabs[i] = tab({ num = i, label = "group-label-" .. i })
            end
            local out = winbar.build(tabs, 40, OPTS)
            assert.is_truthy(out:find("1:g…", 1, true))
        end)

        it("counts page labels against the width budget", function()
            -- Page tabs carry visible text; if they were treated as zero-width
            -- escapes the bar would silently overflow the window.
            local pages = {}
            for i = 1, 6 do
                pages[i] = { num = i + 1, label = "page-label-" .. i, current = false, unread = false }
            end
            local out = winbar.build({ tab({ num = 1, pages = pages }) }, 50, OPTS)
            assert.is_true(visible_width(out) <= 50)
        end)

        it("takes columns from the longest label first", function()
            local out = winbar.build({
                tab({ num = 1, label = "ab" }),
                tab({ num = 2, label = string.rep("x", 60) }),
            }, 40, OPTS)
            -- the short label survives intact; the long one absorbs the overflow
            assert.is_truthy(out:find("1:ab", 1, true))
            assert.is_truthy(out:find("…", 1, true))
        end)

        it("leaves a fitting bar untouched", function()
            local out = winbar.build({ tab({ label = "build" }) }, 200, OPTS)
            assert.is_nil(out:find("…", 1, true))
        end)
    end)
end)
