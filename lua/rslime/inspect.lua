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
