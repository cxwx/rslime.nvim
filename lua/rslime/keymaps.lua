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
  { "n", "sign", "RslimeSign", "signatures + docs", "󰊕 sign" },
  { "n", "vars", "RslimeVars", "session variables", "󰬹 vars" },
  { "n", "replay", "RslimeReplay", "replay session history", "󰒋 replay" },
  { "n", "hover", "RslimeHover", "live hover (Dump)", "󰡎 hover" },
  { "n", "inline_clear", "RslimeInlineClear", "clear inline evals", "󰡎 clear" },
  { "n", "draw", "RslimeDraw", "draw in session", "󰓫 draw" },
  { "n", "draw_same", nil, "draw same", "󰓫 same" }, -- ":RslimeDraw same"
  { "x", "visual", nil, "send selection", "󰅩 visual" }, -- range command handled separately
}

---Register send mappings (suffix false disables; "" is a valid empty suffix)
---@param bufnr integer|nil buffer-local when set; nil = global mappings
---@param prefix string
---@param keys table
---@param short boolean? short which-key descriptions (icon + word, no "rslime " prefix)
---@param opts table? extra cfg
function M.apply_to_buf(bufnr, prefix, keys, short, opts)
  keys = keys or {}
  for _, m in ipairs(buf_actions) do
    local mode, action, command, desc, sdesc = m[1], m[2], m[3], m[4], m[5]
    local suffix = keys[action]
    if suffix ~= nil and suffix ~= false then
      local rhs
      if command then
        rhs = mode == "x" and ":<C-u>" .. command .. "<cr>" or cmd(command)
      elseif action == "draw_same" then
        rhs = ":<C-u>RslimeDraw same<cr>"
      else
        rhs = ":<C-u>RslimeSendSelection<cr>"
      end
      vim.keymap.set(mode, prefix .. suffix, rhs,
        { silent = true, buffer = bufnr, desc = short and sdesc or desc })
    end
  end
end

---send-mapping scope (cfg.filetypes): a string / list of strings = only those filetypes
---@param ft string current 'filetype'
---@param filetypes string|table
---@return boolean
function M.ft_enabled(ft, filetypes)
  if type(filetypes) == "string" then return ft == filetypes end
  return vim.tbl_contains(filetypes, ft)
end

---Mappings are prefix + keys.<action>
---start/toggle/restart/quit/focus/http are global; send mappings follow cfg.filetypes:
---nil = set globally in one shot (no autocmd), a string/list = buffer-local via FileType
---a suffix of false disables the action; "" means an empty suffix (prefix alone triggers)
---@param cfg table full config (prefix, keys, filetypes)
function M.apply(cfg)
  local prefix = cfg.prefix
  local keys = cfg.keys or {}

  -- which-key hint: prefix alone is a no-op labeled "rslime", so the group pops open;
  -- an action with a "" suffix (prefix alone triggers it) overrides this below
  vim.keymap.set("n", prefix, "", { silent = true, desc = "rslime" })

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

  -- send mappings: filetypes nil = global one-shot set (no event overhead);
  -- a string/list = buffer-local, registered per FileType
  local short = cfg.short_desc
  local augroup = vim.api.nvim_create_augroup("RslimeKeymaps", { clear = true })
  if not cfg.filetypes then
    M.apply_to_buf(nil, prefix, keys, short, cfg)
  else
    vim.api.nvim_create_autocmd("FileType", {
      group = augroup,
      pattern = cfg.filetypes,
      callback = function(args)
        M.apply_to_buf(args.buf, prefix, keys, short, cfg)
      end,
    })
  end
end

return M
