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

-- before/after: 光标在第 2 格（头行 5） -> before=第1格, after=第2格(含当前)
local bef = cells.cell_texts_before(buf, 5, delim)
assert(#bef == 1 and bef[1]:find("TH1F", 1, true), "before cell2 = cell1")
local aft = cells.cell_texts_after(buf, 5, delim)
assert(#aft == 1 and aft[1]:find("Draw"), "after cell2 = cell2 (inclusive)")
-- 光标在第 1 格 -> before 空, after = 两格
assert(#cells.cell_texts_before(buf, 2, delim) == 0, "before cell1 = none")
assert(#cells.cell_texts_after(buf, 2, delim) == 2, "after cell1 = both")

-- rpc: C 字符串转义（引号/反斜杠/换行）
local rpc = require("rslime.rpc")
assert(rpc.escape([[hist->Dra]]) == [[hist->Dra]])
assert(rpc.escape([[a"B\c]]) == [[a\"B\\c]], rpc.escape([[a"B\c]]))
assert(rpc.escape("x\ny") == "x y")

-- rpc: 应答行解析 name%K%detail，垃圾行丢弃
local cands = rpc.parse_lines({
  "Draw%M%void TH1F::Draw(Option_t*)",
  "fNbins%D%Int_t",
  "TH1F%C%class",
  "hist%V%TH1F",
  "Info in <TInterpreter>: noise",
  "RSLIME 1 E",
})
assert(#cands == 4, "expect 4 candidates, got " .. #cands)
assert(cands[1].name == "Draw" and cands[1].kind == "M" and cands[1].detail:find("TH1F", 1, true))
assert(cands[4].name == "hist" and cands[4].kind == "V" and cands[4].detail == "TH1F")

-- complete: 查询门控（值得发请求的行才发）
local complete = require("rslime.complete")
local want = { ["hist.Dra"] = true, ["hp->"] = true, ["TH1F::D"] = true,
               ["auto x = hi"] = true, [""] = false, ["auto x = "] = false,
               ["for (int 3"] = false }
for line, expected in pairs(want) do
  local called = false
  local hit
  complete.complete_line(line, function(items) called = true; hit = items end)
  -- 不发请求的分支是同步回调空表；这里只验证不会不回调
  assert(called, "complete_line did not call back for: " .. vim.inspect(line))
  if expected == false then assert(#hit == 0, "expected empty for: " .. line) end
end

-- rpc: eval 三明治过滤（去回显行/marker 回显/空行，保值行）
local ev = rpc.filter_eval_lines({
  "𝒞𝒳:  12 >p.GetMean()",           -- 表达式回显 (行尾=表达式)
  "(double) 0.5238917",              -- 值
  "",                                -- 空行
  '𝒞𝒳:  13 >rslime_mark("8","E")',  -- marker 回显
  "error: use of undeclared identifier 'nope'",  -- 错误行也要保留
}, "p.GetMean()")
assert(#ev == 2 and ev[1] == "(double) 0.5238917" and ev[2]:find("^error:"), vim.inspect(ev))

-- diag: cling 错误行解析
local diag = require("rslime.diag")
local errs = diag.parse_errors({
  "input_line_13:2:10: error: use of undeclared identifier 'nope'",
  "ROOT_prompt_8:1:2: error: member reference type 'TH1F *' is a pointer",
  "error: something anchorless",
  "Info in <TInterpreter>: noise",   -- 非错误
  "(double) 0.5",                     -- 值输出
})
assert(#errs == 3, "expect 3 errors, got " .. #errs)
assert(errs[1].line == 2 and errs[1].col == 10 and errs[1].message:find("nope", 1, true))
assert(errs[2].line == 1 and errs[2].col == 2)
assert(errs[3].line == 1 and errs[3].message == "something anchorless")

-- history: 记录/获取/清空/去空
local history = require("rslime.history")
history.clear()
history.record("auto a = 1;")
history.record("   ")          -- 空白不记
history.record("auto b = 2;")
local h = history.get()
assert(#h == 2 and h[1] == "auto a = 1;" and h[2] == "auto b = 2;")

-- inline: 短结果判定 + 行尾 virt text 置/换/清
local inline = require("rslime.inline")
assert(inline.is_short({ "(double) 0.5" }))
assert(inline.is_short({ string.rep("x", 80) }))
assert(not inline.is_short(nil))
assert(not inline.is_short({ "a", "b" }))
assert(not inline.is_short({ string.rep("x", 81) }))
local ibuf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(ibuf, 0, -1, false, { "h->GetMean();", "second" })
assert(inline.show(ibuf, 1, "  (double) 0.5000000"))
assert(inline.show(ibuf, 1, "(double) 0.6000000"))  -- 同行重求值 -> 替换
local ins = vim.api.nvim_create_namespace("rslime.inline")
assert(#vim.api.nvim_buf_get_extmarks(ibuf, ins, 0, -1, {}) == 1, "one mark per line")
inline.clear(ibuf)
assert(#vim.api.nvim_buf_get_extmarks(ibuf, ins, 0, -1, {}) == 0, "clear wipes")
assert(not inline.show(ibuf, 99, "out of range"))  -- 越界 -> false -> 调用方回退浮窗
-- probe: 单块变量名抽取
local probe = require("rslime.probe")
local pn = probe.names([[auto h = new TH1F("h", "t", 100, 0, 10);
TH1F hist("x", "t", 10, 0, 1);
TF1 *f1 = new TF1("f1", "gaus");
for (int i = 0; i < 10; ++i) h->Fill(i);
y = 3;]])
assert(vim.deep_equal(pn, { "h", "hist", "f1", "y" }), vim.inspect(pn))

-- inline.refresh: 全量替换，未出现的行被丢弃；同行值变化 -> Changed 高亮
local rbuf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(rbuf, 0, -1, false, { "auto h = new TH1F();", "h->Fill();", "h->Draw();" })
inline.refresh(rbuf, { [1] = "(TH1F *) 0x1", [3] = "void" })
assert(#vim.api.nvim_buf_get_extmarks(rbuf, ins, 0, -1, {}) == 2, "refresh replaces all")
inline.refresh(rbuf, { [3] = "void" })
local ms = vim.api.nvim_buf_get_extmarks(rbuf, ins, 0, -1, { details = true })
assert(#ms == 1 and ms[1][2] == 2, "only line 3 marked after replace")
-- signature: 调用头解析 + 参数计数（0 基）
local sig = require("rslime.signature")
local h1, p1 = sig._parse_context("h->Fill(", 8)          assert(h1 == "h->Fill" and p1 == 0, vim.inspect({h1, p1}))
local h2, p2 = sig._parse_context("  p->Fill(1.5, ", 15)  assert(h2 == "p->Fill" and p2 == 1, vim.inspect({h2, p2}))
local h3, p3 = sig._parse_context("f(g(x), 2, ", 12)      assert(h3 == "f" and p3 == 2, vim.inspect({h3, p3}))
local h4, p4 = sig._parse_context('TH1F::Draw("APL", ', 18) assert(h4 == "TH1F::Draw" and p4 == 1, vim.inspect({h4, p4}))
assert(sig._parse_context("no paren here", 13) == nil)
assert(sig._parse_context("(a+b)*(", 8) == nil, "表达式非调用头")
assert(sig._parse_context("for (int i =", 12) == nil, "关键字后括号无调用头")
-- draw: Draw 重载的"无参可调"判定
local draw = require("rslime.draw")
assert(draw._callable_no_args("void TH1::Draw()"))
assert(draw._callable_no_args('void TH1::Draw(Option_t* option = "")'))
assert(draw._callable_no_args("void TGraph::Draw(Option_t* chopt = \"\")"))
assert(not draw._callable_no_args("void TTree::Draw(const char* varexp, const char* selection)"))
assert(not draw._callable_no_args("void TTree::Draw(const char* varexp)"))
assert(draw._callable_no_args("void f(TF1* g = nullptr, Color_t c = 1)"))
print("smoke_test OK")
