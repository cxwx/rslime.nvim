local M = {}

---解析缓冲区中的 jupyter 风格 cell 分块
---返回 cell 列表：{ start = 起始代码行, stop = 结束代码行, header = 头行文本 }
---@param bufnr integer
---@param delimiter string lua pattern，如 "^%s*//%s*%%%%"
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

  -- 最后一个 cell 不延伸到文件末尾：末尾包裹结构的孤立 `}`（深度为负）排除出 cell
  -- cell 自身合法闭合的块（如 for 循环的 `}`）深度为 0，不受影响
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

---光标所在 cell（光标落在头行上也归属该 cell）
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
        -- 光标在上一 cell 末尾与本 cell 代码之间：头行则归属本 cell
        local header = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
        if header and header:match(delimiter) then
          -- 归属本 cell
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

---所有 cell 文本（按顺序）
---@param bufnr integer
---@param delimiter string
---@return string[]
function M.all_cell_texts(bufnr, delimiter)
  local texts = {}
  for _, c in ipairs(M.parse(bufnr, delimiter)) do
    local lines = vim.api.nvim_buf_get_lines(bufnr, c.start - 1, c.stop, false)
    table.insert(texts, table.concat(lines, "\n"))
  end
  return texts
end

return M
