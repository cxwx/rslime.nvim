# TODO · 画大饼 🫓

> 终极目标：把 Emacs SLIME 那套“编辑器问活进程”的工作模式搬到 ROOT 上。SLIME 的本质是一条通往运行中 Lisp 镜像的通道（swank）加 N 个查询命令；这里对应成一条通往运行中 Cling 会话的 sentinel 问答通道，之后每个功能都只是在这条通道上加一个命令。

## 已完成

- [x] **P0 · 通道**：REPL 启动时自动注入一小段解释执行的 C++ helper，建立“请求 id + sentinel 应答”协议 —— 一切功能的地基
- [x] **P0 · 活会话补全**：通过反射（`TClass` / `TGlobal` / `TClassTable`）把运行中会话的符号喂给 [blink.cmp](https://github.com/Saghen/blink.cmp) —— 你在 REPL 里造的 `hist`、`.L` 进来的函数、autoload 的类，clangd 不知道的它都知道。**默认关闭**：日常 clangd 够用，LSP 管缓冲区，它管会话态，要时再开
- [x] **P1 · 变量求值**：光标处表达式发进活会话求值，浮窗显示值和类型（表达式由 REPL 本体执行，打错只报错不崩会话）
- [x] **P1 · 变量面板**：列出会话内存里所有全局量与类型，选中即求值到浮窗 —— notebook 变量视图的 ROOT 版
- [x] **P2 · 签名帮助 / 文档**：`Func(` 处列出全部重载原型，显示反射字典里的 class guide 注释（`<leader>r0S`）
- [x] **P3 · 错误回标**：cell 发送后 cling 报错自动回标到源码 cell（`diagnostics = true` 开启）

## 下一炉

- [x] **会话重放**：记录本会话发过的全部代码块，`<leader>r0p` 一键按序重放（跨文件、跨 buffer；`<leader>r0B` 只管当前文件，这是它补不上的那半边）
- [x] **hover**：`<leader>r0K`（独立按键，不碰用户的 K/LSP hover）—— 活会话求值光标处单词；指针/对象自动追 `Dump()` 显示数据成员当前值，非 TObject 降级 `Print()`
- [x] **面板专属 filetype `rslime-dump`（dapui 式）**：syntax 高亮三列结构；ftplugin 键位 `q`/`<Esc>` 关、`r` 刷新为最新内存值、`<CR>`/双击 step-into 成员对象 ✅ 已完成
- [x] **REPL 缓冲区 filetype = `rootrepl`（daprepl 式）**：ftplugin 挂 REPL 内 `<C-c>` 中断 + omnifunc 后备；blink `per_filetype = { rootrepl = { "rslime" } }` 实现 REPL 终端内活会话补全（一并完成） ✅ 已完成
- [x] **签名自动触发**：`(` 后自动弹活会话重载（`signature = true` 开启，blink signature provider）；查不到即弃权让位 LSP，参数位置按逗号深度计数 ✅ 已完成
- [x] **eval inline**：短结果（`(double) 0.5` 级别）以 virtual text 显示在行尾（`inline_eval = true` 开启，`<leader>r0x` 清除）；长结果仍走浮窗 ✅ 已完成
- [x] **run block inline**：单块运行后自动求值该块的变量并显示（`run_block_inline`，默认开）；值变化时 Changed 高亮；run all/before/after 不触发 ✅ 已完成
- [x] **会话画图**：`<leader>r0d` 光标对象类型感知 `Draw()`（eval 拿类名 → 反射查 Draw 重载：无参直画 / TTree 弹参数输入 / 无 Draw 提前 notify；指针 `->` 对象 `.`；补 `Modified+Update` 同事务推送 web canvas），`<leader>r0D` 叠加 same，`:RslimeDraw COLZ` 传 option；replay 连画一起重放 ✅ 已完成
- [x] **README 功能演示 GIF**：asciinema + agg + tmux 真实 ROOT 会话录制（send / completion / signature / hover 四张，逐帧 QC）✅ 已完成

## 修过的坑（复盘留档）

- [x] **补全冷启动必超时**：`rpc.request` 默认 800ms，冷会话第一次反射查询（cling 加载类表）远超它 → 补全静默空。补全请求改为 4000ms（`complete.lua`）
- [x] **run-block inline 丢 Changed 高亮**：`refresh` 硬编码 `changed=false`，且 `place()` 内部的 `clear_line` 把循环里刚 set 的 `last_text` 条目又删了（refresh 之后缓存是空的，对比永远失败）。两处都修了，smoke 补了同值/变值两条断言
- [x] **`last_text` 随 buffer 泄漏**：key 是 `buf:lnum`，buffer 删除后残留。`BufUnload` autocmd 清理（首次使用时注册）

## 下一炉

- [ ] **冷会话预热**：REPL 启动注入 helper 后顺手发一个廉价反射查询（如 `rslime_rpc` 查 `TObject`），把 cling 类表加载提前 —— 补全/签名首次触发的秒级延迟就没了（`complete.lua` 已把超时放宽到 4s，预热是把延迟本身消掉）
- [ ] **diag.capture 用 sentinel 代替固定 1800ms**：现在 cell 发送后盲等 1800ms 再扫 REPL 输出；长编译 cell 的错误可能还没出现，短 cell 又白等。已有 `rslime_mark` E 机制，等 E 到达再解析即可
- [ ] **probe 超时回传部分结果**：run-block inline 某个变量求值超时会把整个结果丢弃（`cb(nil)`）；已求到的变量其实可以先显示
- [ ] **probe 与用户操作抢单通道**：probe 串行求值期间用户做了 eval/hover/补全，probe 的请求被 supersede，变量静默缺失。可接受（再跑一次就好），要更稳就得给通道加请求队列
- [ ] **`probe.names` 误抓函数定义**：`void f(...) {` 会匹配 `Type name(` 模式被当变量探针；eval 结果是函数地址（通常超宽被过滤），无实际危害，但按住"声明/赋值"语义收紧模式更干净

## 不画的饼（想清楚了，不做）

- THttpServer 面板 —— 实测（ROOT 6.41）：REST 侧无层级枚举（对象树只走 websocket GUI）；`Register` 的目录 REST 访问不到；canvas 走 web canvas **创建时已自动开浏览器**；`exe.json` 默认只读锁死且会话内执行本就有更安全的 REPL 通道。取而代之做了上面的会话画图
- `.L`/`.x` 路径补全 —— REPL 窗口里 root 原生 Tab 已覆盖；源码 cell 里 blink 内置 `path` provider 已覆盖。两侧都有现成的，没有空白可填
- 重发 cell 前自动 `.undo` 旧事务 —— 一个 cell 会产生**多个** cling 事务（每条顶层语句一个），盲 undo 数量必然猜错，会悄悄污染会话状态。可靠循环就是 `<leader>r0R` 重启 + `<leader>r0B` 重跑 setup cells
- 参数位置感知的语义补全 —— 需要修 Cling 重建 ROOT，且大半收益被 clangd 覆盖
- 编辑器缓冲区局部变量的补全 —— 只有 Lisp 的 homoiconic reader 做得到（这正是 SLIME 的天赋），C++ 交给 LSP
- 调试器集成 —— Cling 没有 DAP
- 真 swank socket —— sentinel pty 通道已覆盖当前需求；cling 非线程安全，会话内起 TCP server 得跨线程调补全，有崩会话风险，不值得
