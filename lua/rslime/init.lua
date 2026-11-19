local M = {}

local defaults = {
  cmd = "root -l",
  position = "bottom", -- "bottom" | "right"
  width = 80,
  height = nil,        -- nil = half the terminal height
  startup_cmds = {},   -- cling commands sent after startup
  cell_delimiter = "^%s*//%s*%%%%",
  run_all_delay = 0,   -- >0: send cells one by one with this delay (ms)
  send_keep_focus = true, -- send without stealing focus: cursor stays in the source buffer
                        -- (false: jump to the REPL window on every send)
  http_port = 8080,
  http_open = true,    -- open the browser after starting THttpServer
  completion = false,  -- off by default: LSP covers most of it; the live source only adds
                       -- REPL-session symbols (objects made interactively, .L, autoload)
  diagnostics = false, -- mark cling errors from cell sends back onto the source cell
  signature = false,  -- opt-in: auto signature help on `(` from the live session
                       -- (blink signature provider; LSP covers buffer-known symbols)
  inline_eval = false, -- opt-in: short eval results as virtual text at the line end;
                       -- long results still float (RslimeInlineClear wipes the marks)
  run_block_inline = true, -- after running ONE block (send cell), show its variable
                           -- values as eol virtual text; run all/before/after skip it
  run_block_inline_delay = 600, -- ms to wait after sending before probing (let cling finish)
  -- mappings are prefix + keys.<action>; prefix = nil registers no mappings
  -- global: start/toggle/restart/quit/focus/http; send mappings follow filetypes:
  -- nil = global mappings (no autocmd); { "c", "cpp" } = buffer-local via FileType
  -- set a suffix to false to disable that mapping
  prefix = nil,
  filetypes = nil,     -- send-mapping scope: nil = global; a string or list = only those filetypes
  short_desc = false,   -- true: short which-key descriptions ("rslime before" instead of
                        -- "rslime run cells before cursor")
  keys = {
    start = "s",
    toggle = "1",
    restart = "R",
    quit = "q",
    focus = "f",
    http = "h",
    cell = "k",
    line = "l",
    visual = "b",
    file = "F",
    undo = "u",
    run_all = "a",
    run_before = "B",   -- cells strictly before the cursor's cell
    run_after = "A",    -- the cursor's cell and everything after
    eval = "e",         -- eval word (n) / selection (x) in the live session
    sign = "S",         -- signatures + docs for the identifier before the cursor
    vars = "v",         -- session variable panel
    replay = "p",       -- re-send everything recorded this session (rebuild a fresh kernel)
    hover = "K",        -- live-session hover (Dump) on the word under the cursor; NOT the K key
    inline_clear = "x", -- wipe the buffer's inline eval results
    draw = "d",        -- Draw word under cursor (web canvas opens the browser)
    draw_same = "D",   -- Draw with "same" (overlay on the current pad)
  },
}

M.config = vim.deepcopy(defaults)

---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)

  local repl = require("rslime.repl")
  repl._set_config(M.config)

  -- cell header highlight (window-local, c/cpp)
  vim.api.nvim_set_hl(0, "RslimeCellHeader", { link = "SpecialComment", default = true })
  vim.api.nvim_set_hl(0, "RslimeInline", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "RslimeInlineChanged", { link = "DiagnosticVirtualTextWarn", default = true })
  local group = vim.api.nvim_create_augroup("RslimeHighlight", { clear = true })
  vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = group,
    pattern = { "c", "cpp" },
    callback = function(args)
      local win = vim.fn.bufwinid(args.buf)
      if win == -1 then return end
      vim.fn.clearmatches(win)
      pcall(vim.fn.matchadd, "RslimeCellHeader", M.config.cell_delimiter, 10, -1, { window = win })
    end,
  })

  if M.config.prefix then
    local keymaps = require("rslime.keymaps")
    keymaps.apply(M.config)
    -- ft lazy-loading: with filetypes set, the FileType event has already fired for this
    -- buffer — register on it when its filetype matches (nil filetypes = already set globally)
    if M.config.filetypes and keymaps.ft_enabled(vim.bo.filetype, M.config.filetypes) then
      keymaps.apply_to_buf(vim.api.nvim_get_current_buf(), M.config.prefix, M.config.keys, M.config.short_desc, M.config)
    end
  end
  return M.config
end

return M
