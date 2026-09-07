if vim.g.loaded_dock then return end
vim.g.loaded_dock = true

-- 'winfixbuf', which keeps the panel window pinned to the buffer dock puts
-- in it, landed in 0.10.
if vim.fn.has("nvim-0.10") ~= 1 then
    error("dock.nvim requires Neovim >= 0.10")
end

-- Registered up front so `:Dock` exists without the user calling setup();
-- the callback lazy-requires the rest of the plugin.
require("dock.commands").register()
