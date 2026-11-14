-- rslime sentinel 通道端到端测试（真实 root 进程 + pty 扫描）:
--   nvim -l script/e2e_test.lua ; 结果写入 script/e2e_test.out
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local out_path = plugin_root .. "/script/e2e_test.out"

package.path = package.path
  .. ";" .. plugin_root .. "/lua/?.lua"
  .. ";" .. plugin_root .. "/lua/?/init.lua"

local out = {}
local function say(s) out[#out + 1] = s end
local function flush(code)
  table.insert(out, "RESULT " .. (code and "PASS" or "FAIL"))
  local f = io.open(out_path, "w")
  f:write(table.concat(out, "\n"), "\n")
  f:close()
end

-- headless 默认列宽太窄会把应答行折行，加宽
vim.o.columns = 200

require("rslime").setup { prefix = nil, completion = true, diagnostics = true, inline_eval = true }
local repl = require("rslime.repl")
local rpc = require("rslime.rpc")

repl.start()

local function finish(ok)
  pcall(function() vim.fn.jobstop(repl.job_id()) end)
  vim.defer_fn(function() vim.cmd("qa!") end, 200)
  vim.defer_fn(function() flush(ok) end, 50)
end

-- 等 root 提示符 + helper 注入（start() 800ms 时 .L，tty 会排队）
vim.defer_fn(function()
  pcall(function() vim.api.nvim_chan_send(repl.job_id(), 'TH1F hist("h", "t", 100, 0, 10);\n') end)
  -- 用户场景: cell 风格发一个 auto 指针 (script/test.cpp 第一格)
  pcall(function() vim.api.nvim_chan_send(repl.job_id(), 'auto p = new TH1F("p", "t", 100, 0, 10);\n') end)
end, 6000)

vim.defer_fn(function()
  -- rootrepl filetype (daprepl 式) 应已由 on_buf 设置
  local rbuf = repl.bufnr()
  assert(rbuf and vim.bo[rbuf].filetype == "rootrepl",
    "rootrepl ft expected, got [" .. vim.bo[rbuf].filetype .. "]")
  say("rootrepl ft OK")
  rpc.request("  hist.Dra", function(lines)  -- 带缩进, 复现真实 cell
    local cands = rpc.parse_lines(lines)
    local names = {}
    for _, c in ipairs(cands) do names[#names + 1] = c.name end
    local ok = #cands >= 3 and vim.tbl_contains(names, "Draw")
    say(("hist.Dra -> %d cands, Draw=%s"):format(#cands, tostring(vim.tbl_contains(names, "Draw"))))
    for i = 1, math.min(4, #cands) do say("  " .. cands[i].name .. " : " .. cands[i].detail) end

    -- 用户场景: auto 指针成员, h-> 前缀为空 / h->Dra 有前缀
    rpc.request("  p -> ", function(lines2)  -- 缩进 + 箭头后空格
      local c2 = rpc.parse_lines(lines2)
      say(("p-> -> %d cands (full member list)"):format(#c2))
      rpc.request("  p->Dra", function(lines3)
        local c3 = rpc.parse_lines(lines3)
        local n3 = {}
        for _, c in ipairs(c3) do n3[#n3 + 1] = c.name end
        local ok3 = #c3 >= 3 and vim.tbl_contains(n3, "Draw")
        say(("p->Dra -> %d cands, Draw=%s"):format(#c3, tostring(vim.tbl_contains(n3, "Draw"))))

        rpc.request("TH1F::Dra", function(lines4)
          local c4 = rpc.parse_lines(lines4)
          say(("TH1F::Dra -> %d cands"):format(#c4))

          -- M2: 求值（三明治，REPL 本体执行）
          rpc.request_expr("p->GetMean()", function(ev)
            local joined = table.concat(ev, " | ")
            say(("eval p.GetMean() -> [%s]"):format(joined))
            local oke = joined:find("double", 1, true) ~= nil

            -- M2: 错误表达式必须不崩会话（后续请求仍活）
            rpc.request_expr("no_such_var_xyz", function(ev2)
              say(("eval bad -> %d lines"):format(#(ev2 or {})))
              local okb = ev2 ~= nil and #ev2 > 0   -- 有错误输出, 而不是超时 nil

              -- M2: 变量面板
              rpc.request_cmd(function(id)
                return string.format('rslime_vars("%s")\n', id)
              end, nil, function(vl)
                local vars = rpc.parse_lines(vl)
                local vn = {}
                for _, v in ipairs(vars) do vn[#vn + 1] = v.name end
                local okv = vim.tbl_contains(vn, "hist") and vim.tbl_contains(vn, "p")
                say(("vars -> %d, hist=%s p=%s"):format(#vars,
                  tostring(vim.tbl_contains(vn, "hist")), tostring(vim.tbl_contains(vn, "p"))))

                -- M3: 签名 (P 类行, 含 vv 与类 doc)
                rpc.request_cmd(function(id)
                  return string.format('rslime_sign("%s", "%s")\n', id, rpc.escape("p->Fill"))
                end, nil, function(sl)
                  local sigs = {}
                  for _, c in ipairs(rpc.parse_lines(sl)) do
                    if c.kind == "P" then sigs[#sigs + 1] = c.name end
                  end
                  say(("sign p->Fill -> %d protos"):format(#sigs))
                  for i = 1, math.min(3, #sigs) do say("  " .. sigs[i]) end
                  local oks = #sigs >= 3 and sigs[1]:find("TH1::Fill", 1, true) ~= nil

                  -- P3: 错误回标。真 buffer + 坏 cell 走 send_cell 全路径
                  local srcbuf = vim.api.nvim_create_buf(false, true)
                  vim.api.nvim_buf_set_lines(srcbuf, 0, -1, false, {
                    "// %% bad cell",
                    "nope_var_xyz.Foo();",
                  })
                  vim.api.nvim_set_current_buf(srcbuf)
                  vim.api.nvim_win_set_cursor(0, { 2, 0 })
                  repl.send_cell()  -- capture() 等 1800ms 后回标
                  vim.defer_fn(function()
                    local ds = vim.diagnostic.get(srcbuf)
                    local okd = #ds >= 1 and ds[1].lnum == 1
                      and ds[1].message:find("nope", 1, true) ~= nil
                    say(("diag -> %d items, first=%s"):format(#ds,
                      #ds > 0 and ("[" .. ds[1].lnum + 1 .. "] " .. ds[1].message) or "none"))

                    -- 会话重放: 清历史 -> 记一条 -> 重放 -> 活会话里验证
                    local history = require("rslime.history")
                    history.clear()
                    history.record('TH1F rp("rp", "t", 100, 0, 10)')
                    history.replay(300, function()
                      rpc.request_cmd(function(id)
                        return string.format('rslime_vars("%s")\n', id)
                      end, nil, function(vl2)
                        local vn2 = {}
                        for _, v in ipairs(rpc.parse_lines(vl2)) do vn2[#vn2 + 1] = v.name end
                        local okr = vim.tbl_contains(vn2, "rp")
                        say(("replay -> rp=%s"):format(tostring(okr)))

                        -- hover: 指针 p -> Dump() 数据成员
                        require("rslime.inspect").hover_session("p", function(hl)
                          local joined = table.concat(hl, " ")
                          local okh = joined:find("TH1F *", 1, true) ~= nil
                            and (joined:find("fN", 1, true) or joined:find("fEntries", 1, true)) ~= nil
                            and #hl > 5
                          say(("hover p -> %d lines, dump=%s"):format(#hl, tostring(okh)))

                          -- eval inline: 短结果 -> 行尾 virt text（不弹浮窗）
                          local ibuf = vim.api.nvim_create_buf(false, true)
                          vim.api.nvim_buf_set_lines(ibuf, 0, -1, false,
                            { 'TH1F hist("h", "t", 100, 0, 10);' })
                          vim.api.nvim_set_current_buf(ibuf)
                          vim.api.nvim_win_set_cursor(0, { 1, 5 })  -- 光标落在 hist 上
                          require("rslime.inspect").eval_cursor()
                          vim.defer_fn(function()
                            local ins = vim.api.nvim_create_namespace("rslime.inline")
                            local ms = vim.api.nvim_buf_get_extmarks(ibuf, ins, 0, -1, {})
                            local oki = #ms >= 1
                            say(("inline -> %d marks, hist=%s"):format(#ms, tostring(oki)))
                            finish(ok and ok3 and #c4 >= 3 and oke and okb and okv and oks
                              and okd and okr and okh and oki)
                          end, 3000)
                        end)
                      end, 8000)
                    end)
                  end, 3500)
                end, 8000)
              end, 8000)
            end, 8000)
          end, 8000)
        end, 12000)
      end, 12000)
    end, 12000)
  end, 12000)
end, 10000)

vim.wait(80000, function() return false end, 100)
