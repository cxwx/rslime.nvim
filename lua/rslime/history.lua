-- Session replay: record every user-sent code block (cells, lines, selections)
-- in order, so after a kernel restart the whole session can be rebuilt with
-- one key. RPC traffic (completion/eval/signature) is never recorded.
local M = {}

local history = {}
local MAX = 500

---@param text string
function M.record(text)
  if not text or text:match("^%s*$") then return end
  history[#history + 1] = text
  if #history > MAX then table.remove(history, 1) end
end

function M.get() return history end

function M.clear() history = {} end

---Re-send everything in order; cb(n) when done.
---@param delay_ms integer? pause between blocks (cling needs a beat to compile)
function M.replay(delay_ms, cb)
  local repl = require("rslime.repl")
  if #history == 0 then
    vim.notify("rslime: session history is empty", vim.log.levels.WARN)
    if cb then cb(0) end
    return
  end
  local texts = vim.list_slice(history)
  local i, n = 0, #texts
  local function next_block()
    i = i + 1
    if i > n then
      vim.notify(string.format("rslime: replayed %d blocks", n), vim.log.levels.INFO)
      if cb then cb(n) end
      return
    end
    repl.send(texts[i])
    vim.defer_fn(next_block, delay_ms or 250)
  end
  next_block()
end

return M
