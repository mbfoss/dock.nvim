# Development

Notes for working on dock.nvim itself. For using the plugin, see
[README.md](README.md).

## Layout

| | |
|---|---|
| `lua/dock/` | the plugin: `Panel`, `Group`, `Source`, `winbar`, `commands`, `config`, `highlight`, `health`, `shell` |
| `plugin/dock.lua` | version guard and lazy entry point |
| `tests/` | busted specs, run inside a real Neovim |
| `scripts/gendoc.sh` | regenerates `doc/dock.txt` from `README.md` |
| `doc/` | generated; do not edit by hand |

`lua/dock/shell.lua` is written against nothing but the public API, so it is
both the one builtin source and a worked example of embedding a plugin's
buffers.

## Tests

```sh
make test

# pass flags through to busted
make test BUSTED_ARGS="--filter=winbar -o gtest"
```

- [busted](https://lunarmodules.github.io/busted/), run through
  [`tests/nvim-lua`](tests/nvim-lua), the interpreter shim named by
  [`.busted`](.busted), so each spec executes inside a real Neovim and can use
  the `vim` API.
- busted must already be installed for Lua 5.1, the version Neovim embeds:

  ```sh
  luarocks --lua-version=5.1 --local install busted
  ```

  `make test` fails if it is missing rather than installing anything.
- Specs are `tests/*_spec.lua`; `tests/init.lua` is the shared helper.

## Help file

`doc/dock.txt` is generated from `README.md` with
[panvimdoc](https://github.com/kdheepak/panvimdoc), so the README is the single
source and the help file follows it:

```sh
scripts/gendoc.sh           # rewrite doc/dock.txt and doc/tags
scripts/gendoc.sh --check   # exit 1 when the help file is out of date
scripts/gendoc.sh --check --diff
```

- Needs pandoc (`brew install pandoc`). `nvim` is used only to refresh
  `doc/tags`, and is optional.
- panvimdoc is fetched on first run and cached under `$XDG_CACHE_HOME`, pinned
  to the commit in `PANVIMDOC_COMMIT` (a tag can be moved, a commit cannot), so
  the help file is reproducible.
- `PANVIMDOC_DIR` points at a checkout of your own instead.
- Regenerate and commit `doc/` whenever `README.md` changes.

### Markdown that needs help-file handling

Three conventions, all read by `scripts/gendoc.sh`:

**Markdown with no place in a help file** (badges, screenshots, links to files
on the forge) goes between ignore markers:

```markdown
<!-- panvimdoc-ignore-start -->
![A screenshot](https://...)
<!-- panvimdoc-ignore-end -->
```

**Help-file-only text**, invisible where markdown is rendered, goes in a
vimdoc-only comment, uncommented on the way to panvimdoc:

```markdown
<!-- vimdoc-only
See |dock-configuration| for the full option list.
-->
```

**Help tags** come from a hidden comment at the end of a section heading; the
project name is prefixed automatically, so this yields `*dock-sources*`:

```markdown
## Custom sources <!-- tag: sources -->
```

Without one, the tag is derived from the heading text.

## Conventions

* Window options are set with an explicit `scope = "local"`. `vim.wo[win].opt =
  val` also writes Neovim's hidden global default, even for options with no
  real global scope, which would paint the dock's `'winbar'` onto unrelated
  windows.
* dock never deletes a buffer it did not create, and never removes a tab on its
  own; both are the owning source's call. See the README's
  [buffer ownership](README.md#buffer-ownership-and-cleaning) section.
* Highlight groups are defined with `default = true`, so a colourscheme always
  wins.
* Every `setup()` option needs its default in `lua/dock/config.lua`:
  `:checkhealth dock` warns about names dock does not define, because `setup()`
  merges the table wholesale and a misspelling would otherwise pass in silence.
