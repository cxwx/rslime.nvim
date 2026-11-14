local M = {}

-- 解析缓冲区中的 jupyter 风格 cell 分块
-- delimiter 是 lua pattern，如 "^%s*//%s*%%%%" 匹配 "// %%" 头
-- 返回 cell 列表：{ start = 起始代码行, stop = 结束代码行, header = 头行文本 }

---@param bufnr integer
---@param delimiter string lua pattern
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
  -- 最后一个 cell：文件末尾包裹结构的孤立 `}`（如 main 的收尾，深度为负）不算进 cell
  -- 注意：cell 自身合法闭合的块（如 for 循环的 `}`）深度为 0，不受影响
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
        last.stop = last.stop - 1 -- 末尾空行无意义
      else
        break
      end
    end
  end

  -- 过滤空 cell（只有分隔头、没有代码的情况已由 start/stop 保证非负）
  local out = {}
  for _, c in ipairs(cells) do
    if c.stop >= c.start then table.insert(out, c) end
  end
  return out
end

---光标所在 cell（光标落在头行上也算该 cell）
---@param bufnr integer
---@param lnum integer 1-based 光标行
---@param delimiter string
---@return table|nil cell
---@return string|nil text
function M.cell_at(bufnr, lnum, delimiter)
  local cells = M.parse(bufnr, delimiter)
  for i, c in ipairs(cells) do
    if lnum <= c.stop then
      -- 光标在本 cell 代码之前（上一 cell 末尾之后）
      if lnum < c.start then
        local header = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
        if header and header:match(delimiter) then
          -- 光标在本 cell 头行上 → 属于本 cell
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
  -- 光标在最后一个 cell 之后
  if #cells > 0 then
    local c = cells[#cells]
    local lines = vim.api.nvim_buf_get_lines(bufnr, c.start - 1, c.stop, false)
    return c, table.concat(lines, "\n")
  end
  return nil, nil
end

---所有 cell 拼接（发送整个文件按 cell 逐段）
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
