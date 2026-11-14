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

require("rslime").setup { prefix = nil, completion = true }
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
                finish(ok and ok3 and #c4 >= 3 and oke and okb and okv)
              end, 8000)
            end, 8000)
          end, 8000)
        end, 12000)
      end, 12000)
    end, 12000)
  end, 12000)
end, 10000)

vim.wait(40000, function() return false end, 100)
