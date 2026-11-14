-- blink.cmp provider 模块（补全 + 签名）。
-- 用法（插件已在 rtp, 如 ft 懒加载或 lazy=false）:
--   providers = { rslime = { module = "rslime.blink", name = "rslime" } }
-- keys 懒加载的用户: 配置里放一个 pcall 垫片再转发到本模块（见 README）。
-- 查询门控全在本模块: 补全/签名各自按 config 开关, REPL 未跑时 enabled=false。
local M = {}

local function cfg() return require("rslime").config end

function M:new()
  return setmetatable({}, { __index = M })
end

function M:enabled()
  local ft = vim.bo.filetype
  if ft ~= "cpp" and ft ~= "c" and ft ~= "rootrepl" then return false end
  if cfg().completion == false and cfg().signature == false then return false end
  return require("rslime.repl").is_running()
end

function M:get_trigger_characters()
  return require("rslime.complete"):get_trigger_characters()
end

function M:get_completions(context, callback)
  -- signature-only 配置下补全不得漏出来
  if cfg().completion == false then
    return callback({ is_incomplete_forward = false, is_incomplete_backward = true, items = {} })
  end
  require("rslime.complete"):get_completions(context, callback)
end

function M:get_signature_help_trigger_characters()
  if cfg().signature == false then
    return { trigger_characters = {}, retrigger_characters = {} }
  end
  return require("rslime.signature").trigger_characters()
end

function M:get_signature_help(context, callback)
  -- 查不到/未开启 -> nil 弃权, 让位给 LSP（blink 取第一个非空结果）
  if cfg().signature == false then return callback(nil) end
  require("rslime.signature").get(context, callback)
end

return M
