-- blink.cmp provider 模块（补全 + 签名）。
-- 用法（插件已在 rtp, 如 ft 懒加载或 lazy=false）:
--   providers = { rslime = { module = "rslime.blink", name = "rslime" } }
-- keys 懒加载的用户: 配置里放一个 pcall 垫片再转发到本模块（见 README）。
-- 查询门控全在本模块: 补全/签名各自按 config 开关, REPL 未跑时 enabled=false。
-- org root 块 (rslime.babel) 另有一个开关 org_completion: 独立于 completion/signature ——
-- org buffer 上没有 clangd, 那里本源是唯一的语义补全; c/cpp 仍按 completion/signature。
local M = {}

local function cfg() return require("rslime").config end

---is the cursor in an org buffer's root block? (delegates to rslime.complete)
local function in_root_block()
  return require("rslime.complete").in_root_block()
end

---completion on in this buffer? `completion`, or `org_completion` inside a root block
local function completion_on()
  if cfg().completion then return true end
  return vim.bo.filetype == "org" and cfg().org_completion and in_root_block()
end

---signature on in this buffer? `signature`, or `org_completion` inside a root block
local function signature_on()
  if cfg().signature then return true end
  return vim.bo.filetype == "org" and cfg().org_completion and in_root_block()
end

function M:new()
  return setmetatable({}, { __index = M })
end

function M:enabled()
  local ft = vim.bo.filetype
  -- org: only with the cursor inside a root block (rslime.babel)
  if ft ~= "cpp" and ft ~= "c" and ft ~= "rootrepl" and not in_root_block() then return false end
  if not completion_on() and not signature_on() then return false end
  return require("rslime.repl").is_running()
end

function M:get_trigger_characters()
  return require("rslime.complete"):get_trigger_characters()
end

function M:get_completions(context, callback)
  -- signature-only 配置下补全不得漏出来
  if not completion_on() then
    return callback({ is_incomplete_forward = false, is_incomplete_backward = true, items = {} })
  end
  require("rslime.complete"):get_completions(context, callback)
end

function M:get_signature_help_trigger_characters()
  if not signature_on() then
    return { trigger_characters = {}, retrigger_characters = {} }
  end
  return require("rslime.signature").trigger_characters()
end

function M:get_signature_help(context, callback)
  -- 查不到/未开启 -> nil 弃权, 让位给 LSP（blink 取第一个非空结果）
  if not signature_on() then return callback(nil) end
  require("rslime.signature").get(context, callback)
end

return M
