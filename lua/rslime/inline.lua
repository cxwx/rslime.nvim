-- eval inline: short results as virtual text at the end of the line.
-- One mark per line — re-evaluating replaces it; RslimeInlineClear wipes the
-- buffer. Anything not "short" (multi-line / over-wide) never gets here: the
-- caller falls back to the preview float. Opt-in via cfg.inline_eval.
local M = {}

local ns = vim.api.nvim_create_namespace("rslime.inline")

-- inline only when the answer fits on one line under this width
local MAX_WIDTH = 80

---Does this result qualify as inline-able? (one line, not over-wide)
function M.is_short(lines)
  return lines ~= nil and #lines == 1
    and vim.api.nvim_strwidth(lines[1]) <= MAX_WIDTH
end

---Show `text` as eol virtual text on `lnum` (1-based); replaces a previous mark
---@return boolean shown (false: buffer/line gone — caller should float instead)
function M.show(bufnr, lnum, text)
  local buf = bufnr or 0
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  if lnum < 1 or lnum > vim.api.nvim_buf_line_count(buf) then return false end
  M.clear_line(buf, lnum)
  vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
    virt_text = { { " 󰡎 " .. vim.trim(text), "RslimeInline" } },
    virt_text_pos = "eol",
  })
  return true
end

---Remove this module's mark(s) on one line
function M.clear_line(bufnr, lnum)
  vim.api.nvim_buf_clear_namespace(bufnr or 0, ns, lnum - 1, lnum)
end

---Remove every inline result in the buffer
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr or 0, ns, 0, -1)
end

return M
