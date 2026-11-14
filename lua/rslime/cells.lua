local M = {}

---Parse jupyter-style cells in a buffer
---Returns a list: { start = first code line, stop = last code line, header = header line }
---@param bufnr integer
---@param delimiter string lua pattern, e.g. "^%s*//%s*%%%%"
---@return table[] cells
function M.parse(bufnr, delimiter)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cells = {}
  local cur = nil
  for i, line in ipairs(lines) do
    if line:match(delimiter) then
      if cur then
        cur.stop = i - 1
        table.insert(cells, cur)
      end
      cur = { start = i + 1, header = line }
    end
  end
  if cur then
    cur.stop = #lines
    table.insert(cells, cur)
  end

  -- the last cell must not reach EOF: a dangling closing `}` from the wrapper
  -- (negative brace depth) is excluded; properly closed blocks (depth 0) stay intact
  local last = cells[#cells]
  if last then
    local depth = 0
    for i = last.start, #lines do
      for ch in lines[i]:gmatch("[{}]") do
        depth = depth + (ch == "{" and 1 or -1)
      end
    end
    while last.stop >= last.start do
      local l = lines[last.stop]
      if depth < 0 and l:match("^%s*}%s*;?%s*$") then
        last.stop = last.stop - 1
        depth = depth + 1
      elseif l:match("^%s*$") then
        last.stop = last.stop - 1
      else
        break
      end
    end
  end

  local out = {}
  for _, c in ipairs(cells) do
    if c.stop >= c.start then table.insert(out, c) end
  end
  return out
end

---Cell under the cursor (a header line belongs to its own cell)
---@param bufnr integer
---@param lnum integer
---@param delimiter string
---@return table|nil cell
---@return string|nil text
function M.cell_at(bufnr, lnum, delimiter)
  local cells = M.parse(bufnr, delimiter)
  for i, c in ipairs(cells) do
    if lnum <= c.stop then
      if lnum < c.start then
        -- cursor between the previous cell and this cell's code: a header line belongs to this cell
        local header = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
        if header and header:match(delimiter) then
          -- belongs to this cell
        elseif i > 1 then
          c = cells[i - 1]
        else
          return nil, nil
        end
      end
      local lines = vim.api.nvim_buf_get_lines(bufnr, c.start - 1, c.stop, false)
      return c, table.concat(lines, "\n")
    end
  end
  if #cells > 0 then
    local c = cells[#cells]
    local lines = vim.api.nvim_buf_get_lines(bufnr, c.start - 1, c.stop, false)
    return c, table.concat(lines, "\n")
  end
  return nil, nil
end

local function cell_text(bufnr, c)
  local lines = vim.api.nvim_buf_get_lines(bufnr, c.start - 1, c.stop, false)
  return table.concat(lines, "\n")
end

---All cell texts in order
---@param bufnr integer
---@param delimiter string
---@return string[]
function M.all_cell_texts(bufnr, delimiter)
  local texts = {}
  for _, c in ipairs(M.parse(bufnr, delimiter)) do
    table.insert(texts, cell_text(bufnr, c))
  end
  return texts
end

---Cell texts strictly before the cursor's cell (cursor on a header counts as that cell)
---@param bufnr integer
---@param lnum integer cursor line
---@param delimiter string
---@return string[]
function M.cell_texts_before(bufnr, lnum, delimiter)
  local cur = M.cell_at(bufnr, lnum, delimiter)
  if not cur then return {} end
  local texts = {}
  for _, c in ipairs(M.parse(bufnr, delimiter)) do
    if c.stop < cur.start then table.insert(texts, cell_text(bufnr, c)) end
  end
  return texts
end

---Cell texts from the cursor's cell to the end (inclusive)
---@param bufnr integer
---@param lnum integer cursor line
---@param delimiter string
---@return string[]
function M.cell_texts_after(bufnr, lnum, delimiter)
  local cur = M.cell_at(bufnr, lnum, delimiter)
  if not cur then return {} end
  local texts = {}
  for _, c in ipairs(M.parse(bufnr, delimiter)) do
    if c.start >= cur.start then table.insert(texts, cell_text(bufnr, c)) end
  end
  return texts
end

return M
