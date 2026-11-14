-- rootrepl: the live ROOT REPL terminal buffer (daprepl-style)
if vim.bo.buftype ~= "terminal" and not vim.fn.bufname():find("^term://") then return end

-- SIGINT to the kernel from normal mode (insert mode passes it raw already)
vim.keymap.set("n", "<C-c>", function()
  local repl = require("rslime.repl")
  if repl.job_id() then vim.api.nvim_chan_send(repl.job_id(), "\3") end
end, { silent = true, buffer = 0, desc = "rslime interrupt kernel" })

-- omnifunc completion fallback (C-x C-o); blink users get it automatically
-- via per_filetype = { rootrepl = { "rslime" } }
vim.bo[0].omnifunc = "v:lua.require'rslime.complete'.omnifunc"
