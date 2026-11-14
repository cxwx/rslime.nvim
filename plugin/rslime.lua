-- 命令注册
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
  RslimeHttp = function() repl.http_server() end,
  RslimeUndo = function(a) repl.undo(a.args ~= "" and tonumber(a.args) or 1) end,
}
for name, fn in pairs(cmds) do
  vim.api.nvim_create_user_command(name, fn, { nargs = name == "RslimeUndo" and "?" or 0 })
end

-- 选区命令（range）
vim.api.nvim_create_user_command("RslimeSendSelection", function() repl.send_selection(false) end, { range = true })
