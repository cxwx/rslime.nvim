-- Commands are defined in lua/rslime/commands.lua (single source of truth);
-- menus/pickers can require the same table: require("rslime.commands").menu()
local commands = require("rslime.commands").all()

for _, c in ipairs(commands) do
  vim.api.nvim_create_user_command(c.cmd, c.run, {
    nargs = c.nargs or 0,
    range = c.range or false,
  })
end
