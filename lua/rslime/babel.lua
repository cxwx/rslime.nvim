-- org babel `root` language: C++ src blocks executed in rslime's ROOT (Cling) session
--
--   #+begin_src root
--     TH1F h("h", "h", 10, 0, 10);
--     h.Fill(3);
--     h.GetEntries()
--   #+end_src
--
-- Shaped after Emacs' ob-lisp: SLIME owns the process, ob-lisp is just a thin adapter calling
-- slime-eval. Here rslime owns the ROOT process; this module registers a handler in
-- org.babel.ob.HANDLERS: the REPL started with the start key IS the session (started
-- automatically if not running), and every rslime feature lives on that same process.
--
-- EXPERIMENTAL. Requires xheisenbugx/org.nvim.
--
-- - default :results output: everything the code printed to the terminal. :results value: the
--   value of the last expression Cling printed (the "(double) 1" type prefix stripped)
-- - :includes :namespaces :defines :var :prologue :epilogue as in C++ blocks; :dir like a shell
--   session (gSystem->ChangeDirectory, and it stays in the REPL)
-- - execution blocks Neovim synchronously (Emacs' slime-eval does the same); each line waits at
--   most `timeout` for the REPL; the REPL itself is unharmed
-- - lines are sent one by one, each waiting for ROOT to come back to the prompt: writing more at
--   once (4 KB already does it locally) fills the pty input queue, the rest trickles in while ROOT
--   is busy with a statement — the terminal is in canonical mode then, and the tty driver raw-
--   echoes that input (no prompt), interleaved with ROOT's own echo, and the result becomes
--   unreadable. Up to 1 KB in one write is fine
-- - a Ctrl-U is sent first: it clears any unsubmitted input sitting on the prompt (harmless on an
--   empty line, display unchanged), otherwise it would be glued in front of the first line
-- - more than one prompt shape is recognized: after .@ typed in the REPL, ROOT uses its built-in
--   root [N] prompt for the next input line before switching back to the user's (ROOT 6.43.01)
-- - foreign input (rslime injects its helper with .L: sent once per REPL start when completion is
--   on) being processed while our line goes out makes the tty driver raw-echo our line first (no
--   prompt): a REPL we started ourselves waits at least 1.2 s (rslime sends that at 800 ms), and
--   when other input is glued after the prompt we wait for it to be processed; whatever escapes
--   both is recognized and dropped when the result is collected
-- - before sending, the code is checked against the prompt's rules; a bad block is not sent at
--   all (nothing half-done left in the REPL): unclosed brackets / quotes / block comments; string
--   or char literals spanning lines (Cling's prompt stays on the continuation line, and it never
--   executes even once the quote is closed); a line ending inside a raw string (at the prompt that
--   is not a continuation — it makes Cling spray a screen of errors and stop evaluating, ROOT
--   6.43.01, only a restart helps); the last line ending with a backslash, or with else (the
--   prompt returns to the main prompt as usual and takes the end marker as the else branch)
-- - blank lines in the code are not sent, tabs become spaces: the prompt echoes every input line,
--   and the result is obtained by stripping the echo
-- - output is read from the terminal buffer (same as rslime's rpc): lines wider than the REPL
--   window are wrapped; a code line's echo reaches at most the window's second-to-last column
--   (the line editor keeps the last one), and when a code line stops exactly there the terminal
--   gains a one-space row, dropped when collecting (see drop_fit_space: only full rows ending
--   with a code line's tail count, so a single space printed by the code itself is unaffected)
-- - a statement reading the keyboard (cin / scanf / getchar) eats the end marker: that is an
--   error, and the code's state is left in the REPL
-- - speed: ROOT's prompt takes ~8 ms per character, while Cling executes a line in a few ms
--   (piping into root has no such overhead; nothing to do with Neovim). So one block takes
--   ≈ 8 ms × characters: ~0.2 s for a short block, ~8 s for 1 KB
-- - the markers are two integer literals (0x186a0, recognized by the value Cling prints), 14
--   characters for both; they do not go through rslime's helper, see FUTURE below
--
-- FUTURE: rslime's rpc.ask() force-.L's the helper again after a timeout, and on this machine's
--   ROOT 6.43.01 the helper's functions lose their JIT after a second load (reproducible without
--   nvim:
--   printf '.L rslime_helper.C\nrslime_mark("1","X")\n.L rslime_helper.C\nrslime_mark("2","X")\n' | root -l
--   the second call prints nothing, unresolved std::__str_find_first_not_of[abi:...]).
--   So after any RPC timeout in rslime, eval / inspect / completion are dead until a restart;
--   it should only inject on a new process (on_exit already calls rpc.reset()).
--   The markers here therefore bypass the helper: integer literals are short enough, a printf
--   line would be 30+ characters.
-- FUTURE: non-blocking execution only has the two paths where org.nvim owns the process
--   (org.babel.session is async; rslime's REPL is not its session): a handler with a session
--   table (family + repl command) makes org.nvim start its own ROOT and feed it the code through
--   a temp file one line at a time — a second process next to the <F2>s REPL; or a one-off cmd
--   step (root -b -q tempfile), a fresh ROOT per block, no session. Async AND rslime's REPL
--   would take a plugin change (org.nvim letting a handler return the result asynchronously).
--   fn steps are synchronous, useless here. Neither is done: the point is rslime's REPL.
-- FUTURE: an unclosed raw string reaching the prompt leaves ROOT dead — that is Cling's problem;
--   what can be done is keeping it out (M.check) and recognizing the dead REPL so the user
--   restarts. Typing it by hand in the REPL cannot be intercepted.
-- FUTURE: big blocks could go through a temp file loaded with .L (no per-character overhead),
--   but that is one transaction for the whole file and it prints no expression values — not the
--   same thing as feeding the prompt. Not done.

local M = {}

local opts = { timeout = 30000 } -- ms: per sent line, the cap on waiting for the REPL to answer (ROOT startup included)
local seq = math.random(100000, 999999) -- each request consumes two: begin marker and end marker

local IDLE = 500 -- ms: terminal silent this long -> take a look at where the REPL is sitting
local QUIET = 150 -- ms: after the begin marker, terminal silent this long -> nothing else is glued after the prompt
local POLL = 10 -- ms: terminal polling interval
local SETTLE = 3000 -- ms: after the begin marker's value line, if the last input line still isn't recognizable as a prompt
                   -- (or other input stays glued after the prompt) this long, accept it as it is
local WINDOW = 400 -- lines: the marker's value line can only be within this many lines from the end
local START_SETTLE = 1200 -- ms: for a REPL we started ourselves, the begin marker waits at least this long (see M.run step 1)

-- Cling's error for an unclosed raw string (the leading file name ROOT_prompt_N varies across
-- versions, only the tail is matched); after spraying it, the REPL only echoes, never evaluates
local DEAD = "error: raw string missing terminating delimiter"
local DEAD_MSG =
  "root: the REPL stopped evaluating: an unclosed raw string made Cling error out (ROOT 6.43.01). Restart ROOT: :lua require('rslime.repl').restart()"

-- ROOT's built-in continuation prompt "root (cont'ed, cancel with .@) [N]" (the user's custom
-- main prompt does not affect it); a line ending with it = the REPL is waiting for more input
local CONT = "root %(cont'ed, cancel with %.@%) %[%d+%]"
local CONT_BARE = CONT .. "%s*$"

local ob -- org.babel.ob, set by M.setup

-- the REPL started and running; when this call started it, also return the time it started (ms)
local function ensure_running()
  local repl = require("rslime.repl")
  if repl.is_running() then return repl end
  -- same as rslime's send_raw: start it if not running
  local t0 = vim.uv.now()
  if not pcall(repl.start) then
    require("rslime").setup({}) -- loaded but never set up: use its defaults
    repl.start()
  end
  if not repl.is_running() then
    error("root: rslime's REPL failed to start (is root on your PATH?)", 0)
  end
  return repl, t0
end

-- markers: the prompt echoes input and Cling prints expression values: send 0x186a0 and the
-- terminal gains a "(int) 100000" line
local function literal(n)
  return string.format("0x%x", n)
end

-- a value line Cling printed, "(int) 100000" -> "100000"
local function value_of(l)
  return l:match("^%b()%s+(%d+)$")
end

-- a prompt as a Lua pattern: escaped, the counter replaced with %d+ (it changes every line)
local function prompt_pat(prompt)
  return (vim.pesc(prompt):gsub("%d+", "%%d+"))
end

-- digits replaced with #: prompt comparison ignoring the counter
local function digits(s)
  return (s:gsub("%d+", "#"))
end

-- sitting on the continuation prompt (input incomplete, waiting for more)
local function cont(tail)
  return tail:match(CONT_BARE) ~= nil
end

-- recognized main prompts (Lua patterns)
local known = {}

local function know(prompt)
  local pat = prompt_pat(prompt)
  if not vim.list_contains(known, pat) then known[#known + 1] = pat end
end

-- sitting on a recognized main prompt (possibly glued after output without a newline)
local function at_main(tail)
  for _, pat in ipairs(known) do
    if tail:match(pat .. "$") then return true end
  end
  return false
end

-- a: the prompt part in the begin marker's echo (the echo line minus its trailing marker);
-- b: the current last input line. Same main prompt (counter may differ) -> return the prompt:
-- taken from b, so anything glued after the prompt in b (rslime's injected .L) is excluded.
-- Different prompts -> nil
function M.same_prompt(a, b)
  local function common(x, y)
    local n = 0
    while n < #x and n < #y and x:sub(n + 1, n + 1) == y:sub(n + 1, n + 1) do
      n = n + 1
    end
    return n
  end
  local ra, rb, prompt = a, b, ""
  while true do
    local n = common(ra, rb)
    prompt, ra, rb = prompt .. rb:sub(1, n), ra:sub(n + 1), rb:sub(n + 1)
    if ra == "" then return prompt end -- a exhausted: anything left in b is other input glued after the prompt
    if rb == "" or not (ra:match("^%d") and rb:match("^%d")) then return end -- b is only half a prompt, or the two differ
    local na, nb = ra:match("^%d+"), rb:match("^%d+") -- they differ in the counter: skip it and keep comparing
    prompt, ra, rb = prompt .. nb, ra:sub(#na + 1), rb:sub(#nb + 1)
  end
end

-- the terminal's last non-blank line (the blank filler rows below the window don't count):
-- text, 0-based line number, total line count
local function tail_key(bufnr)
  local text, idx, n = "", -1, 0
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    n = vim.api.nvim_buf_line_count(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, math.max(0, n - 40), n, false)
    for i = #lines, 1, -1 do
      if lines[i]:match("%S") then
        text, idx = lines[i], n - #lines + i - 1
        break
      end
    end
  end
  return text, idx, n
end

-- this line is a clean main prompt (nothing else glued after it): some earlier terminal line
-- starts with it (those lines are prompt + the input of the time)
local function seen_before(bufnr, tail)
  local d = digits(tail)
  if d == "" then return false end
  local _, idx = tail_key(bufnr)
  for _, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, math.max(0, idx - 300), idx, false)) do
    if digits(l):sub(1, #d) == d then return true end
  end
  return false
end

-- after line `from` (0-based), within the last WINDOW lines: the line number (0-based) of the
-- last value line "(int) val"
local function find_value(bufnr, from, val)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  local n = vim.api.nvim_buf_line_count(bufnr)
  local lo = math.max(from, n - WINDOW)
  local lines = vim.api.nvim_buf_get_lines(bufnr, lo, n, false)
  for i = #lines, 1, -1 do
    if value_of(lines[i]) == val then return lo + i - 1 end
  end
end

-- is this REPL already dead from an unclosed raw string (after line `from`)
local function dead(bufnr, from)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return false end
  for _, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, math.max(0, from), -1, false)) do
    if l:find(DEAD, 1, true) then return true end
  end
  return false
end

-- next segment of a wrapped echo: does l continue `pending` (a whole code line) after its
-- `seen`-th character (a space at the wrap point may have been eaten by the terminal)?
-- returns: is echo, pending not yet fully echoed, characters seen so far
local function continues(l, pending, seen)
  if l == "" then return false, nil, seen end
  if l:sub(1, 1):match("%S") and pending:sub(seen + 1, seen + 1):match("%s") then seen = seen + 1 end
  local n = math.min(#l, #pending - seen)
  if pending:sub(seen + 1, seen + n) == l:sub(1, n) then
    seen = seen + n
    return true, seen < #pending and pending or nil, seen
  end
  return false, nil, seen
end

local WRAP_MIN = 24 -- a wrapped echo's first segment is at least this long; shorter coincidences are not echoes

-- loose version: a line ending with some code line (or with its beginning: first segment of a
-- wrap) counts as echo. Used only when the strict version cannot recognize the prompt; output
-- that happens to end with a code line can be wrongly dropped
function M.strip_echo_loose(lines, sent)
  local body = {}
  for _, s in ipairs(sent) do
    s = s:gsub("%s+$", "")
    if s ~= "" then body[#body + 1] = s end
  end
  local out, pending, seen = {}, nil, 0 -- pending: the code line currently being echoed; seen: characters shown so far
  for _, raw in ipairs(lines) do
    local l = raw:gsub("%s+$", "")
    local echo = false
    if pending then
      echo, pending, seen = continues(raw, pending, seen)
    end
    if not echo then
      for _, b in ipairs(body) do
        if l:sub(-#b) == b then
          echo, seen = true, #l
        else
          -- first segment of a wrap: the line ends with this code line's beginning
          local k = #b > WRAP_MIN and l:find(b:sub(1, WRAP_MIN), 1, true) and math.min(#l, #b) - 1 or 0
          while k >= WRAP_MIN and l:sub(-k) ~= b:sub(1, k) do k = k - 1 end
          if k >= WRAP_MIN then pending, seen, echo = b, #raw - (#l - k), true end
        end
        if echo then break end
      end
    end
    if not echo then out[#out + 1] = raw end
  end
  while out[#out] == "" do out[#out] = nil end -- the end marker brings its own trailing blank line
  return out
end

-- is the segment `rest` after the prompt in an echo line the beginning of code line b? The
-- leading spaces are ambiguous (the prompt carries one, a wrap point eats one), so align from
-- each side's first non-blank character. Returns how many characters of b have appeared; no
-- non-blank in rest -> nil
local function head(b, rest)
  local k, s = b:match("^%s*()"), rest:match("^%s*()") -- position of the first non-blank character
  local r = rest:sub(s):gsub("%s+$", "")
  if r == "" or b:sub(k, k + #r - 1) ~= r then return end
  return k - 1 + #rest - s + 1
end

-- strict version: a line is an echo iff it carries a prompt (main or continuation) followed by
-- the beginning of some code line (later segments of a wrap follow); everything else is output.
-- A prompt not at column 0 counts too: when the previous output had no newline it is glued after
-- it, and that leading part is output. A line carrying a prompt but not our code is the echo of
-- foreign input (rslime injecting its helper's .L: once per REPL start when completion is on;
-- otherwise triggered by its own RPC requests) — dropped. A line right after it, without a
-- prompt, exactly the next code line due to be echoed, is also an echo: it was sent while ROOT
-- was busy processing foreign input and the tty driver raw-echoed it first (M.run step 1 tries
-- to avoid that). If the end marker's echo cannot be matched, return nil and the caller falls
-- back to the loose version
-- prompts: the main prompt (string), or a list of recognized patterns
local function strip_strict(lines, sent, prompts)
  if type(prompts) == "string" then prompts = prompts ~= "" and { prompt_pat(prompts) } or nil end
  if not prompts or #prompts == 0 then return end
  local body = {}
  for i, s in ipairs(sent) do body[i] = (s:gsub("%s+$", "")) end
  local out, pending, seen, expect, ok_end, foreign = {}, nil, 0, 2, false, false -- expect: next code line due to be echoed (1 is the begin marker); foreign: previous line was foreign input's echo
  for _, raw in ipairs(lines) do
    local echo, pre = false, nil
    if pending then
      local p
      echo, p, seen = continues(raw, pending, seen)
      if echo and not p then expect = expect + 1 end
      pending = p
      foreign = false
    end
    if not echo then
      local l = raw:gsub("%s+$", "")
      local rest
      for _, pat in ipairs(prompts) do -- not anchored at column 0: the prompt glues after unterminated output
        pre, rest = l:match("(.-)" .. pat .. "(.*)$")
        if pre then break end
      end
      if not pre then pre, rest = l:match("(.-)" .. CONT .. "(.*)$") end
      if pre then
        echo = true
        local mine = false
        for i = expect, #body do
          local k = head(body[i], rest)
          if k then
            pending, seen = k < #body[i] and body[i] or nil, k
            expect = k < #body[i] and i or i + 1
            ok_end = ok_end or i == #body
            mine = true
            break
          end
        end
        foreign = not mine
      elseif foreign and expect <= #body and l == body[expect] then
        -- no prompt, and byte-identical to the next code line due: our line went out while ROOT
        -- was busy with foreign input, the tty driver raw-echoed it first, the real echo follows
        -- (a wrapped long line is not recognized, stays in the result)
        echo = true
        foreign = false
      else
        foreign = false
      end
    end
    if not echo or (pre and pre ~= "") then out[#out + 1] = pre or raw end
  end
  if not ok_end then return end
  while out[#out] == "" do out[#out] = nil end
  return out
end

-- when a code line's echo stops exactly on the terminal's last column (the row is cols - 1 cells
-- wide in the terminal, wrapped continuation rows too), ROOT's line editor emits a space first
-- and moves back (observed in a typescript capture); a code line ending right there leaves that
-- space at the start of the next row: a one-space line. If the next line is more code, that
-- space gets overwritten — harmless. Drop such lines.
-- Only full rows ending with some code line's tail count: echo rows look like that (the full row
-- is exactly that code line's last row, so it ends with its tail), and a single space after a
-- full row the code itself printed is kept. A single space after an echo row is indistinguishable
-- from one the code printed — dropped either way. A tail of at least 8 bytes counts, so a
-- one-character code line doesn't make everything look like its tail.
-- cols: terminal width in cells, unknown -> no dropping; sent: the lines sent (the two markers
-- at the ends are not code)
local function drop_fit_space(lines, cols, sent)
  if not cols then return lines end
  local code = {} -- code lines (trailing blanks stripped)
  for i = 2, #sent - 1 do
    code[#code + 1] = (sent[i]:gsub("%s+$", ""))
  end
  local out, full = {}, false
  for _, l in ipairs(lines) do
    if full and l == " " then
      full = false
    else
      out[#out + 1] = l
      full = false
      if vim.fn.strwidth(l) >= cols - 1 then
        local t = l:gsub("%s+$", "")
        for _, s in ipairs(code) do
          local n = math.min(#t, #s) -- the shorter one is entirely the longer one's tail
          if n >= 8 and t:sub(-n) == s:sub(-n) then
            full = true
            break
          end
        end
      end
    end
  end
  return out
end

-- the prompt echoes every input line (prompt + code, wrapped into segments past the window
-- width): keep only what the code itself printed.
-- cols: terminal width in cells, see drop_fit_space
function M.strip_echo(lines, sent, prompts, cols)
  lines = drop_fit_space(lines, cols, sent)
  return strip_strict(lines, sent, prompts) or M.strip_echo_loose(lines, sent)
end

-- the value of an expression Cling printed: "(double) 1.0000000" -> "1.0000000"
local function last_value(text)
  local v
  for l in (text .. "\n"):gmatch("(.-)\n") do
    v = l:match("^%b()%s+(.+)$") or v
  end
  return v
end

-- is the R of an R" at position i in `line` preceded by an identifier's tail: an identifier
-- ending in R followed by a plain string (WORD"x") is not a raw string; the u8 / L / u / U
-- prefixes are
local function plain_r(line, i)
  local before = line:sub(1, i - 1)
  return before:match("[%w_]$") ~= nil and not before:match("^[LluU]8?$") and not before:match("[^%w_][LluU]8?$")
end

-- pre-send check (by the prompt's rules): returns the error message, nil if fine
--  - code with unclosed brackets / quotes / block comments: Cling sits on the continuation
--    prompt waiting for more (a block comment's continuation cannot be exited with .@)
--  - string / char literals spanning lines (a trailing backslash included): Cling's prompt
--    stays on the continuation line and never executes, even once the quote is closed (ROOT
--    6.43.01, only .@ gets back)
--  - an unclosed raw string: see the FUTURE at the top
--  - last line ending with a backslash: the end marker would be spliced onto it
--  - last line ending with else: the prompt only counts brackets and quotes, so it returns to
--    the main prompt as usual and takes the next input line (the end marker) as the else branch.
--    Earlier lines are fine — more lines follow
function M.check(lines)
  local state, quote = "code", nil -- code / string / comment
  local open = { ["{"] = true, ["("] = true, ["["] = true }
  local close_of = { ["}"] = "{", [")"] = "(", ["]"] = "[" }
  local depth = { ["{"] = 0, ["("] = 0, ["["] = 0 }
  for k, line in ipairs(lines) do
    local i = 1
    local word, lastw, last = "", "", "" -- identifier being assembled in code, last completed one, last character
    while i <= #line do
      local c, d = line:sub(i, i), line:sub(i, i + 1)
      if state == "comment" then
        local j = line:find("*/", i, true)
        if not j then break end
        state, i = "code", j + 2
      elseif state == "string" then
        if c == "\\" then
          i = i + 2
        elseif c == quote then
          state, i = "code", i + 1
        else
          i = i + 1
        end
      elseif d == "//" then
        break
      elseif d == "/*" then
        state, i = "comment", i + 2
      elseif d == 'R"' and not plain_r(line, i) then
        local delim = line:sub(i + 2):match("^([^()]*)%(")
        local close = delim and (")" .. delim .. '"')
        local j = close and line:find(close, i + #delim + 3, true)
        if not j then
          return "line " .. k .. ": raw string not closed on its own line: at Cling's prompt it makes the REPL stop evaluating for good (restart needed). Keep the raw string on one line"
        end
        i = j + #close
      elseif c == '"' or (c == "'" and not line:sub(i - 1, i - 1):match("%d")) then -- the ' in 1'000'000 is not a char literal
        state, quote, i = "string", c, i + 1
      else
        if c:match("[%w_]") then
          word = word .. c
        else
          lastw, word = word ~= "" and word or lastw, ""
        end
        last = c
        if open[c] then
          depth[c] = depth[c] + 1
        elseif close_of[c] then
          depth[close_of[c]] = depth[close_of[c]] - 1
        end
        i = i + 1
      end
    end
    if state == "string" then
      return "line " .. k .. ": string / char literal not closed on its own line: Cling's prompt stays on the continuation line waiting for more and never executes it (even once the quote is closed; only .@ gets back). Nothing was sent. Put it on one line"
    end
    -- else followed only by blanks / comments (else { is the bracket check's business)
    if k == #lines and (word == "else" or (lastw == "else" and (last == "" or last:match("%s")))) then
      return "last line ends with else: Cling takes the next input line as its branch. Nothing was sent"
    end
  end
  if state == "comment" then return "incomplete code: block comment /* ... */ not closed, nothing was sent" end
  local brackets = { { "{", "braces", "}" }, { "(", "parens", ")" }, { "[", "brackets", "]" } }
  for _, b in ipairs(brackets) do
    local d = depth[b[1]]
    if d ~= 0 then
      return "incomplete code: " .. b[2] .. (d > 0 and (" missing " .. d .. " " .. b[3]) or (" extra " .. -d .. " " .. b[3])) .. ", nothing was sent"
    end
  end
  if lines[#lines] and lines[#lines]:match("\\%s*$") then return "last line ends with a backslash: the end marker would be spliced onto it, nothing was sent" end
end

-- the code to execute: two markers around it, sent line by line
function M.run(text)
  local repl, started = ensure_running()
  local job, bufnr = repl.job_id(), repl.bufnr()
  if not job or not bufnr then error("root: rslime's REPL has no terminal (rslime changed?)", 0) end
  local code = {}
  for l in ((text:gsub("\r", ""):gsub("\t", " ")) .. "\n"):gmatch("(.-)\n") do
    if l:match("%S") then code[#code + 1] = l end
  end
  local problem = M.check(code)
  if problem then error("root: " .. problem, 0) end
  if dead(bufnr, math.max(0, vim.api.nvim_buf_line_count(bufnr) - 4000)) then error(DEAD_MSG, 0) end
  if cont(tail_key(bufnr)) then
    error("root: the REPL has unfinished input (sitting on the continuation prompt): finish it in the REPL, or send .@ to cancel", 0)
  end

  local a = seq
  seq = seq + 2
  local bmark, emark = literal(a), literal(a + 1)
  local bval, eval = tostring(a), tostring(a + 1) -- the two markers' values as Cling prints them
  local sent = vim.list_extend({ bmark }, code)
  sent[#sent + 1] = emark
  local _, idx0 = tail_key(bufnr) -- the line the prompt is on (0-based)
  local from = math.max(0, idx0) -- this run's output all starts at this line: right after a REPL start the bottom of the terminal is blank filler, and new content fills in from the top

  local why -- diagnosis when stopping early: gone / dead / cont / stdin / idle
  -- wait until cond(tail, idx) holds. tail: last non-blank terminal line, line number idx, must be past idx0 (nothing moved on the original line -> not yet);
  -- quiet: stay quiet this long first (more echo of other input may still appear after the prompt); limit: cap (default timeout).
  -- When things go silent (IDLE) let diag take a look; ROOT exited / REPL dead stops right away
  local function wait(cond, idx0, quiet, diag, limit)
    local key, since, probed = nil, vim.uv.now(), false
    local ok = vim.wait(limit or opts.timeout, function()
      if not repl.is_running() then
        why = "gone"
        return true
      end
      local tail, idx = tail_key(bufnr)
      if tail .. idx ~= key then key, since, probed = tail .. idx, vim.uv.now(), false end
      local now = vim.uv.now()
      if now - since < quiet then return false end
      if idx > idx0 and cond(tail, idx) then return true end
      if now - since < IDLE then return false end
      if not probed then
        probed = true
        if dead(bufnr, from) then
          why = "dead"
          return true
        end
        if diag and diag(tail) then return true end
      end
      return false
    end, POLL)
    return ok and why == nil
  end

  local function stop(detail) -- stop waiting: raise, #+RESULTS: stays untouched
    vim.api.nvim_echo({ { "" } }, false, {})
    if why == "gone" then error("root: the ROOT process exited (.q in the code?)", 0) end
    if why == "dead" then error(DEAD_MSG, 0) end
    error("root: " .. detail, 0)
  end

  vim.api.nvim_echo({ { "root: executing in the rslime REPL...", "Comment" } }, false, {})
  vim.cmd("redraw")

  -- 1. begin marker. The value line carries its own newline, so the line after it is a clean
  --    prompt: remember its shape (per-line sending relies on it to tell "back at the prompt").
  --    rslime may send a .L line into the REPL to inject its helper (once per start at 800 ms
  --    when completion is on; otherwise triggered by its own RPC requests), possibly glued right
  --    after this prompt: so wait for the terminal to settle, and only take the prompt up to
  --    where it matches the one in the echo.
  --    After .@ typed in the REPL, ROOT uses its built-in root [N] prompt for the next input
  --    line (before switching back to the user's): then the one in the echo and the current one
  --    don't match, so check whether the current one was recognized before, or appears in
  --    earlier terminal lines. If neither, keep waiting (most likely .L still processing); past
  --    SETTLE accept it as is (a prompt whose shape changed?)
  --    If this run started the REPL: rslime sends things into it 800 ms after start
  --    (startup_cmds, the .L when completion is on), and sending our code right as ROOT is busy
  --    processing them makes the tty driver raw-echo our line first (no prompt) — hence the floor
  local main -- this block's recognized main prompt
  local bidx, t0 = nil, vim.uv.now()
  vim.api.nvim_chan_send(job, "\21" .. bmark .. "\n") -- Ctrl-U: clear unsubmitted input on the prompt
  why = nil
  local ok = wait(function(tail, idx)
    if started and vim.uv.now() - started < START_SETTLE then return false end
    bidx = find_value(bufnr, from, bval)
    if not bidx or idx <= bidx then return false end -- no new input line yet after the value line (the value line itself also looks "seen before")
    local lead = bidx > 0 and vim.api.nvim_buf_get_lines(bufnr, bidx - 1, bidx, false)[1] or ""
    if lead:sub(-#bmark) ~= bmark then return false end
    main = M.same_prompt(lead:sub(1, -#bmark - 1), tail)
    if main then
      -- more input glued after the prompt: submitted (.L and the like) — wait for ROOT to finish
      -- it and produce a fresh clean prompt line before sending code; one that never cleans up
      -- (someone typing, not submitted) won't, past SETTLE accept it as it is
      return tail == main or vim.uv.now() - t0 > SETTLE
    end
    if at_main(tail) then return true end
    if not seen_before(bufnr, tail) and vim.uv.now() - t0 <= SETTLE then return false end
    main = tail
    return true
  end, idx0, QUIET, nil)
  if not ok then
    stop(string.format("the REPL did not answer within %d ms (ROOT failed to start, or something else is sitting on the prompt)", opts.timeout))
  end
  if main then know(main) end
  local function at_prompt(tail) -- on a prompt: the main one, or the continuation one while input is incomplete
    return at_main(tail) or cont(tail)
  end

  -- 2. the code, line by line: each line waits for the REPL to come back to the prompt before
  --    the next one goes out (see the top)
  for k, line in ipairs(code) do
    local _, idx = tail_key(bufnr)
    vim.api.nvim_chan_send(job, line .. "\n")
    why = nil
    if not wait(at_prompt, idx, 0, nil) then
      stop(string.format("line %d got no prompt back within %d ms (the code may still be running, or waiting for keyboard input):\n%s", k, opts.timeout, line))
    end
  end

  -- 3. end marker. If the REPL sits on the continuation prompt (the checks above missed it), it
  --    would be taken as the code's tail: get back to the prompt first
  if cont(tail_key(bufnr)) then
    local _, idx = tail_key(bufnr)
    vim.api.nvim_chan_send(job, ".@\n")
    wait(at_prompt, idx, 0, nil, 2000) -- wait for the prompt (2 s cap: a block comment's continuation cannot be exited with .@): otherwise the very next block walks straight into a continuation prompt
    stop("incomplete code, Cling is waiting for more; sent .@ to get back to the prompt")
  end
  local _, idx = tail_key(bufnr)
  local eidx
  vim.api.nvim_chan_send(job, emark .. "\n")
  why = nil
  ok = wait(function()
    eidx = find_value(bufnr, from, eval)
    return eidx ~= nil
  end, idx, 0, function(tail)
    if cont(tail) then
      why = "cont"
      return true
    end
    -- the end marker was echoed but not evaluated = something (cin and friends) consumed it; it
    -- is still waiting for more input (int a, b; cin >> a >> b) so feed it another line
    if tail == emark or at_prompt(tail) then
      if tail == emark then vim.api.nvim_chan_send(job, ".@\n") end
      why = "stdin"
      return true
    end
  end)
  if not ok then
    if why == "stdin" then
      stop("a statement reads the keyboard (cin / scanf / getchar)? the end marker was consumed; the code's state is left in the REPL")
    end
    stop(string.format("the end marker got no answer within %d ms (the code may still be running)", opts.timeout))
  end
  vim.api.nvim_echo({ { "" } }, false, {})

  -- the terminal's width (cells): the REPL window minus sign / fold columns; window not open ->
  -- Neovim's own columns
  local win = vim.fn.bufwinid(bufnr)
  local info = win ~= -1 and vim.fn.getwininfo(win)[1]
  local cols = info and (info.width - (info.textoff or 0)) or vim.o.columns
  local out = M.strip_echo(vim.api.nvim_buf_get_lines(bufnr, bidx + 1, eidx, false), sent, known, cols)
  local nerr = 0
  for _, l in ipairs(out) do
    if l:match(":%d+:%d+: error:") or l:match("^Error in <") then nerr = nerr + 1 end
  end
  if nerr > 0 then
    vim.notify("root: " .. nerr .. " errors, see #+RESULTS: and the REPL", vim.log.levels.WARN)
  end
  return table.concat(out, "\n")
end

-- a C++ string literal
local function c_string(s)
  return '"' .. s:gsub('[\\"]', "\\%0") .. '"'
end

-- the full code to execute (org-babel-expand-body:C++'s :includes :defines :namespaces, :var);
-- with ctx, :dir is included
function M.code(text, args, vars, ctx)
  local langs = require("org.babel.langs")
  local unquote = require("org.babel.blocks").unquote
  local lines = {}
  local function add(s)
    if s and s ~= "" then lines[#lines + 1] = s end
  end
  for _, x in ipairs(langs.words(args.includes)) do
    add(x:match("^<") and ("#include " .. x) or ('#include "' .. x .. '"'))
  end
  local dw = langs.words(args.defines)
  local k = 1
  while k <= #dw do
    add("#define " .. dw[k] .. (dw[k + 1] and (" " .. dw[k + 1]) or ""))
    k = k + 2
  end
  for _, x in ipairs(langs.words(args.namespaces)) do add("using namespace " .. x .. ";") end
  if ctx and args.dir then add("(void)gSystem->ChangeDirectory(" .. c_string(ctx.cwd) .. ");") end
  for _, l in ipairs(langs.var_lines("cpp", vars, args)) do add(l) end
  add(unquote(args.prologue))
  add(text)
  add(unquote(args.epilogue))
  return table.concat(lines, "\n")
end

local handler = {}

-- what C-c C-v v shows / what tangle produces
function handler.expand(body, args, vars)
  return M.code(ob.body_text(body), args, vars)
end

-- the whole evaluation happens here, synchronously (a handler has no async escape hatch); an
-- error = an Emacs-style error, and org leaves #+RESULTS: untouched
function handler.prepare(body, args, vars, ctx)
  local out = M.run(M.code(ob.body_text(body), args, vars, ctx))
  return { value = ob.result_cond(args, out, last_value) }
end

---@param o table? { timeout?: integer } ms
function M.setup(o)
  opts = vim.tbl_deep_extend("force", opts, o or {})
  local ok
  ok, ob = pcall(require, "org.babel.ob")
  if not ok then
    error("rslime.babel: xheisenbugx/org.nvim is required for the org babel handler", 0)
  end
  ob.HANDLERS.root = handler
  return M
end

return M
