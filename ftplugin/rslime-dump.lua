-- rslime-dump: interactive Dump/Print panel (dap-float style)
-- Buffer is owned by rslime.inspect (b:rslime_expr / b:rslime_deref carry the query context)

vim.keymap.set("n", "q", "<cmd>close<cr>", { silent = true, buffer = 0, desc = "close panel" })
vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { silent = true, buffer = 0, desc = "close panel" })
-- r: refresh — Dump values are a snapshot; re-read live memory
vim.keymap.set("n", "r", function() require("rslime.inspect").refresh() end,
  { silent = true, buffer = 0, desc = "refresh dump" })
-- <CR> / double-click: step into the member under the cursor (dap trigger_actions analog)
vim.keymap.set("n", "<CR>", function() require("rslime.inspect").step_into() end,
  { silent = true, buffer = 0, desc = "step into member" })
vim.keymap.set("n", "<2-LeftMouse>", function() require("rslime.inspect").step_into() end,
  { silent = true, buffer = 0, desc = "step into member" })
