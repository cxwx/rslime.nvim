-- blink.cmp (v2) source: live ROOT session symbols via rslime.
-- Registers as a provider:  rslime = { module = "rslime.complete", async = true }
-- Covers what clangd cannot know: REPL-declared objects, .L-loaded symbols,
-- autoloaded classes — the session state at the moment of typing.
local M = {}

local KIND_LSP = {           -- helper K -> blink CompletionItemKind
  M = 2,                     -- Method
  D = 5,                     -- Field
  C = 7,                     -- Class
  V = 6,                     -- Variable
  F = 3,                     -- Function
}
local KIND_LABEL = { M = "method", D = "member", C = "class", V = "var", F = "func" }

function M:new() return setmetatable({}, { __index = M }) end

function M:enabled()
  local ft = vim.bo.filetype
  if ft ~= "cpp" and ft ~= "c" and ft ~= "rootrepl" then return false end
  local ok, repl = pcall(require, "rslime.repl")
  return ok and repl.is_running()
end

function M:get_trigger_characters() return { ".", ">", ":" } end

---core entry, also usable without blink: complete_line("hist.Dra", cb)
---@param before string line text before the cursor
---@param cb fun(items: table[])
function M.complete_line(before, cb)
  if not before or before == "" then return cb({}) end
  -- worth asking? an access operator, or a trailing identifier of >=2 chars
  if not (before:find("[%.:>]$") or before:find("[%.:>][_a-zA-Z][_a-zA-Z0-9]*$")
      or before:find("[_a-zA-Z][_a-zA-Z0-9]*$")) then
    return cb({})
  end
  require("rslime.rpc").request(before, function(lines)
    local items = {}
    local seen = {}
    for _, c in ipairs(require("rslime.rpc").parse_lines(lines)) do
      if not seen[c.name] then
        seen[c.name] = true
        items[#items + 1] = {
          label = c.name,
          label_description = KIND_LABEL[c.kind],
          kind = KIND_LSP[c.kind] or 1,
          detail = c.detail,
        }
      end
    end
    cb(items)
  end)
end

function M:get_completions(context, callback)
  local col = (context.cursor and context.cursor[2]) or #context.line + 1
  local before = context.line:sub(1, col - 1)
  M.complete_line(before, function(items)
    callback({ is_incomplete_forward = false, is_incomplete_backward = true, items = items })
  end)
end

---omnifunc for the rootrepl ftplugin (C-x C-o); blink users never hit this
function M.omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col(".")
    local before = line:sub(1, col)
    local start = before:match("[%.%->_:a-zA-Z0-9]*$") or ""
    return col - #start
  end
  local items = {}
  M.complete_line(vim.api.nvim_get_current_line():sub(1, vim.fn.col(".")), function(cands)
    for _, c in ipairs(cands) do
      items[#items + 1] = { word = c.label, menu = c.label_description, kind = c.kind }
    end
    vim.fn.complete(vim.fn.col(".") - #base, items)
  end)
  return ""
end

return M
