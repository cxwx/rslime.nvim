-- run-block inline: after a cell runs, show the values of the variables it
-- assigns / declares as eol virtual text in that cell.
--
-- Scope is deliberately narrow: one block, short results only. `run all` and
-- `run before/after` never touch this (they sweep many cells — the marks would
-- churn and lag behind).
local M = {}

local CELL_TIMEOUT = 8000
local MAX_VARS = 12

---Variable names a cell introduces: `auto|Type name =`, `Type name(...)`,
---`Type* name`, `name =` (first assignment).
---@param text string cell source
---@return string[] unique names in source order
function M.names(text)
  local out, seen = {}, {}
  local function add(n)
    if n and not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    -- `auto x = ...` / `Type* x = ...`
    add(line:match("^%s*auto%s+([%a_][%w_]*)%s*="))
    add(line:match("^%s*[%a_][%w_]*[%s%*&]+([%a_][%w_]*)%s*="))
    -- `Type x(...)`
    add(line:match("^%s*[%a_][%w_]*[%s%*&]+([%a_][%w_]*)%s*%("))
    -- bare reassignment `x = ...`
    add(line:match("^%s*([%a_][%w_]*)%s*="))
  end
  return out
end

---Probe one cell's variables in the live session.
---@param bufnr integer source buffer
---@param cell table { start, stop } from cells.parse
---@param text string cell source
---@param cb fun(results: table<integer, string>|nil)
function M.run(bufnr, cell, text, cb)
  local names = M.names(text or "")
  if #names == 0 or not cell then return cb(nil) end
  local limited = vim.list_slice(names, 1, MAX_VARS)
  local inline = require("rslime.inline")
  local rpc = require("rslime.rpc")
  -- each name belongs to its own declaration line (first line mentioning it);
  -- a line already claimed by an earlier name is not stolen
  local src = vim.api.nvim_buf_get_lines(bufnr, cell.start - 1, cell.stop, false)
  local line_of, claimed = {}, {}
  for _, name in ipairs(limited) do
    for i, l in ipairs(src) do
      local lnum = cell.start + i - 1  -- 1-based buffer line
      if not claimed[lnum] and l:find("%f[%w_]" .. name .. "%f[^%w_]") then
        line_of[name] = lnum
        claimed[lnum] = true
        break
      end
    end
  end

  -- the rpc channel allows ONE request in flight (a new one supersedes the
  -- old), so probe serially: names in declaration order, one at a time
  local names = {}
  for _, n in ipairs(limited) do
    if line_of[n] then names[#names + 1] = n end
  end
  if #names == 0 then return cb(nil) end

  local results, failed = {}, false
  local i = 0
  local function next_probe()
    i = i + 1
    local name = names[i]
    if not name then
      if failed or not cb then return end
      local out = {}
      for lnum, text_ in pairs(results) do out[lnum] = text_ end
      return vim.schedule(function() cb(out) end)
    end
    rpc.request_expr(name, function(lines)
      if lines and inline.is_short(lines) and not lines[1]:find("^error") then
        results[line_of[name]] = vim.trim(lines[1])
      end
      next_probe()
    end, CELL_TIMEOUT)
  end
  next_probe()

  -- a stuck probe must not wedge the caller forever
  vim.defer_fn(function()
    if i < #names then failed = true; cb(nil) end
  end, (CELL_TIMEOUT + 500) * #names)
end

return M
