local repl = require("rslime.repl")

local cmds = {
  RslimeStart = function() repl.start() end,
  RslimeToggle = function() repl.toggle() end,
  RslimeRestart = function() repl.restart() end,
  RslimeQuit = function() repl.quit() end,
  RslimeFocus = function() repl.focus() end,
  RslimeSendCell = function() repl.send_cell() end,
  RslimeSendLine = function() repl.send_line() end,
  RslimeSendFile = function() repl.send_file() end,
  RslimeRunAll = function() repl.send_all() end,
  RslimeRunBefore = function() repl.send_before() end,
  RslimeRunAfter = function() repl.send_after() end,
  RslimeEval = function() require("rslime.inspect").eval_cursor() end,
  RslimeVars = function() require("rslime.inspect").show_vars() end,
  RslimeHttp = function() repl.http_server() end,
  RslimeUndo = function(a) repl.undo(a.args ~= "" and tonumber(a.args) or 1) end,
}
for name, fn in pairs(cmds) do
  vim.api.nvim_create_user_command(name, fn, { nargs = name == "RslimeUndo" and "?" or 0 })
end

vim.api.nvim_create_user_command("RslimeSendSelection", function() repl.send_selection() end, { range = true })
vim.api.nvim_create_user_command("RslimeEvalVisual", function() require("rslime.inspect").eval_visual() end, { range = true })
