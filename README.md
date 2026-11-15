# rslime.nvim

Slime-style ROOT (CERN) REPL for Neovim. Zero dependencies — built on the internal terminal, no iron/conjure/toggleterm needed.

Organize your C++ code into Jupyter-style `// %%` cells and send them one by one to ROOT (Cling) for interactive execution. Kernel restart, `.undo`, and THttpServer visualization supported.

## What is this?

C++ has no official interactive interpreter, but CERN's [ROOT](https://root.cern/) ships one: [Cling](https://github.com/root-project/cling), a C++ interpreter based on Clang/LLVM. `root -l` opens a REPL where C++ statements run immediately — the de-facto standard for HEP (high energy physics) analysis.

rslime.nvim turns that REPL into a slime workflow: keep your code in ordinary `.cpp` files, split it into cells, and push each cell to the running interpreter — like [slime](https://github.com/jpalardy/vim-slime) or a Jupyter notebook, but for C++.

## Requirements

- Neovim 0.10+
- **[CERN ROOT](https://root.cern/download/)** on your PATH (`root -l` must start) — ROOT is an *external dependency*; it bundles the Cling C++ interpreter that powers the REPL. Install via package manager (e.g. `brew install root`) or build from source.

Neovim plugin dependencies: none.

## Features

- **Cells**: split code into blocks with `// %%` headers and send the one under the cursor; LSP wrapper structure (`#include`, `main()`, …) is skipped automatically and never leaks into the REPL

  ![send a cell](assets/feat_send.gif)
- **Run all**: execute every cell in order (optional per-cell delay to watch each block's output)
- **Run before / after**: run all cells above the cursor (re-run the setup part) or from the cursor down (Jupyter's *Run All Above* / *Run Selected and Below*)
- **Live eval**: `<leader>r0e` evaluates the word under the cursor (or the visual selection) in the running session and floats the result — hover `hist` and see its live entries/mean. Bad expressions show the compiler error in the float; the session never dies
- **Variable panel**: `<leader>r0v` lists every global in the session with its type; pick one to evaluate it — the notebook "variables view", ROOT edition
- **Signatures & docs**: `<leader>r0S` on `hist.Draw(` / `TH1F::Fill` floats every overload prototype at once, plus the class-guide doc string from the reflection dictionary when available
- **Error marking** *(opt-in)*: cling errors from a sent cell are marked back onto the source cell as diagnostics — `input_line` locations are mapped through the cell range
- **Inline eval** *(opt-in)*: short results land as virtual text at the end of the line instead of a float; long results still float, `:RslimeInlineClear` wipes the marks
- **Auto signatures** *(opt-in)*: typing `(` shows the live session's overload prototypes via the blink signature provider — LSP answers for buffer-known symbols, this source abstains (returns nil) unless the symbol exists in the session, so it only ever fills the gap LSP structurally cannot (`hist` built two cells ago, `.L`-loaded functions)

  ![auto signature](assets/feat_signature.gif)
- **Session draw**: `<leader>r0d` draws the word under the cursor in the live session — type-aware via the eval + reflection round-trip (stack objects get `.`, pointers `->`; `TTree` prompts for a draw expression; classes without `Draw` are rejected up front), then `Modified()+Update()` in the same cling transaction so the web canvas pops up in the browser. `<leader>r0D` overlays with `same`, `:RslimeDraw COLZ` passes any option; replay redraws with the session
- **Run-block inline** *(on by default)*: running a single block (`:RslimeSendCell`) re-evaluates the variables it declares/assigns and shows their values at the line end — a re-run that produced a different value is highlighted as *changed* (dap-virtual-text style); `run all/before/after` deliberately skip it
- **Session replay**: `<leader>r0p` re-sends every block you've sent this session (cells, lines, selections), in order — after a kernel restart, one key rebuilds the session; works across files
- **Live hover** (dap-style panel): `<leader>r0K` (its own key — your `K` / LSP hover stays untouched) evaluates the word under the cursor in the session; pointers are followed by `Dump()`, so you see data members with their current values (`fNcells 102 …`), not just an address; non-TObject classes fall back to `Print()`. The result opens as a persistent, focused `rslime-dump` panel with syntax-highlighted member/value/comment columns: `q`/`<Esc>` closes, `r` re-reads live memory, `<CR>`/double-click steps into a member object (`fXaxis ->…` → dump of the axis)

  ![live hover panel](assets/feat_hover.gif)
- **`rootrepl` filetype**: the REPL terminal buffer gets its own filetype (daprepl-style) — ftplugin ships an in-REPL `<C-c>` interrupt and a `C-x C-o` omnifunc; with blink.cmp, `per_filetype = { rootrepl = { "rslime" } }` gives live-session completion *inside* the REPL window
- **Kernel restart**: `.q` → `gSystem->Exit(0)` → force kill, three-level fallback; the REPL comes back automatically
- **Undo**: roll back the last n cling transactions (`:RslimeUndo 3`)
- **THttpServer**: one key to start it and open the browser — inspect variables and canvases from the background
- **Live-session completion** *(opt-in, off by default — LSP covers most of it)*: a [blink.cmp](https://github.com/Saghen/blink.cmp) source backed by the running REPL, for the one thing LSP can't do: symbols that only exist in the session — objects created interactively, `.L`-loaded functions, autoloaded classes

  ![live-session completion](assets/feat_completion.gif)
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
  send_keep_focus = true,          -- send without stealing focus: the cursor stays in the
                                   -- source buffer; false jumps to the REPL window on send
  http_port = 8080,                -- THttpServer port
  http_open = true,                -- open the browser after starting THttpServer
  completion = false,              -- opt-in: live-session completion (see below)
  diagnostics = false,             -- opt-in: mark cling errors back onto the sent cell
  inline_eval = false,             -- opt-in: short eval results as virtual text at the line end
  signature = false,               -- opt-in: auto signature help on `(` from the live session (blink);
                                   -- completion stays LSP's — the source abstains for buffer-known symbols
  run_block_inline = true,         -- after running ONE block (send cell), show that block's
                                   -- variable values inline; run all/before/after skip it
  run_block_inline_delay = 600,    -- ms to wait after sending before probing (let cling finish)
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
    sign = "S",                    -- overload prototypes + docs
    vars = "v",                    -- session variable panel
    replay = "p",                  -- re-send all blocks recorded this session
    hover = "K",                   -- live hover (Dump); NOT the K key itself
    inline_clear = "x",            -- wipe the buffer's inline eval results
    draw = "d",                    -- draw the word under the cursor (web canvas)
    draw_same = "D",               -- draw with "same" (overlay on the current pad)
  },
})
```

Mapping rules: `start/toggle/restart/quit/focus/http` are global; everything else (`cell/line/visual/file/undo/run_all/run_before/run_after/eval/sign/vars/replay/hover/inline_clear/draw/draw_same`) is buffer-local to c/cpp files. Set any suffix to `false` to disable it. `short_desc = true` swaps the verbose which-key labels for compact `"󰖯 before"`-style ones (Nerd Font required).

## Live-session completion (opt-in)

Off by default — for most code, LSP (clangd) completion is better. What LSP structurally cannot know is the state of the *running* session: the `hist` you built two cells ago, functions loaded with `.L`, classes pulled in by autoload. This source covers exactly that gap:

- `hist.Dra` → methods of the live object, with real prototypes
- `TH1F::Dra` → statics of a class (autoloaded on demand)
- bare `hi` → session globals + ROOT classes

It works by injecting a small C++ helper into the running interpreter (interpreted, nothing compiled) and talking to it through the REPL terminal with sentinel-delimited requests — the SLIME "ask the running image" trick, minus the socket. The same RPC channel is the base for the roadmap items below (variable eval, inspector).

Enable and wire into [blink.cmp](https://github.com/Saghen/blink.cmp) (v2):

```lua
require("rslime").setup({ prefix = "<leader>r0", completion = true, signature = true })

require("blink.cmp").setup({
  signature = { enabled = true },
  sources = {
    per_filetype = {
      cpp = { inherit_defaults = true, "rslime" },
      rootrepl = { "rslime" },  -- live-session completion inside the REPL window
    },
    providers = {
      rslime = {
        module = "rslime.blink",  -- completion + signature provider shipped by the plugin
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

No shim needed: blink requires provider modules without pcall, but lazy.nvim intercepts `require` and loads the owning plugin on demand — `module = "rslime.blink"` works with any lazy-loading style (`keys`, `ft`, `lazy = true`), same as every other blink source plugin.

Notes:
- Completion queries the session, not the buffer: a variable must be **sent to the REPL first** (`<leader>r0k`); buffer-only locals are LSP's job
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
| `RslimeSign` | Overload prototypes + docs for the identifier before the cursor |
| `RslimeVars` | Session variable panel — pick a global to evaluate |
| `RslimeReplay` | Re-send all blocks recorded this session, in order |
| `RslimeHover` | Live-session hover (Dump) on the word under the cursor |
| `RslimeUndo [n]` | `.undo n` — roll back cling transactions |
| `RslimeInlineClear` | Wipe the inline eval results in the buffer |
| `RslimeDraw [opt]` | Draw the word under the cursor in the session (opt = `same`, `COLZ`, …) |

Menus/pickers: the table above is code — `require("rslime.commands").menu()` returns `{ display, cmd, desc }` items, and `.all()` the full definitions (`range`, `nargs`, `run`). The `:Rslime*` commands themselves are registered from that same table. For a grouped view (e.g. [nvzone/menu](https://github.com/nvzone-menu)): `require("menu").open(require("rslime.menu").nvzone(), { mouse = true })` — 4 groups (session / send / run / inspect), one entry per command.

## Filetypes

The plugin ships two filetypes (dap-style):

- **`rootrepl`** — the REPL terminal buffer. In-REPL keys: `<C-c>` sends a real interrupt (`\3`), completion falls back to `C-x C-o` omnifunc when blink isn't wired
- **`rslime-dump`** — the persistent hover/panel buffer. Keys: `q` / `<Esc>` close, `r` re-read live memory (Dump values are a snapshot), `<CR>` / double-click on a member line steps into that member object

## Highlights

| Group | Default | Used by |
|---|---|---|
| `RslimeCellHeader` | `SpecialComment` | `// %%` cell headers |
| `RslimeInline` | `Special` | inline eval virtual text |
| `RslimeInlineChanged` | `DiagnosticVirtualTextWarn` | a re-run whose value changed (dap-virtual-text style) |

Override with `vim.api.nvim_set_hl(0, "RslimeInline", { ... })` after `setup()`.

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

## Roadmap

The original roadmap shipped end to end: sentinel RPC channel, live-session completion, variable eval & panel, signatures (manual + auto), error marking, replay, hover panel, inline eval, run-block inline and session draw — see [Features](#features). [`TODO.md`](TODO.md) holds the ideas deliberately *not* being built, each with the reason (measured, not guessed).

## License

MIT

## Acknowledgements

- **[Claude Code](https://claude.com/claude-code)** — the CLI coding agent this plugin's swank-style roadmap (sentinel RPC channel, live-session completion, eval/panel, signatures, error marking, replay, hover, draw) was designed, implemented and tested with, end to end on a live ROOT session
- **[GLM](https://www.z.ai/)** — the model (GLM, by Z.ai / Zhipu AI) powering the coding agents above through the whole journey
- **[AtomCode](https://atomcode.atomgit.com/)** — the open-source terminal AI coding agent the original cell/send workflow was developed with
