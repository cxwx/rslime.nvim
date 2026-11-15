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

-- last rendered text per (buf, lnum): a re-run that produced a different answer
-- gets the Changed colour (borrowed from nvim-dap-virtual-text's NvimDapVirtualTextChanged)
local last_text = {}

-- buffers get wiped all the time; drop their last_text entries on unload
-- (registered on first use, not at require time — tests load this module raw)
local cleanup_registered = false
local function ensure_cleanup()
  if cleanup_registered then return end
  cleanup_registered = true
  vim.api.nvim_create_autocmd("BufUnload", {
    group = vim.api.nvim_create_augroup("RslimeInlineCleanup", { clear = true }),
    callback = function(args)
      local prefix = args.buf .. ":"
      for k in pairs(last_text) do
        if k:sub(1, #prefix) == prefix then last_text[k] = nil end
      end
    end,
  })
end

local function place(buf, lnum, text, changed)
  ensure_cleanup()
  M.clear_line(buf, lnum)
  local hl = changed and "RslimeInlineChanged" or "RslimeInline"
  vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
    virt_text = { { " 󰡎 " .. vim.trim(text), hl } },
    virt_text_pos = "eol",
  })
end

---Show `text` as eol virtual text on `lnum` (1-based); replaces a previous mark
---@return boolean shown (false: buffer/line gone — caller should float instead)
function M.show(bufnr, lnum, text)
  local buf = bufnr or 0
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  if lnum < 1 or lnum > vim.api.nvim_buf_line_count(buf) then return false end
  local key = buf .. ":" .. lnum
  local prev = last_text[key]
  last_text[key] = text
  place(buf, lnum, text, prev ~= nil and prev ~= text)
  return true
end

---Replace every mark in the buffer in one go (a re-run must not leave stale
---lines behind). `results` = { [lnum] = text }; marks absent from it are dropped.
---A line whose value changed since the last render gets the Changed colour.
---@param bufnr integer
---@param results table<integer, string>
function M.refresh(bufnr, results)
  local buf = bufnr or 0
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local prefix = buf .. ":"
  local prev = {}
  for k, v in pairs(last_text) do
    if k:sub(1, #prefix) == prefix then
      prev[k:sub(#prefix + 1)] = v
      last_text[k] = nil
    end
  end
  M.clear(buf)
  for lnum, text in pairs(results) do
    -- place() clears last_text for the line, so record after placing
    place(buf, lnum, text, prev[tostring(lnum)] ~= nil and prev[tostring(lnum)] ~= text)
    last_text[prefix .. lnum] = text
  end
end

---Remove this module's mark(s) on one line
function M.clear_line(bufnr, lnum)
  vim.api.nvim_buf_clear_namespace(bufnr or 0, ns, lnum - 1, lnum)
  last_text[(bufnr or 0) .. ":" .. lnum] = nil
end

---Remove every inline result in the buffer
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr or 0, ns, 0, -1)
  local prefix = (bufnr or 0) .. ":"
  for k in pairs(last_text) do
    if k:sub(1, #prefix) == prefix then last_text[k] = nil end
  end
end

return M
