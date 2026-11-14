# rslime.nvim

Slime-style ROOT (CERN) REPL for Neovim. Zero dependencies — built on the internal terminal, no iron/conjure/toggleterm needed.

Organize your C++ code into Jupyter-style `// %%` cells and send them one by one to ROOT (Cling) for interactive execution. Kernel restart, `.undo`, and THttpServer visualization supported.

![rslime.nvim demo](assets/demo.gif)

[▶ HD video (mp4, ~580 KB)](https://github.com/cxwx/rslime.nvim/raw/main/assets/demo.mp4)

## What is this?

C++ has no official interactive interpreter, but CERN's [ROOT](https://root.cern/) ships one: [Cling](https://github.com/root-project/cling), a C++ interpreter based on Clang/LLVM. `root -l` opens a REPL where C++ statements run immediately — the de-facto standard for HEP (high energy physics) analysis.

rslime.nvim turns that REPL into a slime workflow: keep your code in ordinary `.cpp` files, split it into cells, and push each cell to the running interpreter — like [slime](https://github.com/jpalardy/vim-slime) or a Jupyter notebook, but for C++.

## Requirements

- Neovim 0.10+
- **[CERN ROOT](https://root.cern/download/)** on your PATH (`root -l` must start) — ROOT is an *external dependency*; it bundles the Cling C++ interpreter that powers the REPL. Install via package manager (e.g. `brew install root`) or build from source.

Neovim plugin dependencies: none.

## Features

- **Cells**: split code into blocks with `// %%` headers and send the one under the cursor; LSP wrapper structure (`#include`, `main()`, …) is skipped automatically and never leaks into the REPL
- **Run all**: execute every cell in order (optional per-cell delay to watch each block's output)
- **Run before / after**: run all cells above the cursor (re-run the setup part) or from the cursor down (Jupyter's *Run All Above* / *Run Selected and Below*)
- **Live eval**: `,r0e` evaluates the word under the cursor (or the visual selection) in the running session and floats the result — hover `hist` and see its live entries/mean. Bad expressions show the compiler error in the float; the session never dies
- **Variable panel**: `,r0v` lists every global in the session with its type; pick one to evaluate it — the notebook "variables view", ROOT edition
- **Kernel restart**: `.q` → `gSystem->Exit(0)` → force kill, three-level fallback; the REPL comes back automatically
- **Undo**: roll back the last n cling transactions (`:RslimeUndo 3`)
- **THttpServer**: one key to start it and open the browser — inspect variables and canvases from the background
- **Live-session completion** *(opt-in, off by default — LSP covers most of it)*: a [blink.cmp](https://github.com/Saghen/blink.cmp) source backed by the running REPL, for the one thing LSP can't do: symbols that only exist in the session — objects created interactively, `.L`-loaded functions, autoloaded classes
- **Clean exit**: the terminal buffer closes itself when the REPL exits; never stuck on `[Process exited 0]`

## Installation

Install with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "cxwx/rslime.nvim",
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

Requirement: CERN ROOT on your PATH (`root -l` must start).

## Configuration

```lua
require("rslime").setup({
  cmd = "root -l",                 -- ROOT command to run
  position = "bottom",             -- "bottom" | "right"
  height = nil,                    -- nil = half the terminal height; position="right" uses width
  width = 80,
  startup_cmds = {},               -- cling commands sent after startup
  cell_delimiter = "^%s*//%s*%%%%",-- cell header pattern
  run_all_delay = 0,               -- >0: send cells one by one with this delay (ms)
  http_port = 8080,                -- THttpServer port
  http_open = true,                -- open the browser after starting THttpServer
  completion = false,              -- opt-in: live-session completion (see below)
  short_desc = false,              -- true: compact which-key labels ("󰖯 before" instead of
                                   --       "rslime run cells before cursor"); needs a Nerd Font
  prefix = nil,                    -- nil registers no mappings
  keys = {                         -- mapping = prefix + suffix
    start = "s", toggle = "1", restart = "R", quit = "q", focus = "f",
    http = "h",
    cell = "k", line = "l", visual = "b", file = "F", undo = "u", run_all = "a",
    run_before = "B",              -- cells strictly before the cursor's cell
    run_after = "A",               -- the cursor's cell and everything after
    eval = "e",                    -- eval word (n) / selection (x) in the live session
    vars = "v",                    -- session variable panel
  },
})
```

Mapping rules: `start/toggle/restart/quit/focus/http` are global; `cell/line/visual/file/undo/run_all/run_before/run_after/eval/vars` are buffer-local to c/cpp files. Set any suffix to `false` to disable it. `short_desc = true` swaps the verbose which-key labels for compact `"󰖯 before"`-style ones (Nerd Font required).

## Live-session completion (opt-in)

Off by default — for most code, LSP (clangd) completion is better. What LSP structurally cannot know is the state of the *running* session: the `hist` you built two cells ago, functions loaded with `.L`, classes pulled in by autoload. This source covers exactly that gap:

- `hist.Dra` → methods of the live object, with real prototypes
- `TH1F::Dra` → statics of a class (autoloaded on demand)
- bare `hi` → session globals + ROOT classes

It works by injecting a small C++ helper into the running interpreter (interpreted, nothing compiled) and talking to it through the REPL terminal with sentinel-delimited requests — the SLIME "ask the running image" trick, minus the socket. The same RPC channel is the base for the roadmap items below (variable eval, inspector).

Enable and wire into [blink.cmp](https://github.com/Saghen/blink.cmp) (v2):

```lua
require("rslime").setup({ prefix = "<leader>r0", completion = true })

require("blink.cmp").setup({
  sources = {
    per_filetype = { cpp = { inherit_defaults = true, "rslime" } },
    providers = {
      rslime = {
        module = "rslime.complete",
        async = true,
        score_offset = 100,  -- rank above LSP: session state beats static guesses
        max_items = 3,
        transform_items = function(_, items)
          for _, item in ipairs(items) do item.kind_icon = "Ⓢ" end
          return items
        end,
      },
    },
  },
})
```

Notes:
- Completion queries the session, not the buffer: a variable must be **sent to the REPL first** (`,r0k`); buffer-only locals are LSP's job
- The source disables itself when the REPL isn't running or `completion = false`
- Restarting the kernel re-injects the helper automatically

## Commands

| Command | Description |
|---|---|
| `RslimeStart` | Start the ROOT REPL |
| `RslimeToggle` | Show / hide the REPL window |
| `RslimeRestart` | Restart the kernel |
| `RslimeQuit` | Quit the REPL |
| `RslimeFocus` | Jump to the REPL window |
| `RslimeHttp` | Start THttpServer and open the browser |
| `RslimeSendCell` | Send the cell under the cursor |
| `RslimeSendLine` | Send the current line |
| `RslimeSendSelection` | Send the visual selection |
| `RslimeSendFile` | Send the whole buffer |
| `RslimeRunAll` | Run all cells in order |
| `RslimeRunBefore` | Run all cells before the cursor's cell |
| `RslimeRunAfter` | Run the cursor's cell and all cells after it |
| `RslimeEval` | Evaluate the word under the cursor in the session, float the result |
| `RslimeEvalVisual` | Evaluate the visual selection |
| `RslimeVars` | Session variable panel — pick a global to evaluate |
| `RslimeUndo [n]` | `.undo n` — roll back cling transactions |

## Example

```cpp
// %% Create a histogram
auto h = new TH1F("h", "gaus test", 100, -5, 5);

// %% Fill (multi-line block sent as a whole)
TRandom3 rng(42);
for (int i = 0; i < 10000; ++i) {
    h->Fill(rng.Gaus(0, 1));
}

// %% Draw
h->Draw();
```

Open a c/cpp file → start the REPL → put the cursor inside a cell and hit the send key; run all executes every block in order; after a kernel restart, resend the "create" cell to start over.

See [`script/test.cpp`](script/test.cpp) for cells covering THttpServer, undo and restart testing.

## Roadmap · 画大饼 🫓

> 终极目标：把 Emacs SLIME 那套“编辑器问活进程”的工作模式搬到 ROOT 上。SLIME 的本质是一条通往运行中 Lisp 镜像的通道（swank）加 N 个查询命令；这里对应成一条通往运行中 Cling 会话的 sentinel 问答通道，之后每个功能都只是在这条通道上加一个命令。

- [x] **P0 · 通道**：REPL 启动时自动注入一小段解释执行的 C++ helper，建立“请求 id + sentinel 应答”协议 —— 一切功能的地基 ✅ 已完成
- [x] **P0 · 活会话补全**：通过反射（`TClass` / `TGlobal` / `TClassTable`）把运行中会话的符号喂给 [blink.cmp](https://github.com/Saghen/blink.cmp) —— 你在 REPL 里造的 `hist`、`.L` 进来的函数、autoload 的类，clangd 不知道的它都知道。**默认关闭**：日常 clangd 够用，LSP 管缓冲区，它管会话态，要时再开 ✅ 已完成
- [x] **P1 · 变量求值**：光标处表达式发进活会话求值，浮窗显示值和类型（表达式由 REPL 本体执行，打错只报错不崩会话） ✅ 已完成
- [x] **P1 · 变量面板**：列出会话内存里所有全局量与类型，选中即求值到浮窗 —— notebook 变量视图的 ROOT 版 ✅ 已完成
- [ ] **P2 · 签名帮助 / 文档**：`Func(` 处列出全部重载原型，hover 显示反射字典里的 class guide 注释
- [ ] **P3 · 循环增强**：重发 cell 前自动 `.undo` 旧事务；REPL 报错行回标成 Neovim diagnostic

**不画的饼**（想清楚了，不做）：

- 参数位置感知的语义补全 —— 需要修 Cling 重建 ROOT，且大半收益被 clangd 覆盖
- 编辑器缓冲区局部变量的补全 —— 只有 Lisp 的 homoiconic reader 做得到（这正是 SLIME 的天赋），C++ 交给 LSP
- 调试器集成 —— Cling 没有 DAP

## License

MIT

## Acknowledgements

- **[AtomCode](https://atomcode.atomgit.com/)** — the terminal AI coding agent ([open source](https://atomgit.com/atomgit_atomcode/atomcode)) this plugin was developed end-to-end with, powered by **GLM-5.3-flash** from [Zhipu AI](https://open.bigmodel.cn/).
