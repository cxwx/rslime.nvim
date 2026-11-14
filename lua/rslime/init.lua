local M = {}

local defaults = {
  -- ROOT 启动命令（也可加 --web=off 等）
  cmd = "root -l",
  -- repl 窗口位置："bottom" | "right"
  position = "bottom",
  width = 80,
  -- height = nil → 启动时取终端高度一半
  height = nil,
  -- 启动后发送到 repl 的 ROOT/cling 命令，如 { ".gitinfo", "gROOT->SetBatch(kFALSE);" }
  startup_cmds = {},
  -- cell 分隔头 pattern，默认匹配 "// %%"（行首可有空白）
  cell_delimiter = "^%s*//%s*%%%%",
  -- run_all_delay > 0：run all 时逐 cell 延迟发送（毫秒），便于观察每块输出
  run_all_delay = 0,
  -- THttpServer 端口（,r0h / RslimeHttp 启动，浏览器观察变量）
  http_port = 8080,
  -- 启动后自动打开浏览器
  http_open = true,
  -- 按键：prefix + keys.<action> 拼接；prefix = nil 时不注册任何映射
  -- 全局：start/toggle/restart/quit/focus；c/cpp 缓冲区：cell/line/visual/file/undo
  -- 某 action 的 suffix 设为 false 可单独禁用
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

  -- cell 分隔头高亮（c/cpp 缓冲区窗口局部 matchadd）
  vim.api.nvim_set_hl(0, "RslimeCellHeader", { link = "SpecialComment", default = true })
  local group = vim.api.nvim_create_augroup("RslimeHighlight", { clear = true })
  vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = group,
    pattern = { "c", "cpp" },
    callback = function(args)
      if vim.fn.bufwinid(args.buf) == -1 then return end
      vim.fn.clearmatches(vim.fn.bufwinid(args.buf))
      pcall(vim.fn.matchaddpos, "RslimeCellHeader", {}, 10, -1, { window = vim.fn.bufwinid(args.buf) })
      vim.fn.matchadd("RslimeCellHeader", M.config.cell_delimiter, 10, -1, { window = vim.fn.bufwinid(args.buf) })
    end,
  })

  if M.config.prefix then
    local keymaps = require("rslime.keymaps")
    keymaps.apply(M.config)
    -- ft 懒加载时 FileType 事件已过，给当前 c/cpp 缓冲区补注册发送类映射
    local ft = vim.bo.filetype
    if ft == "c" or ft == "cpp" then
      keymaps.apply_to_buf(vim.api.nvim_get_current_buf(), M.config.prefix, M.config.keys)
    end
  end
  return M.config
end

return M
