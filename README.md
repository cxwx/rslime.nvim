# rslime.nvim

C++ ROOT (CERN) 的 slime 式 REPL 插件，零依赖（基于 Neovim 内置 terminal）。

## 功能

- 启动 / 重启 / 退出 ROOT 交互式 REPL（`root -l`，即 Cling 内核），支持 kernel 重启
- Jupyter 风格 `// %%` cell 分块，逐块发送给 ROOT 运行
- 发送：cell / 行 / 可视选区 / 整个文件
- `.undo n` 撤销最近 n 条 cling 语句
- cell 分隔头高亮（`RslimeCellHeader`）

## 配置

```lua
require("rslime").setup({
  cmd = "root -l",                 -- ROOT 启动命令
  position = "right",              -- "right" | "bottom"
  width = 80,
  startup_cmds = {},               -- 启动后发送的 cling 命令
  cell_delimiter = "^%s*//%s*%%%%",-- "// %%" 头 pattern
  run_all_delay = 0,               -- >0 时 run all 逐 cell 延迟发送（毫秒）
  http_port = 8080,                -- THttpServer 端口（,r0h / RslimeHttp）
  http_open = true,                -- 启动后自动打开浏览器（false 关闭）
  -- 按键 = prefix + keys.<action> 拼接；prefix = nil 不注册任何映射
  -- 某 action 的 suffix 设 false 可单独禁用
  prefix = ",rr",
  keys = {
    start = "s", toggle = "1", restart = "R", quit = "q", focus = "f",
    cell = "k", line = "l", visual = "b", file = "F", undo = "u", run_all = "a",
    http = "h",
  },
})
```

按键规则：`start/toggle/restart/quit/focus` 是全局映射；`cell/line/visual/file/undo` 只挂在 c/cpp 缓冲区。`RslimeSendSelection` 是 range 命令，visual 模式映射单独生成。

## 命令

| 命令 | 说明 |
|---|---|
| `RslimeStart` | 启动 ROOT repl |
| `RslimeToggle` | 显示 / 隐藏 repl 窗口 |
| `RslimeRestart` | 重启 kernel（`.q` 后自动重新拉起） |
| `RslimeQuit` | 退出 repl |
| `RslimeFocus` | 焦点跳到 repl 窗口 |
| `RslimeSendCell` | 发送光标所在 `// %%` cell |
| `RslimeSendLine` | 发送当前行 |
| `RslimeSendSelection` | 发送可视选区 |
| `RslimeSendFile` | 发送整个 buffer |
| `RslimeRunAll` | 按顺序运行所有 cell（跳过 cell 外的包裹结构） |
| `RslimeHttp` | 启动 ROOT THttpServer（浏览器观察变量，端口 `http_port`，默认自动打开浏览器） |
| `RslimeUndo [n]` | `.undo n` 撤销 cling 语句 |

## cell 示例

```cpp
// %% 定义
auto h = new TH1F("h", "test", 100, -5, 5);

// %% 填充
h->FillRandom("gaus");

// %% 绘制
h->Draw();
```

光标落在某 cell 内按 `,rrk` 即把该块发给 ROOT；`,rrR` 重启内核。
