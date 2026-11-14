-- nvzone/menu (and similar) view over the command table — grouped, icon'd.
--   require("menu").open(require("rslime.menu").nvzone(), { mouse = true })
-- Groups keep the short_desc icon language; commands.lua stays the single
-- source of truth (descriptions come from there).
local M = {}

-- { group name, { { cmd, display }, ... } }
local layout = {
  { "󰓩 session", {
    { "RslimeStart",   "󰓩 start" },
    { "RslimeToggle",  "󰑓 toggle" },
    { "RslimeRestart", "󰜉 restart" },
    { "RslimeQuit",    "󰗼 quit" },
    { "RslimeFocus",   "󰁯 focus" },
    { "RslimeHttp",    "󰖟 http" },
  } },
  { "󰅩 send", {
    { "RslimeSendCell",      "󰅩 cell" },
    { "RslimeSendLine",      "󰅩 line" },
    { "RslimeSendSelection", "󰅩 visual" },
    { "RslimeSendFile",      "󰅩 file" },
  } },
  { "󰒑 run", {
    { "RslimeRunAll",    "󰒑 all" },
    { "RslimeRunBefore", "󰖯 before" },
    { "RslimeRunAfter",  "󰖰 after" },
    { "RslimeUndo",      "󰕌 undo" },
    { "RslimeReplay",    "󰒋 replay" },
  } },
  { "󰡎 inspect", {
    { "RslimeEval",       "󰡎 eval" },
    { "RslimeEvalVisual", "󰡎 eval visual" },
    { "RslimeSign",       "󰊕 sign" },
    { "RslimeHover",      "󰡎 hover" },
    { "RslimeVars",       "󰬹 vars" },
    { "RslimeInlineClear", "󰡎 clear" },
    { "RslimeDraw",        "󰓫 draw" },
  } },
}

---Grouped table in nvzone/menu format: { { name, items = { { name, cmd } } } }
function M.nvzone()
  local out = {}
  for _, g in ipairs(layout) do
    local items = {}
    for _, e in ipairs(g[2]) do
      items[#items + 1] = { name = e[2], cmd = e[1] }
    end
    out[#out + 1] = { name = g[1], items = items }
  end
  return out
end

return M
