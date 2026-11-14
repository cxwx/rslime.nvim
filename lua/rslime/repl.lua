local M = {}

local state = {
  bufnr = nil,
  winid = nil,
  job_id = nil,
  restarting = false,
  http_started = nil,
}

local cfg = nil

function M._set_config(c) cfg = c end

local function is_running()
  return state.job_id ~= nil
    and vim.fn.jobwait({ state.job_id }, 0)[1] == -1
end

local function on_split_opened(bufnr)
  state.bufnr = bufnr
  state.winid = vim.fn.bufwinid(bufnr)
end

---Start the ROOT REPL
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
  local pos, size = cfg.position or "bottom", cfg.width or 80
  local split = pos == "bottom" and "botright split" or "botright vsplit"
  vim.cmd(split .. " | buffer " .. bufnr)
  if pos ~= "bottom" then
    vim.cmd("vertical resize " .. size)
  else
    vim.cmd("resize " .. (cfg.height or math.floor(vim.o.lines / 2)))
  end
  on_split_opened(bufnr)
  vim.cmd("wincmd p")

  -- termopen must run on the REPL buffer, otherwise it replaces the source file buffer
  vim.api.nvim_buf_call(bufnr, function()
    vim.fn.termopen(cfg.cmd, {
      cwd = vim.fn.getcwd(),
      -- LSP documentHighlight on a term:// buffer is rejected by clangd
      on_buf = function()
        vim.b[bufnr].snacks_words = false
      end,
      on_exit = function()
        state.job_id, state.winid, state.http_started = nil, state.winid, nil
        pcall(function() require("rslime.rpc").reset() end)
        local buf = state.bufnr
        state.bufnr = nil
        -- auto-close the terminal buffer instead of waiting on [Process exited 0]
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

  if #cfg.startup_cmds > 0 or cfg.completion ~= false then
    vim.defer_fn(function()
      for _, c in ipairs(cfg.startup_cmds) do M.send_raw(c .. "\n") end
      if cfg.completion ~= false then require("rslime.rpc").inject() end
    end, 800)
  end
end

---Send raw text (with newline); starts the REPL first if not running
function M.send_raw(text)
  if not is_running() then
    vim.notify("rslime: repl not running, starting...", vim.log.levels.WARN)
    M.start()
    vim.defer_fn(function()
      if state.job_id then pcall(vim.api.nvim_chan_send, state.job_id, text) end
    end, 1500)
    return
  end
  M.focus()
  pcall(vim.api.nvim_chan_send, state.job_id, text)
end

---Send a code block (cling evaluates line by line; multi-line blocks are written as a whole)
function M.send(code)
  M.send_raw(code .. "\n")
end

---Send the cell under the cursor
function M.send_cell()
  local bufnr = vim.api.nvim_get_current_buf()
  local _, text = require("rslime.cells").cell_at(bufnr, vim.fn.line("."), cfg.cell_delimiter)
  if not text or text:match("^%s*$") then
    vim.notify("rslime: no cell under cursor", vim.log.levels.WARN)
    return
  end
  M.send(text)
end

---Send the current line
function M.send_line()
  M.send(vim.fn.getline("."))
end

---Send the visual selection
function M.send_selection()
  local lines = vim.api.nvim_buf_get_lines(
    0, vim.fn.line("'<") - 1, vim.fn.line("'>"), false)
  M.send(table.concat(lines, "\n"))
end

---Send the whole buffer
function M.send_file()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  M.send(table.concat(lines, "\n"))
end

local function run_cell_texts(texts)
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

---Send all cells in order (wrapper structure is skipped; run_all_delay > 0 sends cell by cell)
function M.send_all()
  local texts = require("rslime.cells").all_cell_texts(
    vim.api.nvim_get_current_buf(), cfg.cell_delimiter)
  if #texts == 0 then
    vim.notify("rslime: no cells in buffer", vim.log.levels.WARN)
    return
  end
  run_cell_texts(texts)
end

---Run every cell strictly before the cursor's cell — re-run the setup part only
function M.send_before()
  local texts = require("rslime.cells").cell_texts_before(
    vim.api.nvim_get_current_buf(), vim.fn.line("."), cfg.cell_delimiter)
  if #texts == 0 then
    vim.notify("rslime: no cells before cursor", vim.log.levels.WARN)
    return
  end
  run_cell_texts(texts)
end

---Run the cursor's cell and every cell after it
function M.send_after()
  local texts = require("rslime.cells").cell_texts_after(
    vim.api.nvim_get_current_buf(), vim.fn.line("."), cfg.cell_delimiter)
  if #texts == 0 then
    vim.notify("rslime: no cells from cursor", vim.log.levels.WARN)
    return
  end
  run_cell_texts(texts)
end

---Restart the kernel: .q → gSystem->Exit(0) → jobstop
function M.restart()
  if not is_running() then M.start() return end
  state.restarting = true
  pcall(vim.api.nvim_chan_send, state.job_id, ".q\n")
  vim.defer_fn(function()
    if is_running() then
      pcall(vim.api.nvim_chan_send, state.job_id, "gSystem->Exit(0)\n")
    end
  end, 1000)
  vim.defer_fn(function()
    if is_running() then vim.fn.jobstop(state.job_id) end
  end, 2500)
end

---Quit the REPL (buffer closing is handled by on_exit)
function M.quit()
  state.restarting = false
  if is_running() then
    pcall(vim.api.nvim_chan_send, state.job_id, ".q\n")
    vim.defer_fn(function()
      if is_running() then vim.fn.jobstop(state.job_id) end
    end, 800)
  end
end

---Toggle the REPL window
function M.toggle()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)
    and vim.fn.bufwinid(state.bufnr) ~= -1 then
    vim.api.nvim_win_hide(vim.fn.bufwinid(state.bufnr))
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

---Jump to the REPL window (starts it first if not running)
function M.focus()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)
    and vim.fn.bufwinid(state.bufnr) ~= -1 then
    vim.api.nvim_set_current_win(vim.fn.bufwinid(state.bufnr))
  else
    M.start()
  end
end

---Send `.undo n` to roll back the last n cling transactions
function M.undo(n)
  M.send_raw(string.format(".undo %d\n", n or 1))
end

---Start ROOT's THttpServer (state resets when the kernel restarts)
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
  if cfg.http_open ~= false then
    vim.defer_fn(function()
      local url = "http://localhost:" .. port
      if vim.ui and vim.ui.open then
        pcall(vim.ui.open, url)
      else
        pcall(vim.cmd, string.format("silent! !open %q", url))
      end
    end, 500)
  end
end

function M.is_running() return is_running() end

---Channel accessors for the RPC layer
function M.job_id() return state.job_id end

function M.bufnr() return state.bufnr and (vim.api.nvim_buf_is_valid(state.bufnr) and state.bufnr or nil) or nil end

return M
