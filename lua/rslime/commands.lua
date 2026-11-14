-- Single source of truth for user commands: plugin/rslime.lua registers them
-- from this table, and menus/pickers can require it to build their own UI:
--   require("rslime.commands").all()
--   require("rslime.commands").menu()  -- {display, cmd, desc} for pickers
local M = {}

---@return table[] { cmd, desc, range?, nargs?, run }
function M.all()
  local repl = require("rslime.repl")
  local inspect = require("rslime.inspect")
  return {
    { cmd = "RslimeStart",        desc = "start the ROOT REPL",                  run = function() repl.start() end },
    { cmd = "RslimeToggle",       desc = "show/hide the REPL window",            run = function() repl.toggle() end },
    { cmd = "RslimeRestart",      desc = "restart the kernel",                   run = function() repl.restart() end },
    { cmd = "RslimeQuit",         desc = "quit the REPL",                        run = function() repl.quit() end },
    { cmd = "RslimeFocus",        desc = "jump to the REPL window",              run = function() repl.focus() end },
    { cmd = "RslimeHttp",         desc = "start THttpServer + browser",          run = function() repl.http_server() end },
    { cmd = "RslimeSendCell",     desc = "send the cell under cursor",           run = function() repl.send_cell() end },
    { cmd = "RslimeSendLine",     desc = "send the current line",                run = function() repl.send_line() end },
    { cmd = "RslimeSendSelection", desc = "send the visual selection", range = true, run = function() repl.send_selection() end },
    { cmd = "RslimeSendFile",     desc = "send the whole buffer",                run = function() repl.send_file() end },
    { cmd = "RslimeRunAll",       desc = "run all cells in order",               run = function() repl.send_all() end },
    { cmd = "RslimeRunBefore",    desc = "run cells before cursor",              run = function() repl.send_before() end },
    { cmd = "RslimeRunAfter",     desc = "run cells from cursor down",           run = function() repl.send_after() end },
    { cmd = "RslimeUndo",         desc = "roll back n cling transactions", nargs = "?", run = function(a) repl.undo(a.args ~= "" and tonumber(a.args) or 1) end },
    { cmd = "RslimeReplay",       desc = "re-send all blocks recorded this session", run = function() repl.replay() end },
    { cmd = "RslimeEval",         desc = "eval word under cursor in session",    run = function() inspect.eval_cursor() end },
    { cmd = "RslimeEvalVisual",   desc = "eval the visual selection", range = true, run = function() inspect.eval_visual() end },
    { cmd = "RslimeSign",         desc = "overload prototypes + docs",           run = function() inspect.show_signatures() end },
    { cmd = "RslimeHover",        desc = "live hover panel (Dump)",              run = function() inspect.hover() end },
    { cmd = "RslimeVars",         desc = "session variable panel",               run = function() inspect.show_vars() end },
  }
end

---Picker-friendly view: { display, cmd, desc }
function M.menu()
  local items = {}
  for _, c in ipairs(M.all()) do
    items[#items + 1] = { display = c.cmd, cmd = c.cmd, desc = c.desc }
  end
  return items
end

return M
