-- P1 · 变量求值 / 变量面板: ask the live session, show the answer in a float.
-- Eval goes through the prompt itself (sandwich markers), so a bad expression
-- is just an error line in the float — the session never dies.
local M = {}
local repl = require("rslime.repl")
local rpc = require("rslime.rpc")

local function show(lines, title)
  if not lines or #lines == 0 then lines = { "(no output / timeout)" } end
  vim.schedule(function()
    vim.lsp.util.open_floating_preview(lines, "cpp",
      { border = "rounded", title = " " .. title .. " ", focusable = false })
  end)
end

-- Persistent hover panel (dap-float style): its own filetype `rslime-dump`,
-- ftplugin owns the keymaps, syntax owns the highlight.
local panel_win = nil

local function close_panel()
  if panel_win and vim.api.nvim_win_is_valid(panel_win) then
    vim.api.nvim_win_close(panel_win, true)
  end
  panel_win = nil
end

---@param lines string[]
---@param title string
---@param ctx table? { expr = string, deref = "->"|"."|nil } for refresh / step-into
local function show_panel(lines, title, ctx)
  close_panel()
  if not lines or #lines == 0 then lines = { "(no output / timeout)" } end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.b[buf].rslime_expr = ctx and ctx.expr or title
  vim.b[buf].rslime_deref = ctx and ctx.deref or nil
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.api.nvim_strwidth(l))
  end
  width = math.min(width + 2, math.floor(vim.o.columns * 0.85))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.7))
  panel_win = vim.api.nvim_open_win(buf, true, {  -- enter = true: cursor inside
    relative = "cursor", row = 1, col = 0,
    width = width, height = height,
    border = "rounded", style = "minimal",
    title = " " .. title .. " ", title_pos = "center",
  })
  vim.wo[panel_win].wrap = false  -- Dump columns stay aligned
  vim.wo[panel_win].spell = false
  vim.bo[buf].filetype = "rslime-dump"  -- ftplugin/syntax hook in (dap-float style)
end

local function running()
  if repl.is_running() then return true end
  vim.notify("rslime: repl not running", vim.log.levels.WARN)
  return false
end

---Evaluate a raw expression string in the live session, float the result
function M.eval_expr(expr)
  if not expr or expr == "" then return end
  if not running() then return end
  rpc.request_expr(expr, function(lines)
    show(lines, expr)
  end)
end

---Word under the cursor
function M.eval_cursor()
  local word = vim.fn.expand("<cword>")
  if word == "" then
    vim.notify("rslime: no identifier under cursor", vim.log.levels.WARN)
    return
  end
  M.eval_expr(word)
end

---Visual selection (joined to one line)
function M.eval_visual()
  local lines = vim.api.nvim_buf_get_lines(0, vim.fn.line("'<") - 1, vim.fn.line("'>"), false)
  M.eval_expr(vim.trim(table.concat(lines, " ")))
end

---Session hover for one word: eval it; pointer/object results are followed by
---Dump() (data members with live values — a bare pointer only shows an address);
---classes without Dump() (non-TObject) fall back to Print().
---@param word string
---@param cb fun(lines: string[])? test hook; default shows the panel
function M.hover_session(word, cb)
  if not running() then return end
  local ctx = { expr = word, deref = nil }
  local function present(lines)
    if cb then cb(lines) else show_panel(lines, word, ctx) end
  end
  rpc.request_expr(word, function(lines)
    local val = table.concat(lines, " ")
    local is_ptr = val:match("%s*%(%S+%s*%*%)") ~= nil
    local is_obj = val:match("%s*%(%S+%s*&%)") ~= nil
    if not (is_ptr or is_obj) then return present(lines) end
    local deref = is_ptr and "->" or "."
    ctx.deref = deref
    rpc.request_expr(word .. deref .. "Dump()", function(dump)
      local joined = table.concat(dump, " ")
      if joined:find("no member named 'Dump'", 1, true) then
        rpc.request_expr(word .. deref .. "Print()", function(pr)
          table.insert(pr, 1, val)
          present(pr)
        end)
      else
        table.insert(dump, 1, val)
        present(dump)
      end
    end)
  end)
end

---Panel actions called from ftplugin/rslime-dump.lua (dap trigger_actions analog)

---`r`: re-run the panel's expression — Dump values are a snapshot; refresh reads
---the live memory again
function M.refresh()
  local expr = vim.b.rslime_expr
  if expr then M.hover_session(expr) end
end

---`<CR>` on a member line: step into it — dump the child object
---("fXaxis  ->7fd...  X axis descriptor" → dump of p->fXaxis)
function M.step_into()
  local expr = vim.b.rslime_expr
  local deref = vim.b.rslime_deref
  if not expr or not deref then return end
  local member = vim.api.nvim_get_current_line():match("^([%w_]+)")
  if not member then return end
  M.hover_session(expr .. deref .. member)
end

---Live-session hover on the word under the cursor (,r0K).
---Deliberately NOT bound to K — the user's LSP hover keeps that key.
---Toggle: an open panel closes instead of re-querying.
function M.hover()
  if panel_win and vim.api.nvim_win_is_valid(panel_win) then
    return close_panel()
  end
  local word = vim.fn.expand("<cword>")
  if word == "" then
    return vim.notify("rslime: no identifier under cursor", vim.log.levels.WARN)
  end
  M.hover_session(word)
end

---Session variable panel: list globals with types, pick one to evaluate
function M.show_vars()
  if not running() then return end
  rpc.request_cmd(function(id)
    return string.format('rslime_vars("%s")\n', id)
  end, nil, function(lines)
    local vars = rpc.parse_lines(lines)
    if #vars == 0 then
      return vim.notify("rslime: no session globals", vim.log.levels.WARN)
    end
    local display = {}
    for _, v in ipairs(vars) do
      display[#display + 1] = string.format("%-28s %s", v.name, v.detail or "")
    end
    vim.ui.select(display, { prompt = "rslime · session variables" }, function(choice)
      if not choice then return end
      M.eval_expr(choice:match("^(%S+)"))
    end)
  end, 4000)
end

---Signatures + docs for the identifier (with head context) before the cursor.
---`hist.Dra` / `hist.Draw(` / `TH1F::Draw` all resolve through the live session.
function M.show_signatures()
  if not running() then return end
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col(".")
  local before = line:sub(1, col)
  -- strip a trailing partial word:  hist.Dra -> hist.  (ask for the whole name only)
  local head_ctx = before:gsub("[_a-zA-Z0-9]*$", "")
  local query = vim.trim(before)
  if query == "" then
    return vim.notify("rslime: nothing under cursor", vim.log.levels.WARN)
  end
  -- "obj." alone has no method name yet -> nothing to look up
  if head_ctx:find("[%.:>]%s*$") then
    return vim.notify("rslime: type the method name first", vim.log.levels.WARN)
  end
  rpc.request_cmd(function(id)
    return string.format('rslime_sign("%s", "%s")\n', id, rpc.escape(query))
  end, nil, function(lines)
    local out = {}
    for _, c in ipairs(rpc.parse_lines(lines)) do
      if c.kind == "P" then
        out[#out + 1] = c.name
        if c.detail and c.detail ~= "" then
          out[#out + 1] = "  -- " .. c.detail
        end
      elseif c.kind == "C" then
        out[#out + 1] = "class " .. c.name
        if c.detail and c.detail ~= "" then
          out[#out + 1] = "  -- " .. c.detail
        end
      end
    end
    if #out == 0 then
      out = { "no signature in session for: " .. query }
    end
    show(out, vim.trim(query))
  end, 4000)
end

return M
