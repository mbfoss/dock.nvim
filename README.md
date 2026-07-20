# dock.nvim

One shared, docked window that any number of plugins can show their buffers in.

Plugins that produce output — task runners, test runners, linters, REPLs, build
tools — each end up writing the same window-management code: where to split, how
big, how to keep the user's layout intact, what to do when the buffer is deleted.
dock does that once. A plugin hands over a buffer and a label; dock owns
the window, the tab bar, the numbering, and the focus rules.

```
┌────────────────────────────────────────────────────────┐
│ editor                                                 │
├────────────────────────────────────────────────────────┤
│ ✓ 1:build [2:out|3:diag•] │ ⇪ 4:deploy │ ❯ 5:zsh       │
│ ...buffer contents...                                  │
└────────────────────────────────────────────────────────┘
```

Everything in that bar is clickable, and every tab has a number you can jump to.

## Requirements

Neovim >= 0.10 (for `'winfixbuf'`).

## Install

Any plugin manager, or `pack/*/opt` plus `:packadd dock.nvim`. Calling
`setup()` is optional — the `:Dock` command exists and the defaults work
untouched.

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
| **group**  | one tab. Has a label, a status badge, and pages. |
| **page**   | one buffer inside a group. |

A group with a single page renders as one tab. A group with several renders as a
tab plus a bracketed page list — so the common case stays visually quiet.

Groups belong to the panel, not to its window: closing the panel tears down only
the window, and reopening restores every tab exactly as it was.

## Using it from a plugin

```lua
local dock = require("dock")

-- once, at setup
local src   = dock.source("myplugin")

-- per unit of work
local group = src:group({ label = "build", status = "running" })
group:page({ buf = stdout_buf, label = "out" })

-- later
group:page({ buf = diag_buf, label = "diag", priority = 5 })
group:set_status("ok")
```

That is the whole integration. No window handling, no layout code.

### Buffer ownership

dock **never deletes a buffer it did not create**. Pages are borrowed. When
the panel wants a group gone it calls that group's `on_dispose`, and the source
decides what happens to the buffers:

```lua
local group = src:group({
  label      = "build",
  on_dispose = function(g)
    vim.api.nvim_buf_delete(g.data.buf, { force = true })
  end,
})
```

`group:remove()` detaches the tab and leaves the buffers alone;
`group:dispose()` detaches and then runs `on_dispose`.

### Who gets the view

A group declares how eagerly it takes over the panel, rather than the panel
guessing:

| `focus` | behaviour |
|---|---|
| `"auto"` (default) | takes over when it appears, unless the user is working inside the panel |
| `"never"` | never steals the view — for background or dependency work |
| `"always"` | takes over even when the panel is focused, and keeps the view until it stops being busy — for an explicit user action such as a restart |

Within a group, `priority` decides which page wins. The panel advances to a new
page only when it **outranks** what is already on screen, so a low-priority log
buffer appearing mid-run never pulls the user off the output they are watching.
Pass `activate = true` on a page, or call `group:activate()`, to insist.

### Statuses and badges

A status is a name that maps to a badge. The built-in set:

| status | badge | busy |
|---|---|---|
| `running` | `▶` | yes |
| `waiting` | `⧗` | yes |
| `ok` | `✓` | |
| `failed` | `✗` | |
| `stopped` | `✗` | |
| `idle` | `●` | |

`busy` means the group is still working. Busy groups are excluded from
`dock.disposable()`, so a bulk close can never yank a buffer out from under a
running job.

Add your own, scoped to your source:

```lua
local src = dock.source("myplugin", {
  badges = { deploying = { icon = "⇪", hl = "DockBadgeWarn", busy = true } },
})
src:group({ label = "deploy", status = "deploying" })
```

Or bypass statuses entirely with an explicit `badge = { icon = …, hl = … }` on
the group.

### Unread output

dock watches page buffers and marks a tab with `•` when it gains lines while
not visible. Nothing to wire up.

## Command

`:Dock` — toggle. With a number, jump to that tab.

| | |
|---|---|
| `:Dock` | toggle the panel |
| `:Dock 3` | jump to tab 3 (same as `:Dock jump 3`) |
| `:Dock open` / `close` / `toggle` | |
| `:Dock next` / `prev` | step through tabs, wrapping |
| `:Dock shell` | open a shell in a new tab |
| `:Dock dispose` | pick a finished tab to close |
| `:Dock! dispose` | close every finished tab |

Rename it with `setup({ command = "Panel" })`, or disable it with
`command = false`.

## Builtin: shell

dock ships one source of its own — an interactive shell in a panel tab:

```lua
require("dock").shell({ cwd = vim.fn.getcwd() })
```

The tab survives the shell exiting, so the scrollback stays readable; it is
dropped when the terminal buffer is deleted. `lua/dock/shell.lua` is written
against nothing but the public API, so it doubles as a worked example of
embedding a plugin's buffers.

## Configuration

```lua
require("dock").setup({
  command    = "Dock",
  position   = "bottom",
  size       = 0.22,
  min_size   = 6,
  auto_open  = true,        -- open the panel when a source adds a group
  empty_text = "No panels",

  badges     = { … },       -- merged over the built-in table

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

The panel remembers its size: drag its border and the next open uses that ratio.

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
| `source(name, spec?)` | claim a namespace → `Source` |
| `panel()` | the shared `Panel` |
| `open(opts?)` / `close()` / `toggle(opts?)` | `opts.enter` focuses the window |
| `jump(n, opts?)` | select tab `n`; returns `false` if out of range |
| `groups()` / `disposable()` | all groups / the non-busy ones |
| `shell(opts?)` | open a shell tab |

**`Source`**

| | |
|---|---|
| `group(spec?)` | create a tab; reusing an `id` returns the existing group |
| `get(id)` / `groups()` | |
| `clear(opts?)` | dispose this source's groups; `{ busy = true }` includes busy ones |

**`Group`**

| | |
|---|---|
| `page(spec)` | add a buffer → `Page` |
| `remove_page(page\|buf)` | |
| `set_status(s)` / `set_label(s)` / `set_badge(b?)` | chainable |
| `activate(opts?)` | show it; `{ page = …, buf = …, enter = … }` |
| `remove()` / `dispose()` | detach / detach and run `on_dispose` |
| `is_busy()` / `is_removed()` / `badge_spec()` | |

`GroupSpec`: `id`, `label`, `status`, `badge`, `focus`, `data`,
`remove_when_empty`, `auto_open`, `on_dispose`, `on_activate`.

`PageSpec`: `buf`, `label`, `priority`, `activate`.

## Notes on behaviour

Two things dock handles that are easy to get wrong on your own:

**Deleting a displayed buffer.** Neovim closes a window when the buffer it shows
is deleted, and emits `WinClosed` *before* any `BufUnload`/`BufWipeout` autocmd —
so there is no hook early enough to move the panel off the doomed buffer first.
dock detects the close and restores the panel, unless that was the last tab.

**Option leakage.** `vim.wo[win].opt = val` also writes Neovim's hidden global
default, even for options with no real global scope. dock sets every window
option with an explicit `scope = "local"`, so opening the panel never changes how
your other windows behave — which matters most for `'winbar'`, where the leak
would paint the panel's tab bar onto unrelated windows.

## Tests

```sh
make test
```
