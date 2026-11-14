-- P3 · REPL 报错回标: after a cell is sent, scan the REPL's new output for
-- cling error lines ("input_line_13:2:10: error: ...") and map them back onto
-- the source cell as vim diagnostics.
local M = {}

local ns = nil

local function ns_id()
  if not ns then ns = vim.api.nvim_create_namespace("rslime") end
  return ns
end

---Parse cling error lines out of raw REPL output.
---"input_line_13:2:10: error: msg" -> { line = 2, col = 10, message = "msg" }
---Lines without a location anchor to the cell start.
---@param lines string[] raw REPL output lines
---@return table[]
function M.parse_errors(lines)
  local out = {}
  for _, l in ipairs(lines or {}) do
    local ln, col, msg = l:match("^%S+:(%d+):(%d+): error: (.*)$")
    if msg then
      out[#out + 1] = { line = tonumber(ln) or 1, col = tonumber(col) or 1, message = msg }
    elseif l:match("^error:") then
      out[#out + 1] = { line = 1, col = 1, message = l:match("^error:%s*(.*)$") }
    end
  end
  return out
end

---Replace this plugin's diagnostics inside [from, to] (1-based, inclusive),
---keeping ours outside the range (other diagnostics are on other namespaces).
---@param bufnr integer
---@param from integer? 1-based line
---@param to integer?
---@param new table[] vim.diagnostic items (0-based lnum)
function M.set_range(bufnr, from, to, new)
  local keep = {}
  for _, d in ipairs(vim.diagnostic.get(bufnr, { namespace = ns_id() })) do
    local in_range = from and (d.lnum >= from - 1 and d.lnum <= (to or from) - 1)
    if not in_range then keep[#keep + 1] = d end
  end
  vim.list_extend(keep, new or {})
  vim.diagnostic.set(ns_id(), bufnr, keep)
end

---Capture errors for one sent cell: snapshot the REPL buffer, then a beat
---later parse what appeared and mark the source cell.
---@param srcbuf integer source buffer the cell came from
---@param cell table { start = , stop = } 1-based cell range
---@param delay_ms integer?
function M.capture(srcbuf, cell, delay_ms)
  local repl = require("rslime.repl")
  local rbuf = repl.bufnr()
  if not rbuf or not vim.api.nvim_buf_is_valid(srcbuf) then return end
  local before = vim.api.nvim_buf_line_count(rbuf)
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(rbuf) or not vim.api.nvim_buf_is_valid(srcbuf) then return end
    local lines = vim.api.nvim_buf_get_lines(rbuf, before, -1, false)
    local diags = {}
    for _, e in ipairs(M.parse_errors(lines)) do
      -- input_line numbering is relative to the sent block; clamp into the cell
      local lnum = cell.start - 1 + e.line
      if lnum > cell.stop - 1 then lnum = cell.start - 1 end
      diags[#diags + 1] = {
        lnum = lnum,
        col = math.max(0, e.col - 1),
        message = e.message,
        severity = vim.diagnostic.severity.ERROR,
        source = "rslime",
      }
    end
    M.set_range(srcbuf, cell.start, cell.stop, diags)
  end, delay_ms or 1800)
end

return M
