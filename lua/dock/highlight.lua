local M = {}

---@param name string
---@param attr "fg"|"bg"
---@return integer?
local function _get(name, attr)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
    return ok and hl[attr] or nil
end

--- Define the panel's highlight groups. All are `default = true`, so a user
--- colourscheme or an explicit `:highlight` always wins. Safe to call repeatedly;
--- re-run on ColorScheme so the derived (non-linked) groups follow the new theme.
function M.setup()
    vim.api.nvim_set_hl(0, "DockActiveTab", {
        fg      = _get("Title", "fg"),
        bg      = _get("WinBar", "bg"),
        bold    = true,
        default = true,
    })
    vim.api.nvim_set_hl(0, "DockBadgeOk", { link = "DiagnosticOk", default = true })
    vim.api.nvim_set_hl(0, "DockBadgeErr", { link = "DiagnosticError", default = true })
    vim.api.nvim_set_hl(0, "DockBadgeWarn", { link = "DiagnosticWarn", default = true })
    vim.api.nvim_set_hl(0, "DockBadgeHint", { link = "DiagnosticHint", default = true })
    vim.api.nvim_set_hl(0, "DockBadgeMuted", { link = "WinBar", default = true })
    vim.api.nvim_set_hl(0, "DockUnread", { link = "DiagnosticHint", default = true })
end

return M
