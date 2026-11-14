local M = {}

local defaults = {
  cmd = "root -l",
  position = "bottom", -- "bottom" | "right"
  width = 80,
  height = nil,        -- nil = 终端高度一半
  startup_cmds = {},   -- 启动后发送的 cling 命令
  cell_delimiter = "^%s*//%s*%%%%",
  run_all_delay = 0,   -- >0 时 run all 逐 cell 延迟发送（毫秒）
  http_port = 8080,
  http_open = true,    -- 启动 THttpServer 后自动打开浏览器
  -- 按键 = prefix + keys.<action> 拼接；prefix = nil 不注册任何映射
  -- 全局：start/toggle/restart/quit/focus/http；c/cpp 缓冲区：cell/line/visual/file/undo/run_all
  -- 某 action 的 suffix 设 false 可单独禁用
  prefix = nil,
  keys = {
    start = "s",
    toggle = "1",
    restart = "R",
    quit = "q",
    focus = "f",
    http = "h",
    cell = "k",
    line = "l",
    visual = "b",
    file = "F",
    undo = "u",
    run_all = "a",
  },
}

M.config = vim.deepcopy(defaults)

---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)

  local repl = require("rslime.repl")
  repl._set_config(M.config)

  -- cell 分隔头高亮（c/cpp 窗口局部）
  vim.api.nvim_set_hl(0, "RslimeCellHeader", { link = "SpecialComment", default = true })
  local group = vim.api.nvim_create_augroup("RslimeHighlight", { clear = true })
  vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = group,
    pattern = { "c", "cpp" },
    callback = function(args)
      local win = vim.fn.bufwinid(args.buf)
      if win == -1 then return end
      vim.fn.clearmatches(win)
      pcall(vim.fn.matchadd, "RslimeCellHeader", M.config.cell_delimiter, 10, -1, { window = win })
    end,
  })

  if M.config.prefix then
    local keymaps = require("rslime.keymaps")
    keymaps.apply(M.config)
    -- ft 懒加载时 FileType 事件已过，给当前 c/cpp 缓冲区补注册
    local ft = vim.bo.filetype
    if ft == "c" or ft == "cpp" then
      keymaps.apply_to_buf(vim.api.nvim_get_current_buf(), M.config.prefix, M.config.keys)
    end
  end
  return M.config
end

return M
