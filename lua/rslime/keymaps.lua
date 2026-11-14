local M = {}

local function cmd(name) return "<cmd>" .. name .. "<cr>" end

local buf_actions = {
  { "n", "cell", "RslimeSendCell", "send cell" },
  { "n", "line", "RslimeSendLine", "send line" },
  { "n", "file", "RslimeSendFile", "send file" },
  { "n", "undo", "RslimeUndo", "cling undo" },
  { "n", "run_all", "RslimeRunAll", "run all cells" },
  { "x", "visual", nil, "send selection" }, -- 选区命令单独处理（range）
}

---给单个缓冲区注册发送类映射（suffix 为 false 不注册；"" 也合法）
---@param bufnr integer
---@param prefix string
---@param keys table
function M.apply_to_buf(bufnr, prefix, keys)
  keys = keys or {}
  for _, m in ipairs(buf_actions) do
    local mode, action, command, desc = m[1], m[2], m[3], m[4]
    local suffix = keys[action]
    if suffix ~= nil and suffix ~= false then
      local rhs = command and cmd(command) or ":<C-u>RslimeSendSelection<cr>"
      vim.keymap.set(mode, prefix .. suffix, rhs,
        { silent = true, buffer = bufnr, desc = "rslime " .. desc })
    end
  end
end

---按键映射：prefix + keys.<action> 拼接
---全局：start/toggle/restart/quit/focus；c/cpp 缓冲区：cell/line/visual/file/undo
---suffix 为 false 的 action 不注册；"" 表示空 suffix（prefix 单按即触发）
---@param cfg table 完整配置（含 prefix, keys）
function M.apply(cfg)
  local prefix = cfg.prefix
  local keys = cfg.keys or {}

  local global_actions = {
    start = "RslimeStart",
    toggle = "RslimeToggle",
    restart = "RslimeRestart",
    quit = "RslimeQuit",
    focus = "RslimeFocus",
    http = "RslimeHttp",
  }
  for action, command in pairs(global_actions) do
    local suffix = keys[action]
    if suffix ~= nil and suffix ~= false then
      vim.keymap.set("n", prefix .. suffix, cmd(command),
        { silent = true, desc = "rslime " .. action })
    end
  end

  -- 发送类映射只挂在 c/cpp 缓冲区
  local augroup = vim.api.nvim_create_augroup("RslimeKeymaps", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = { "c", "cpp" },
    callback = function(args)
      M.apply_to_buf(args.buf, prefix, keys)
    end,
  })
end

return M
