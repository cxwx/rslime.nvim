# rslime.nvim

Slime 式 ROOT (CERN) REPL for Neovim。零依赖——基于内置 terminal，不依赖 iron/conjure/toggleterm。

在 C++ 源码里用 Jupyter 风格的 `// %%` cell 组织代码，逐块发送给 ROOT (Cling) 交互执行；支持 kernel 重启、`.undo` 撤销、THttpServer 可视化。

![screenshot](https://raw.githubusercontent.com/USER/rslime.nvim/main/screenshot.png)

## 特性

- **cell 分块**：`// %%` 头切分代码块，光标处一键发送；为了 clangd 的包裹结构（`#include`、`main()` 等）自动跳过，不会混入 REPL
- **run all**：按顺序运行全部 cell（可逐块延迟发送，便于观察每块输出）
- **kernel 重启**：`.q` → `gSystem->Exit(0)` → 强杀，三级退出兜底，退出后自动重开
- **`.undo` 撤销**：回退最近 n 条 cling 事务（支持 `:RslimeUndo 3`）
- **THttpServer**：一键启动并自动打开浏览器，后台观察变量/canvas
- **干净退出**：REPL 进程退出后终端 buffer 自动关闭，不停在 `[Process exited 0]`

## 安装

lazy.nvim：

```lua
{
  dir = "~/software/nvim/rslime.nvim", -- 或你的 fork/本地路径
  ft = { "cpp", "c" },
  keys = {
    { "<leader>r0s", desc = "rslime start" },
  },
  config = function()
    require("rslime").setup({
      prefix = "<leader>r0",
    })
  end,
}
```

要求：`root` 在 PATH 中（即 CERN ROOT，`root -l` 可启动）。

## 配置

```lua
require("rslime").setup({
  cmd = "root -l",                 -- ROOT 启动命令
  position = "bottom",             -- "bottom" | "right"
  height = nil,                    -- nil = 终端高度一半；position="right" 时用 width
  width = 80,
  startup_cmds = {},               -- 启动后发送的 cling 命令
  cell_delimiter = "^%s*//%s*%%%%",-- cell 头 pattern
  run_all_delay = 0,               -- >0 时 run all 逐 cell 延迟发送（毫秒）
  http_port = 8080,                -- THttpServer 端口
  http_open = true,                -- 启动后自动打开浏览器
  prefix = nil,                    -- nil 则不注册任何按键
  keys = {                         -- 按键 = prefix + suffix
    start = "s", toggle = "1", restart = "R", quit = "q", focus = "f",
    http = "h",
    cell = "k", line = "l", visual = "b", file = "F", undo = "u", run_all = "a",
  },
})
```

按键规则：`start/toggle/restart/quit/focus/http` 是全局映射；`cell/line/visual/file/undo/run_all` 只在 c/cpp 缓冲区生效。某项 suffix 设 `false` 可单独禁用。

## 命令

| 命令 | 说明 |
|---|---|
| `RslimeStart` | 启动 ROOT REPL |
| `RslimeToggle` | 显示 / 隐藏 REPL 窗口 |
| `RslimeRestart` | 重启 kernel |
| `RslimeQuit` | 退出 REPL |
| `RslimeFocus` | 焦点跳到 REPL 窗口 |
| `RslimeHttp` | 启动 THttpServer 并打开浏览器 |
| `RslimeSendCell` | 发送光标所在 cell |
| `RslimeSendLine` | 发送当前行 |
| `RslimeSendSelection` | 发送可视选区 |
| `RslimeSendFile` | 发送整个 buffer |
| `RslimeRunAll` | 按顺序运行所有 cell |
| `RslimeUndo [n]` | `.undo n` 撤销 cling 语句 |

## 使用示例

```cpp
// %% 定义直方图
auto h = new TH1F("h", "gaus test", 100, -5, 5);

// %% 填充（多行块整段发送）
TRandom3 rng(42);
for (int i = 0; i < 10000; ++i) {
    h->Fill(rng.Gaus(0, 1));
}

// %% 绘制
h->Draw();
```

打开 c/cpp 文件 → 启动 REPL → 光标放进某个 cell 按 cell 发送键；`,a`（按你的 prefix）依次跑全部；重启内核后再发"定义"块即可重新开始。

更多 cell 覆盖 THttpServer / undo / 重启测试，见 [`script/aa.cpp`](script/aa.cpp)。

## License

MIT
