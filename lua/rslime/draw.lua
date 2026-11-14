-- 会话内画图: 光标对象 -> Draw() -> web canvas 自动开浏览器。
-- 类型感知: 先 eval 拿类名, 再用反射查 Draw 重载 —— 无参可调直接画;
-- TTree 这类必填参数的弹输入框; 没有 Draw 方法的提前 notify, 不污染会话。
-- 画完补 Modified+Update: 标脏 + 推送 web canvas（与 Draw 同一个 cling 事务）。
local M = {}

local rpc = require("rslime.rpc")

---原型是否"无参可调": 空参数表, 或每个参数都带默认值
---`void TH1::Draw(Option_t* option = "")` -> true; `TTree::Draw(const char*, ...)` -> false
local function callable_no_args(proto)
  local args = proto:match("%((.*)%)")
  if not args or vim.trim(args) == "" then return true end
  local depth = 0
  local pieces = { "" }
  for c in args:gmatch(".") do
    if c == "(" or c == "[" or c == "<" then depth = depth + 1
    elseif c == ")" or c == "]" or c == ">" then depth = depth - 1 end
    if c == "," and depth == 0 then pieces[#pieces + 1] = "" else pieces[#pieces] = pieces[#pieces] .. c end
  end
  for _, p in ipairs(pieces) do
    if not p:find("=") then return false end
  end
  return true
end

---Draw 需要必填参数时的提示语前缀（TTree 画表达式最有代表性）
local ARG_HINT = {
  TTree = "x:y>>h(50,0,10)", TChain = "x", TNtuple = "x:y", TNtupleD = "x:y",
}

local function send_line(text)
  require("rslime.repl").send(text)
end

local function emit(expr, deref, option)
  local opt = option and option ~= "" and ('"' .. option .. '"') or ""
  -- 与 Draw 同一事务: 一个 cling 事务完成画+标脏+推送
  send_line(string.format(
    "%s%sDraw(%s); if (gPad) { gPad->Modified(); gPad->Update(); }", expr, deref, opt))
  require("rslime.history").record(string.format("%s%sDraw(%s)", expr, deref, opt))
end

---@param option string? Draw option ("" / "same" / "COLZ" ...), 命令行可传
function M.draw(option)
  local repl = require("rslime.repl")
  if not repl.is_running() then
    return vim.notify("rslime: repl not running", vim.log.levels.WARN)
  end
  local word = vim.fn.expand("<cword>")
  if word == "" then
    return vim.notify("rslime: no identifier under cursor", vim.log.levels.WARN)
  end
  -- 1) 类型: eval -> "(TH1F *)" / "(TH1F&)"
  rpc.request_expr(word, function(lines)
    local val = lines and lines[1] or ""
    local class = val:match("%((%S+)%s*[%*&]") or val:match("%((class%s+%S+)%s*[%*&]")
    -- 指针 -> 箭头, 对象 -> 点: eval 结果里的 * / & 已经说明了解引用方式
    local deref = val:find("*") and "->" or "."
    if not class then
      return vim.notify("rslime: cannot draw [" .. word .. "] — not an object ("
        .. val:sub(1, 60) .. ")", vim.log.levels.WARN)
    end
    -- 2) 反射查 Draw 重载
    rpc.request_cmd(function(id)
      return string.format('rslime_sign("%s", "%s::Draw")\n', id, rpc.escape(class))
    end, nil, function(slines)
      local protos = {}
      for _, c in ipairs(rpc.parse_lines(slines)) do
        if c.kind == "P" then protos[#protos + 1] = c.name end
      end
      if #protos == 0 then
        return vim.notify("rslime: " .. class .. " has no Draw() method", vim.log.levels.WARN)
      end
      for _, p in ipairs(protos) do
        if callable_no_args(p) then return emit(word, deref, option) end
      end
      -- 3) 全是必填参数（TTree 族）: 问画什么
      local hint = ARG_HINT[class] or "args"
      vim.ui.input({
        prompt = "rslime · " .. class .. "::Draw arguments: ",
        default = hint,
      }, function(input)
        if not input or input == "" then return end
        emit(word, deref, input)
      end)
    end, 4000)
  end)
end

M._callable_no_args = callable_no_args  -- test hook

return M
