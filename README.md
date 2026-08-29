# dock.nvim

One shared, docked window that any number of plugins can show their buffers in,
in every tabpage.

Plugins that produce output — task runners, test runners, linters, REPLs, build
tools — each end up writing the same window-management code: where to split, how
big, how to keep the user's layout intact, what to do when the buffer is deleted.
dock does that once. A plugin hands over a buffer and a label; dock owns
the window, the tab bar, the numbering, and the focus rules.

```
┌────────────────────────────────────────────────────────┐
│ editor                                                 │
├────────────────────────────────────────────────────────┤
│ ✓ build [1:out|2:diag•] │ ⇪ 3:deploy │ ❯ 4:zsh         │
│ ...buffer contents...                                  │
└────────────────────────────────────────────────────────┘
```

Everything selectable in that bar is clickable, and has a number you can jump to.

## Requirements

Neovim >= 0.10 (for `'winfixbuf'`).

## Install

With Neovim 0.12's builtin plugin manager:

```lua
vim.pack.add({ "https://github.com/mbfoss/dock.nvim" })
```

Any other plugin manager works too. Calling `setup()` is optional — the `:Dock`
command exists and the defaults work untouched.

```lua
require("dock").setup({
  position = "bottom",   -- "bottom" | "top" | "left" | "right"
  size     = 0.22,       -- fraction of editor lines/columns
})
```

## Concepts

Three nouns, and only the first is yours to manage:

| | |
|---|---|
| **source** | one plugin's namespace. Claim it once, keep the handle. |
| **group**  | one tab. Has a label, an optional badge, and pages. |
| **page**   | one buffer inside a group. |

A group with a single page renders as one numbered tab, and selecting it — by
click or by number — shows that page. A group with several renders as a heading
plus a bracketed list of numbered page tabs, so the common case stays visually
quiet. The heading is only a label: the pages carry the numbers, starting at the
one the group would have had, and it is not itself clickable.

Groups belong to the panel, not to its window: closing the dock tears down only
that window, and reopening restores every tab exactly as it was.

### One dock, every tabpage

The panel is editor-wide, not per tabpage. Every Neovim tabpage shows the same
groups, the same tab bar and the same page — a build you started in one tabpage
is right there in the next, and jumping to a tab in one moves them all, because
there is only one panel to move.

What *is* per-tabpage is the window. Each tab shows or hides the dock on its own:

| | |
|---|---|
| `dock.open()` / `:Dock open` | show the dock in this tabpage |
| `dock.close()` / `:Dock close` | hide it here; the other tabpages keep theirs |
| `dock.close({ all = true })` / `:Dock! close` | hide it everywhere |

Hiding never touches the tabs themselves, so a dock closed in every tabpage
still has every group waiting for the next `open`. Closing a tabpage is just
that: its window goes, the panel and its groups do not.

Two smaller consequences worth knowing:

* Every open dock is a view of the same panel, so they all sit on the same page.
  Only one of them can be the size you dragged it to, and that ratio is shared —
  resize one and the next `open` uses it.
* `:wincmd T` on the dock window is really "new window in a new tabpage, close
  this one". The dock closes with it, and what lands in the new tabpage is a
  plain window showing that buffer.

## Using it from a plugin

```lua
local dock = require("dock")

-- once, at setup
local src   = dock.source("myplugin")

-- per unit of work
local group = src:group({
  label = "build",
  badge = { icon = "▶", hl = "DockBadgeOk" },
  busy  = true,
})
group:page({ buf = stdout_buf, label = "out" })

-- later
group:page({ buf = diag_buf, label = "diag", priority = 5 })
group:set_badge({ icon = "✓", hl = "DockBadgeOk" })
group:set_busy(false)
```

That is the whole integration. No window handling, no layout code.

### Buffer ownership and cleaning

dock **never deletes a buffer it did not create**, and never removes a tab on
its own. Pages are borrowed; the source owns them and is the only party that
knows when one has stopped mattering.

So there is no "close this tab" in dock — there is `clean`, a request to shed
what is no longer needed. `:Dock clean` asks every tab, `:Dock clean 3` asks the
one numbered 3, and each source answers by doing whatever is right for it:

```lua
local group = src:group({
  label    = "build",
  on_clean = function(g)
    if job_still_running then return end          -- ignoring the request is an answer
    vim.api.nvim_buf_delete(g.data.buf, { force = true })
    g:remove()                                    -- and the tab goes with it
  end,
})
```

A group with no `on_clean` keeps everything, which is the right default for a
tab whose buffers belong to something else. `group:clean()` reports whether the
tab is gone afterwards — that is how `:Dock clean` counts what it closed, not by
deciding anything itself.

`group:remove()` is the other half: it detaches the tab and leaves the buffers
alone, for a source tearing down its own tabs (`source:clear()` does it for all
of them). Between them, every removal is the source's call.

### Busy

`busy` says the group is still working. Set it in the spec or with
`group:set_busy(…)`; it is a plain flag, unrelated to the badge glyph, and it
says nothing about lifetime — the panel prefers a busy tab when it has to pick
one to show, and a `focus = "always"` group keeps the view until it stops being
busy. Whether a tab may go is `on_clean`'s business, though a source is free to
consult `is_busy()` there.

### Who gets the view

A group declares how eagerly it takes over the panel, rather than the panel
guessing:

| `focus` | behaviour |
|---|---|
| `"auto"` (default) | takes over when it appears, unless the user is working inside the dock |
| `"never"` | never steals the view — for background or dependency work |
| `"always"` | takes over even when the dock is focused, and keeps the view until it stops being busy — for an explicit user action such as a restart |

Within a group, `priority` decides which page wins. The panel advances to a new
page only when it **outranks** what is already on screen, so a low-priority log
buffer appearing mid-run never pulls the user off the output they are watching.
Pass `activate = true` on a page, or call `group:activate()`, to insist.

### Badges

A badge is the glyph drawn before a tab's label. dock has no status vocabulary
of its own — you supply the badge, and the meaning is whatever your plugin says
it is:

```lua
local group = src:group({
  label = "deploy",
  badge = { icon = "⇪", hl = "DockBadgeWarn" },
})
group:set_badge({ icon = "✓", hl = "DockBadgeOk" })  -- nil drops the glyph
```

| field | |
|---|---|
| `icon` | single-cell glyph |
| `hl` | highlight group for the glyph |

A badge is presentation only; whether a tab is still working is the group's
`busy` flag, and whether it goes away is `on_clean`.

The `DockBadge*` highlight groups below are there to hint from, but any
highlight group works.

### Unread output

dock watches page buffers and marks a tab with `•` when it gains lines while
not visible. Nothing to wire up.

## Command

`:Dock` — toggle. With a number, jump to that tab.

| | |
|---|---|
| `:Dock` | toggle the dock in this tabpage |
| `:Dock 3` | jump to tab 3 (same as `:Dock jump 3`) |
| `:Dock open` / `close` / `toggle` | in this tabpage |
| `:Dock! close` | hide the dock in every tabpage |
| `:Dock next` / `prev` | step through tabs, wrapping |
| `:Dock shell` | open a shell in its own tab |
| `:Dock shell echo 3` | run that command instead of a shell |
| `:Dock clean` | ask every tab to shed what it no longer needs |
| `:Dock clean N` | ask only tab `N` |

Rename it with `setup({ command = "Tray" })`, or disable it with
`command = false`.

## Builtin: shell

dock ships one source of its own — shells in dock tabs:

```lua
require("dock").shell({ cwd = vim.fn.getcwd() })
require("dock").shell({ cmd = "echo 3" })
```

Every shell is its own tab, labelled with the command it runs (`zsh`, `echo 3`),
so each one is a single number away in the winbar. A tab stays busy while its
shell is running and survives the command exiting, so the scrollback stays
readable; `:Dock clean` wipes the terminal of a shell that has exited and drops
its tab, and leaves a running one alone.

`lua/dock/shell.lua` is written against nothing but the public API, so it
doubles as a worked example of embedding a plugin's buffers.

## Configuration

```lua
require("dock").setup({
  command    = "Dock",
  position   = "bottom",
  size       = 0.22,
  min_size   = 6,
  auto_open  = true,        -- open the dock when a source adds a group
  empty_text = "No pages",

  winbar = {
    separator = "│",
    unread    = "•",
    numbers   = true,
  },

  shell = {
    cmd = nil,              -- defaults to 'shell'
    cwd = nil,              -- string, or a function returning one
  },
})
```

The dock remembers its size: drag its border and the next open uses that ratio.

## Highlights

All defined with `default = true`, so a colourscheme always wins.

| group | default |
|---|---|
| `DockActiveTab` | `Title` fg on `WinBar` bg, bold |
| `DockBadgeOk` | `DiagnosticOk` |
| `DockBadgeErr` | `DiagnosticError` |
| `DockBadgeWarn` | `DiagnosticWarn` |
| `DockBadgeHint` | `DiagnosticHint` |
| `DockBadgeMuted` | `WinBar` |
| `DockUnread` | `DiagnosticHint` |

## API

**`dock`**

| | |
|---|---|
| `setup(opts?)` | configure; optional |
| `source(name)` | claim a namespace → `Source` |
| `panel()` | the shared `Panel` |
| `open(opts?)` / `close(opts?)` / `toggle(opts?)` | this tabpage's window; `opts.enter` focuses it, `close({ all = true })` hides every one |
| `jump(n, opts?)` | select tab `n`; returns `false` if out of range |
| `groups()` | every group, oldest first |
| `clean(n?)` | ask every tab — or just tab `n` — to shed itself; returns how many went |
| `shell(opts?)` | run a shell/command in its own tab |

**`Source`**

| | |
|---|---|
| `group(spec?)` | create a tab; reusing an `id` returns the existing group |
| `get(id)` / `groups()` | |
| `clean()` / `clear()` | ask this source's groups to shed themselves / detach them outright |

**`Group`**

| | |
|---|---|
| `page(spec)` | add a buffer → `Page` |
| `remove_page(page\|buf)` | |
| `set_label(s)` / `set_badge(b?)` / `set_busy(b)` | chainable |
| `activate(opts?)` | show it; `{ page = …, buf = …, enter = … }` |
| `remove()` | detach; buffers untouched |
| `clean()` | run `on_clean`; returns whether the tab is gone afterwards |
| `is_busy()` / `is_removed()` | |

`GroupSpec`: `id`, `label`, `badge`, `busy`, `focus`, `data`,
`remove_when_empty`, `auto_open`, `on_clean`, `on_activate`.

`PageSpec`: `buf`, `label`, `priority`, `activate`.

## Notes on behaviour

Two things dock handles that are easy to get wrong on your own:

**Deleting a displayed buffer.** Neovim closes a window when the buffer it shows
is deleted, and emits `WinClosed` *before* any `BufUnload`/`BufWipeout` autocmd —
so there is no hook early enough to move the dock off the doomed buffer first.
dock detects the close and reopens the window, unless that was the last tab.

**Option leakage.** `vim.wo[win].opt = val` also writes Neovim's hidden global
default, even for options with no real global scope. dock sets every window
option with an explicit `scope = "local"`, so opening the dock never changes how
your other windows behave — which matters most for `'winbar'`, where the leak
would paint the dock's tab bar onto unrelated windows.

## Tests

```sh
make test

# pass flags through to busted
make test BUSTED_ARGS="--filter=winbar -o gtest"
```

Tests use [busted](https://lunarmodules.github.io/busted/), run through
[nlua](https://github.com/mfussenegger/nlua) so each spec executes inside a
real Neovim. `make test` installs both into a project-local `.luarocks/` tree
on first use; `make clean-deps` removes it.
