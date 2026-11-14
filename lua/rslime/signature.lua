-- 自动签名帮助: `(` 后自动弹活会话的重载原型（blink signature provider 背后）。
-- LSP 管缓冲区符号；会话符号（REPL 里造的对象、.L 进来的函数）LSP 不认识，
-- 本源兜底。查不到时返回 nil 弃权 —— blink 取第一个非空 provider 的结果。
local M = {}

local rpc = require("rslime.rpc")

---从光标前的文本提取: 最后一个未闭合 `(` 前的调用头 + 括号内已输入的第几个参数
---@param line string
---@param col0 integer 0-based 光标列（before = line:sub(1, col0) 已输入部分）
---@return string|nil head 调用头（`p->Fill` / `TH1F::Draw` / `func`）
---@return integer active_param 0-based
-- 常见控制关键字: `(` 后不该发起会话查询（省一次 RPC 往返）
local KEYWORDS = {
  ["for"] = true, ["if"] = true, ["while"] = true, ["switch"] = true,
  ["catch"] = true, ["return"] = true, ["sizeof"] = true, ["new"] = true,
  ["throw"] = true,
}

local function parse_context(line, col0)
  local before = line:sub(1, col0)
  local depth = 0
  for i = #before, 1, -1 do
    local c = before:sub(i, i)
    if c == ")" or c == "]" or c == "}" then
      depth = depth + 1
    elseif c == "(" or c == "[" or c == "{" then
      if depth == 0 and c == "(" then
        local head = vim.trim(before:sub(1, i - 1))
        -- 调用头必须以标识符字符结尾（`(a+b)(` 这种不是函数调用）
        if head == "" or not head:match("[%w_>]$") then return nil end
        if KEYWORDS[head] then return nil end
        local args = before:sub(i + 1)
        local d, p, j = 0, 0, 1
        while j <= #args do
          local a = args:sub(j, j)
          if a == "(" or a == "[" or a == "{" then d = d + 1
          elseif a == ")" or a == "]" or a == "}" then d = d - 1
          elseif a == "," and d == 0 then p = p + 1 end
          j = j + 1
        end
        return head, p
      end
      depth = depth - 1
    end
  end
  return nil
end

---blink provider 接口: 触发字符
function M.trigger_characters()
  return { trigger_characters = { "(" }, retrigger_characters = { ",", ")" } }
end

---blink provider 接口: 求 `(` 前调用头的活会话签名
---@param context table blink.cmp.SignatureHelpContext { line, pos }
---@param cb fun(help: lsp.SignatureHelp|nil) nil = 弃权
function M.get(context, cb)
  if not context or not context.line or not context.pos then return cb(nil) end
  local head, active_param = parse_context(context.line, context.pos[2])
  if not head then return cb(nil) end
  if not require("rslime.repl").is_running() then return cb(nil) end
  rpc.request_cmd(function(id)
    return string.format('rslime_sign("%s", "%s")\n', id, rpc.escape(head))
  end, nil, function(lines)
    local signatures = {}
    for _, c in ipairs(rpc.parse_lines(lines)) do
      if c.kind == "P" then
        local s = { label = c.name, activeParameter = active_param }
        if c.detail and c.detail ~= "" then
          s.documentation = { kind = "markdown", value = c.detail }
        end
        signatures[#signatures + 1] = s
      end
    end
    if #signatures == 0 then return cb(nil) end
    cb({
      signatures = signatures,
      activeSignature = 0,
      activeParameter = active_param,
    })
  end, 4000)
end

M._parse_context = parse_context  -- test hook

return M
