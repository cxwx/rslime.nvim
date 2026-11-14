local M = {}

local state = {
  bufnr = nil,   -- 终端缓冲区
  winid = nil,   -- 终端窗口
  job_id = nil,  -- job/chan id
  restarting = false,
}

local cfg = nil -- setup() 注入的配置

function M._set_config(c) cfg = c end

local function is_running()
  return state.job_id ~= nil
    and vim.fn.jobwait({ state.job_id }, 0)[1] == -1
end

local function on_split_opened(bufnr)
  state.bufnr = bufnr
  state.winid = vim.fn.bufwinid(bufnr)
end

---启动 ROOT repl
function M.start()
  if is_running() then
    vim.notify("rslime: repl already running", vim.log.levels.WARN)
    return
  end
  local bin = vim.fn.expandcmd(cfg.cmd:match("^%S+"))
  if vim.fn.executable(bin) == 0 then
    vim.notify(string.format("rslime: executable not found: %s", bin), vim.log.levels.ERROR)
    return
  end
  local bufnr = vim.api.nvim_create_buf(true, false)
  local pos, size = cfg.position or "right", cfg.width or 80
  local split = pos == "bottom" and "botright split" or "botright vsplit"
  vim.cmd(split .. " | buffer " .. bufnr)
  if pos ~= "bottom" then vim.cmd("vertical resize " .. size) else vim.cmd("resize " .. (cfg.height or math.floor(vim.o.lines / 2))) end
  on_split_opened(bufnr)
  vim.cmd("wincmd p")

  -- 必须在 REPL buffer 上启动 termopen（当前 buffer 已被 wincmd p 切回源文件，
  -- 直接 termopen 会把源文件 buffer 变成终端，内容被替换成 [No Name]）
  vim.api.nvim_buf_call(bufnr, function()
    vim.fn.termopen(cfg.cmd, {
    cwd = vim.fn.getcwd(),
    -- 屏蔽 snacks.words 等在此终端 buffer 上发 LSP documentHighlight（term:// URI 会被 clangd 拒绝）
    on_buf = function()
      vim.b[bufnr].snacks_words = false
    end,
    on_exit = function()
      state.job_id, state.winid, state.http_started = nil, state.winid, nil
      -- 任何退出都自动关闭终端 buffer，避免停在 [Process exited 0] 等按键
      local buf = state.bufnr
      state.bufnr = nil
      vim.defer_fn(function()
        if buf and vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end, 100)
      if state.restarting then
        state.restarting = false
        vim.defer_fn(function() M.start() end, 150)
      end
    end,
    })
  end)
  state.job_id = vim.bo[bufnr].channel

  -- 执行 startup_cmds（如 .gitinfo、gSystem 等）
  if #cfg.startup_cmds > 0 then
    vim.defer_fn(function()
      for _, c in ipairs(cfg.startup_cmds) do M.send_raw(c .. "\n") end
    end, 800)
  end
end

---向 repl 发送原始文本（含换行）
function M.send_raw(text)
  if not is_running() then
    vim.notify("rslime: repl not running, starting...", vim.log.levels.WARN)
    M.start()
    -- 启动后延迟再发
    vim.defer_fn(function()
      if state.job_id then pcall(vim.api.nvim_chan_send, state.job_id, text) end
    end, 1500)
    return
  end
  M.focus()
  pcall(vim.api.nvim_chan_send, state.job_id, text)
end

---发送代码块：ROOT/Cling 按行求值，多行块整体写入
function M.send(code)
  M.send_raw(code .. "\n")
end

---光标所在 cell
function M.send_cell()
  local bufnr = vim.api.nvim_get_current_buf()
  local _, text = require("rslime.cells").cell_at(bufnr, vim.fn.line("."), cfg.cell_delimiter)
  if not text or text:match("^%s*$") then
    vim.notify("rslime: no cell under cursor", vim.log.levels.WARN)
    return
  end
  M.send(text)
end

---当前行
function M.send_line()
  M.send(vim.fn.getline("."))
end

---可视选区
---@param use_last boolean true 时用上次选区（'<,'>）
function M.send_selection(use_last)
  local start_mark, end_mark = use_last and "'<" or "'<", use_last and "'>" or "'>"
  local lines = vim.api.nvim_buf_get_lines(
    0, vim.fn.line(start_mark) - 1, vim.fn.line(end_mark), false)
  M.send(table.concat(lines, "\n"))
end

---整个 buffer
function M.send_file()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  M.send(table.concat(lines, "\n"))
end

---按顺序发送所有 cell（cling 流式求值；cell 外的头文件/main 等包裹结构自动跳过）
---run_all_delay > 0 时逐 cell 延迟发送（便于观察每块输出），否则一次性写入
function M.send_all()
  local texts = require("rslime.cells").all_cell_texts(
    vim.api.nvim_get_current_buf(), cfg.cell_delimiter)
  if #texts == 0 then
    vim.notify("rslime: no cells in buffer", vim.log.levels.WARN)
    return
  end
  local delay = cfg.run_all_delay or 0
  if delay <= 0 then
    M.send(table.concat(texts, "\n"))
    return
  end
  local i = 0
  local function next_cell()
    i = i + 1
    if texts[i] then
      M.send(texts[i])
      vim.defer_fn(next_cell, delay)
    end
  end
  next_cell()
end

---重启 kernel：.q → gSystem->Exit(0) → 强杀，三级退出
function M.restart()
  if not is_running() then M.start() return end
  state.restarting = true
  -- 温和退出
  pcall(vim.api.nvim_chan_send, state.job_id, ".q\n")
  -- 1s 后仍活着（cling 忙/析构慢）→ 直接调 exit
  vim.defer_fn(function()
    if is_running() then
      pcall(vim.api.nvim_chan_send, state.job_id, "gSystem->Exit(0)\n")
    end
  end, 1000)
  -- 2.5s 后仍活着 → 强杀
  vim.defer_fn(function()
    if is_running() then vim.fn.jobstop(state.job_id) end
  end, 2500)
end

---退出 repl
function M.quit()
  state.restarting = false
  if is_running() then
    pcall(vim.api.nvim_chan_send, state.job_id, ".q\n")
    vim.defer_fn(function()
      if is_running() then vim.fn.jobstop(state.job_id) end
    end, 800)
  end
  -- buffer 关闭统一由 on_exit 处理
end

---切换显示/隐藏
function M.toggle()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)
    and vim.fn.bufwinid(state.bufnr) ~= -1 then
    -- 隐藏
    local win = vim.fn.bufwinid(state.bufnr)
    vim.api.nvim_win_hide(win)
  elseif state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    local pos = cfg.position or "bottom"
    if pos == "bottom" then
      vim.cmd("botright split | buffer " .. state.bufnr)
      vim.cmd("resize " .. (cfg.height or math.floor(vim.o.lines / 2)))
    else
      vim.cmd("botright vsplit | buffer " .. state.bufnr)
      vim.cmd("vertical resize " .. (cfg.width or 80))
    end
    vim.cmd("wincmd p")
  else
    M.start()
  end
end

---焦点跳到 repl 窗口
function M.focus()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)
    and vim.fn.bufwinid(state.bufnr) ~= -1 then
    vim.api.nvim_set_current_win(vim.fn.bufwinid(state.bufnr))
  else
    M.start()
  end
end

---发送 .undo n 撤销最近 n 条 cling 语句
function M.undo(n)
  M.send_raw(string.format(".undo %d\n", n or 1))
end

---在 REPL 里启动 ROOT 的 THttpServer，后台浏览器观察变量
---同一内核会话内重复按键不重复创建（重启内核后状态复位）
function M.http_server(port)
  if state.http_started then
    vim.notify("rslime: THttpServer already started (http://localhost:"
      .. (cfg.http_port or 8080) .. ")", vim.log.levels.INFO)
    return
  end
  port = port or cfg.http_port or 8080
  M.send(string.format('THttpServer *serv = new THttpServer("http:%d");', port))
  state.http_started = true
  vim.notify("rslime: THttpServer → http://localhost:" .. port, vim.log.levels.INFO)
  -- 默认自动打开浏览器（http_open = false 关闭）
  if cfg.http_open ~= false then
    vim.defer_fn(function()
      local url = "http://localhost:" .. port
      if vim.ui and vim.ui.open then
        pcall(vim.ui.open, url)
      else
        pcall(vim.cmd, string.format("silent! !open %q", url)) -- macOS 兜底
      end
    end, 500)
  end
end

function M.is_running() return is_running() end

return M
