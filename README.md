# cangjie.nvim

[Cangjie](https://cangjie-lang.cn) in Neovim 0.11 or newer: the [cjls](https://github.com/ide4cj/cjls)
language server, started for `.cj` files and downloaded on first use, which also formats; `//`
comments and indentation as it formats; and the tree-sitter grammar for nvim-treesitter.

## Install

`vim.pack` (Neovim 0.12):

```lua
vim.pack.add({ 'https://github.com/ide4cj/cangjie.nvim' })
```

[lazy.nvim](https://lazy.folke.io):

```lua
{ 'ide4cj/cangjie.nvim' }
```

[kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) is on `vim.pack`: put the line above in
`lua/custom/plugins/cangjie.lua` and uncomment `require 'custom.plugins'` at the end of `init.lua`.
Don't add `cjls` to its `servers` table: those are the servers Mason installs, and Mason does not
know cjls. For highlighting, run `:TSInstall cangjie` once; kickstart starts it in Cangjie buffers
from then on (it lists the parsers it installs by itself before the plugin loads).

That is all: the server downloads itself, and needs no Cangjie SDK. `:checkhealth cangjie` shows
which cjls the plugin runs, and what to do when there is none.

| File | What it does |
|---|---|
| `lsp/cjls.lua` | the server's `vim.lsp.Config`, in nvim-lspconfig's format: `cjls` from `PATH`, rooted at the nearest `cjpm.toml` |
| `plugin/cjls.lua` | `vim.lsp.enable('cjls')`, `:CjlsInstall`, the download when there is no `cjls` on `PATH`, folds from the server |
| `lua/cangjie/install.lua` | the download itself |
| `lua/cangjie/health.lua` | `:checkhealth cangjie` |
| `ftplugin/cangjie.lua` | `//` comments (`gc`), 4-space indentation as cjls formats |
| `plugin/cangjie.lua` | `*.cj.macrocall` as Cangjie; the tree-sitter grammar for nvim-treesitter |

Neovim detects `*.cj` itself. Settings go through `vim.lsp.config`, as for any server:

```lua
vim.lsp.config('cjls', { cmd_env = { CJLS_LOG_LEVEL = 'DEBUG' } })
```

## The server binary

A `cjls` on `PATH` always wins. Without one, at the first Cangjie buffer of a session, the plugin
downloads the archive [cjls](https://github.com/ide4cj/cjls)'s release publishes for this platform — macOS arm64, Linux x64, Windows
x64 — checks it against the release's `SHA256SUMS`, and unpacks it into
`stdpath('data')/cjls/bin` (`~/.local/share/nvim/cjls/bin`), which it appends to `PATH`. It needs
`curl` and `tar`, as Windows 10 and later ship them.

The release is the one the plugin pins in `lua/cangjie/install.lua`, the one it is tested with, so when the plugin manager updates the plugin to a
newer pin, the next session downloads that release; Renovate moves the pin after each cjls release.
`vim.g.cjls_version = 'v0.2.0'` picks another one; `vim.g.cjls_version = 'nightly-build'` follows cjls's
master, rebuilt every night; `:CjlsInstall` downloads it again.

Elsewhere, or to run your own build, put `cjls` on `PATH`, or point the server at it:

```lua
vim.lsp.config('cjls', { cmd = { '/path/to/cjls/target/release/bin/cjls' } })
```

The plugin then downloads nothing.

## Formatting

The server formats, in its own style ([cjls's D60](https://github.com/ide4cj/cjls/blob/master/docs/adr/0060-the-formatter-keeps-line-breaks.md)):
only the whitespace around the line breaks you wrote, four spaces a level whatever `shiftwidth`
says, so a project formats alike in every editor and as `cjls fmt` does. A file with syntax errors
is left as it is.

- `gq` formats the lines it moves over (`gggqG` the whole file): Neovim sets `'formatexpr'` to the
  server's once it attaches. Until then, or while typing past `'textwidth'`, it is Neovim's own.
- `:lua vim.lsp.buf.format()` formats the buffer.
- With [conform.nvim](https://github.com/stevearc/conform.nvim), through the server:

  ```lua
  require('conform').setup({ default_format_opts = { lsp_format = 'fallback' } })
  ```

## Highlighting

The server highlights by semantic tokens once it attaches. Before that, and for indentation and
text objects, there is [tree-sitter-cangjie](https://github.com/ide4cj/tree-sitter-cangjie), at the
head of its `master`: `:TSUpdate` downloads it again each time. With [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
on its `main` branch (it needs the `tree-sitter` CLI and a C compiler):

```vim
:TSInstall cangjie
```

The download is large — the grammar's repository carries its test corpus. nvim-treesitter does
not start highlighting by itself; if your config does not already, do it for Cangjie buffers:

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'cangjie',
  callback = function(args)
    vim.treesitter.start(args.buf, 'cangjie')
    vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end,
})
```

Without the grammar Neovim falls back to its own `syntax/cangjie.vim`.

## Folding

Folds come from the server: once cjls attaches, the plugin sets `foldexpr` to
`v:lua.vim.lsp.foldexpr()` in the buffer's windows. Neovim uses it where `foldmethod` is `expr`,
which is not its default; to fold Cangjie by the server without everything closed at first:

```lua
vim.o.foldmethod = 'expr'
vim.o.foldlevelstart = 99
```

## Test

```sh
nvim --clean --headless -u test/run.lua                           # all of test/*_test.lua
CJLS_BIN=/path/to/cjls nvim --clean --headless -u test/run.lua    # the server too
TEST=cjls nvim --clean --headless -u test/run.lua                 # the cases matching a Lua pattern
```

A case needing what is not there is skipped, not failed: the server's without `CJLS_BIN`. CI runs
them all on macOS, Linux and Windows with the latest cjls release, downloaded by
`test/install_cjls.lua` (without the server until there is one); cjls's own CI runs them with the
binary it builds.

## Contributing

Commits are [Conventional Commits](https://www.conventionalcommits.org/) (`feat: ...`, `fix: ...`),
checked by [cocogitto](https://docs.cocogitto.io/) in CI, on each commit and the PR title, and
locally once the hooks are on: `git config core.hooksPath .githooks`. `master` takes pull requests
only, squashed or rebased, once CI passes.
