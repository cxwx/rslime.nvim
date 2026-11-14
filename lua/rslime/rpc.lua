-- Sentinel RPC over the REPL pty (the "poor man's swank"):
--   call: rslime_rpc("<id>", "<query>")   -> RSLIME <id> B ... RSLIME <id> E
--   eval: sandwich — the expression is run by the prompt itself, with
--         rslime_mark sentinels printed around its output
-- Answers are scraped from the terminal buffer; a request times out into nil.
local M = {}

local SENTINEL = "RSLIME"
local state = { injected = false, pending = nil, seq = 0 }

local function repl() return require("rslime.repl") end

---Escape a Lua string into a C string literal body (no quotes, single line)
function M.escape(query)
  return (query:gsub("[\\\r\n\t\"']", { ["\\"] = "\\\\", ["\r"] = " ", ["\n"] = " ", ["\t"] = " ", ['"'] = '\\"', ["'"] = "\\'" }))
end

---Load the C++ helper into the live session via `.L tempfile` (one line through
---the pty; typing 4KB line-by-line into the prompt takes seconds and races with
---pending requests). Direct chan_send: must not focus() the REPL window.
function M.inject()
  if state.injected then return end
  if not repl().is_running() then return end
  local path = vim.fn.stdpath("cache") .. "/rslime_helper.C"
  local f = io.open(path, "w")
  if not f then return end
  f:write(require("rslime.helper").code)
  f:close()
  pcall(vim.api.nvim_chan_send, repl().job_id(), ".L " .. path .. "\n")
  state.injected = true
end

---Kernel restarted: the helper is gone, pending requests will never answer
function M.reset()
  state.injected = false
  if state.pending then
    local cb = state.pending.cb
    state.pending = nil
    if cb then cb(nil) end
  end
end

local function scan(bufnr, id)
  if not vim.api.nvim_buf_is_valid(bufnr) then return nil end
  local n = vim.api.nvim_buf_line_count(bufnr)
  -- 4000-line tail: big answers (the variable panel lists every session global) must fit
  local lines = vim.api.nvim_buf_get_lines(bufnr, math.max(0, n - 4000), n, false)
  local bend, bstart
  for i = #lines, 1, -1 do
    local l = lines[i]
    if l == string.format("%s %s E", SENTINEL, id) then
      bend = i
    elseif bend and l == string.format("%s %s B", SENTINEL, id) then
      bstart = i
      break
    end
  end
  if not bend or not bstart then return nil end
  local out = {}
  for i = bstart + 1, bend - 1 do out[#out + 1] = lines[i] end
  return out
end

---Core ask loop: send_fn(id) writes to the pty; collect(lines) shapes the answer.
---One request in flight; a new one supersedes the old (old cb gets nil).
local function ask(send_fn, collect, cb, timeout_ms)
  if not repl().is_running() then return cb(nil) end
  M.inject()
  if state.pending and state.pending.cb then state.pending.cb(nil) end

  state.seq = state.seq + 1
  local id = tostring(state.seq)
  local req = { cb = cb, timer = nil }
  state.pending = req

  local bufnr = repl().bufnr()
  send_fn(id)

  local deadline = vim.uv.now() + (timeout_ms or 800)
  local function poll()
    if state.pending ~= req then return end
    local lines = scan(bufnr, id)
    if lines then
      state.pending = nil
      return cb(collect(lines))
    end
    if vim.uv.now() >= deadline then
      state.pending = nil
      -- timed out: most likely the helper never loaded (kernel restarted,
      -- .L failed) — force a re-inject on the next request
      state.injected = false
      return cb(nil)
    end
    req.timer = vim.defer_fn(poll, 40)
  end
  poll()
end

---Run a helper command in the session; cmd_fn(id) returns the line(s) to send
function M.request_cmd(cmd_fn, collect, cb, timeout_ms)
  ask(function(id)
    pcall(vim.api.nvim_chan_send, repl().job_id(), cmd_fn(id))
  end, collect or function(lines) return lines end, cb, timeout_ms)
end

---Completion/reflection query: rslime_rpc(id, "line before cursor")
function M.request(query, cb, timeout_ms)
  M.request_cmd(function(id)
    return string.format('rslime_rpc("%s", "%s")\n', id, M.escape(query))
  end, nil, cb, timeout_ms)
end

---Filter the sandwich window: keep value/error lines, drop echoed commands
function M.filter_eval_lines(lines, expr)
  local out, elen = {}, #expr
  for _, l in ipairs(lines) do
    -- blank lines, the expression's own echo (line ends with it) and the marker echoes
    if l ~= "" and not l:find("rslime_mark(", 1, true) and l:sub(-elen) ~= expr then
      out[#out + 1] = l
    end
  end
  return out
end

---Evaluate an expression by letting the prompt run it (error-safe: a typo is
---just an error line, never a crash — unlike TInterpreter::Evaluate).
function M.request_expr(expr, cb, timeout_ms)
  M.request_cmd(function(id)
    return string.format('rslime_mark("%s","B")\n%s\nrslime_mark("%s","E")\n', id, M.escape(expr), id)
  end, function(lines) return M.filter_eval_lines(lines, expr) end, cb, timeout_ms or 3000)
end

---name%K%detail -> { name = , kind = M/D/C/V/F/P, detail = }; junk lines dropped
function M.parse_lines(lines)
  local out = {}
  for _, l in ipairs(lines or {}) do
    local name, kind, detail = l:match("^([^%%]+)%%([MDCFVP])%%(.*)$")
    if name and name ~= "" then out[#out + 1] = { name = name, kind = kind, detail = detail } end
  end
  return out
end

return M
