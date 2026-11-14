local M = {}

local function cmd(name) return "<cmd>" .. name .. "<cr>" end

local buf_actions = {
  { "n", "cell", "RslimeSendCell", "send cell" },
  { "n", "line", "RslimeSendLine", "send line" },
  { "n", "file", "RslimeSendFile", "send file" },
  { "n", "undo", "RslimeUndo", "cling undo" },
  { "n", "run_all", "RslimeRunAll", "run all cells" },
  { "x", "visual", nil, "send selection" }, -- range command handled separately
}

---Register send mappings on a single buffer (suffix false disables; "" is a valid empty suffix)
---@param bufnr integer
---@param prefix string
---@param keys table
function M.apply_to_buf(bufnr, prefix, keys)
  keys = keys or {}
  for _, m in ipairs(buf_actions) do
    local mode, action, command, desc = m[1], m[2], m[3], m[4]
    local suffix = keys[action]
    if suffix ~= nil and suffix ~= false then
      local rhs = command and cmd(command) or ":<C-u>RslimeSendSelection<cr>"
      vim.keymap.set(mode, prefix .. suffix, rhs,
        { silent = true, buffer = bufnr, desc = "rslime " .. desc })
    end
  end
end

---Mappings are prefix + keys.<action>
---global: start/toggle/restart/quit/focus/http; c/cpp buffers: cell/line/visual/file/undo/run_all
---a suffix of false disables the action; "" means an empty suffix (prefix alone triggers)
---@param cfg table full config (prefix, keys)
function M.apply(cfg)
  local prefix = cfg.prefix
  local keys = cfg.keys or {}

  local global_actions = {
    start = "RslimeStart",
    toggle = "RslimeToggle",
    restart = "RslimeRestart",
    quit = "RslimeQuit",
    focus = "RslimeFocus",
    http = "RslimeHttp",
  }
  for action, command in pairs(global_actions) do
    local suffix = keys[action]
    if suffix ~= nil and suffix ~= false then
      vim.keymap.set("n", prefix .. suffix, cmd(command),
        { silent = true, desc = "rslime " .. action })
    end
  end

  -- send mappings are buffer-local to c/cpp files
  local augroup = vim.api.nvim_create_augroup("RslimeKeymaps", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = { "c", "cpp" },
    callback = function(args)
      M.apply_to_buf(args.buf, prefix, keys)
    end,
  })
end

return M
