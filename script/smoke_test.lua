-- rslime cell 解析冒烟测试：nvim -l script/smoke_test.lua
-- nvim -l 不加载用户配置/rtp，手动加 package.path
package.path = package.path .. ";"
  .. vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h") .. "/lua/?.lua"
local cells = require("rslime.cells")
local delim = "^%s*//%s*%%%%"

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "// %% 定义",
  "auto h = new TH1F();",
  "",
  "// %% 填充",
  "h->FillRandom(\"gaus\");",
  "h->Draw();",
  "",
})

local parsed = cells.parse(buf, delim)
assert(#parsed == 2, "expect 2 cells, got " .. #parsed)
assert(parsed[1].start == 2 and parsed[1].stop == 3)
-- 最后一个 cell 末尾的空行被剥离（新边界规则）
assert(parsed[2].start == 5 and parsed[2].stop == 6)

-- 光标在头行上 -> 该 cell
local c1, t1 = cells.cell_at(buf, 5, delim)
assert(c1 and c1.start == 5 and t1:gsub("%s+$", "") == 'h->FillRandom("gaus");\nh->Draw();', "cell_at head line")

-- 光标在最后一 cell 之后 -> 最后一个 cell
local _, t2 = cells.cell_at(buf, 8, delim)
assert(t2 ~= nil and t2:find("Draw"), "cell_at after last cell")

-- 光标在第一个 cell 头行上 -> 该 cell（头行归属本 cell）
local c0 = cells.cell_at(buf, 1, delim)
assert(c0 and c0.start == 2, "cursor on first header belongs to that cell")

local all = cells.all_cell_texts(buf, delim)
assert(#all == 2)

print("smoke_test OK")
