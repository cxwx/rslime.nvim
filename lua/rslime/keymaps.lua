local M = {}

local function cmd(name) return "<cmd>" .. name .. "<cr>" end

-- { mode, action, command, long desc, short desc }
local buf_actions = {
  { "n", "cell", "RslimeSendCell", "send cell", "󰅩 cell" },
  { "n", "line", "RslimeSendLine", "send line", "󰅩 line" },
  { "n", "file", "RslimeSendFile", "send file", "󰅩 file" },
  { "n", "undo", "RslimeUndo", "cling undo", "󰕌 undo" },
  { "n", "run_all", "RslimeRunAll", "run all cells", "󰒑 all" },
  { "n", "run_before", "RslimeRunBefore", "run cells before cursor", "󰖯 before" },
  { "n", "run_after", "RslimeRunAfter", "run cells from cursor", "󰖰 after" },
  { "n", "eval", "RslimeEval", "eval word in session", "󰡎 eval" },
  { "x", "eval", "RslimeEvalVisual", "eval selection in session", "󰡎 eval" },
  { "n", "vars", "RslimeVars", "session variables", "󰬹 vars" },
  { "x", "visual", nil, "send selection", "󰅩 visual" }, -- range command handled separately
}

---Register send mappings on a single buffer (suffix false disables; "" is a valid empty suffix)
---@param bufnr integer
---@param prefix string
---@param keys table
---@param short boolean? short which-key descriptions (icon + word, no "rslime " prefix)
function M.apply_to_buf(bufnr, prefix, keys, short)
  keys = keys or {}
  for _, m in ipairs(buf_actions) do
    local mode, action, command, desc, sdesc = m[1], m[2], m[3], m[4], m[5]
    local suffix = keys[action]
    if suffix ~= nil and suffix ~= false then
      local rhs
      if command then
        rhs = mode == "x" and ":<C-u>" .. command .. "<cr>" or cmd(command)
      else
        rhs = ":<C-u>RslimeSendSelection<cr>"
      end
      vim.keymap.set(mode, prefix .. suffix, rhs,
        { silent = true, buffer = bufnr, desc = short and sdesc or desc })
    end
  end
end

---Mappings are prefix + keys.<action>
---global: start/toggle/restart/quit/focus/http; c/cpp buffers: cell/line/visual/file/undo/run_all
---a suffix of false disables the action; "" means an empty suffix (prefix alone triggers)
---@param cfg table full config (prefix, keys)
function M.apply(cfg)
  local prefix = cfg.prefix
  local keys = cfg.keys or {}

  -- global: action -> { command, long desc, short desc }
  local global_actions = {
    start = { "RslimeStart", "start repl", "󰓩 start" },
    toggle = { "RslimeToggle", "toggle repl window", "󰑓 toggle" },
    restart = { "RslimeRestart", "restart kernel", "󰜉 restart" },
    quit = { "RslimeQuit", "quit repl", "󰗼 quit" },
    focus = { "RslimeFocus", "focus repl window", "󰁯 focus" },
    http = { "RslimeHttp", "THttpServer + browser", "󰖟 http" },
  }
  for action, m in pairs(global_actions) do
    local suffix = keys[action]
    if suffix ~= nil and suffix ~= false then
      vim.keymap.set("n", prefix .. suffix, cmd(m[1]),
        { silent = true, desc = cfg.short_desc and m[3] or "rslime " .. m[2] })
    end
  end

  -- send mappings are buffer-local to c/cpp files
  local short = cfg.short_desc
  local augroup = vim.api.nvim_create_augroup("RslimeKeymaps", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = { "c", "cpp" },
    callback = function(args)
      M.apply_to_buf(args.buf, prefix, keys, short)
    end,
  })
end

return M
