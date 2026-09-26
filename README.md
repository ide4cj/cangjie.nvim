# cangjie.nvim

[Cangjie](https://cangjie-lang.cn) in Neovim 0.11 or newer: the [cjls](https://github.com/ide4cj/cjls)
language server, started for `.cj` files and downloaded on first use; cjfmt, found in the Cangjie
SDK, behind `gq`, `:Cjfmt` and conform.nvim; `//` comments and indentation as cjfmt writes them;
and the tree-sitter grammar for nvim-treesitter.

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

That is all: the server downloads itself, cjfmt is found in the SDK. `:checkhealth cangjie` shows
which cjls and cjfmt the plugin runs, and what to do when one is missing.

| File | What it does |
|---|---|
| `lsp/cjls.lua` | the server's `vim.lsp.Config`, in nvim-lspconfig's format: `cjls` from `PATH`, rooted at the nearest `cjpm.toml` |
| `plugin/cjls.lua` | `vim.lsp.enable('cjls')`, `:CjlsInstall`, the download when there is no `cjls` on `PATH` |
| `lua/cangjie/install.lua` | the download itself |
| `lua/cangjie/cjfmt.lua` | cjfmt: found, run, its result applied |
| `lua/conform/formatters/cjfmt.lua` | cjfmt for conform.nvim |
| `lua/cangjie/health.lua` | `:checkhealth cangjie` |
| `ftplugin/cangjie.lua` | `//` comments (`gc`), 4-space indentation as cjfmt writes it, `gq` through cjfmt |
| `plugin/cangjie.lua` | `:Cjfmt`; `*.cj.macrocall` as Cangjie; the tree-sitter grammar for nvim-treesitter |

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

The release is the one the plugin pins in `lua/cangjie/install.lua`, the one it is tested with (the
latest release until there is a first one), so when the plugin manager updates the plugin to a
newer pin, the next session downloads that release. `vim.g.cjls_version = 'v0.2.0'` picks another
one; `:CjlsInstall` downloads it again.

Elsewhere, or to run your own build, put `cjls` on `PATH`, or point the server at it:

```lua
vim.lsp.config('cjls', { cmd = { '/path/to/cjls/target/release/bin/cjls' } })
```

The plugin then downloads nothing.

## Formatting

[cjfmt](https://gitcode.com/Cangjie/cangjie_tools/tree/main/cjfmt) comes with the Cangjie SDK, in
`tools/bin`. The plugin takes the one on `PATH`, else the one in `$CANGJIE_HOME`, `~/.cangjie` or
`~/cangjie`, and runs it with what it needs of the SDK's environment, so Neovim does not have to be
started from a shell that sourced `envsetup.sh`. Each run takes the nearest `cangjie-format.toml`
above the file, or the SDK's `tools/config/cangjie-format.toml` without one.

- `gq` formats the lines it moves over (`gggqG` the whole file), through `'formatexpr'`. Without
  cjfmt, or while typing past `'textwidth'`, it is Neovim's own formatting.
- `:Cjfmt` formats the buffer, `:'<,'>Cjfmt` the lines selected.
- With [conform.nvim](https://github.com/stevearc/conform.nvim), the plugin is where conform looks
  for a formatter it has no definition of, so naming it is enough:

  ```lua
  require('conform').setup({ formatters_by_ft = { cangjie = { 'cjfmt' } } })
  ```

  `format_on_save` and range formatting then work as for any other formatter.

A file cjfmt cannot parse is left as it is, and the errors it reports are shown with their
`line:column`.

## Highlighting

Until the server answers semantic tokens, highlighting, folds, indentation and text objects come
from [tree-sitter-cangjie](https://github.com/BonZirka/tree-sitter-cangjie), at the revision
pinned in `plugin/cangjie.lua`. With [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
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
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end,
})
```

Without the grammar Neovim falls back to its own `syntax/cangjie.vim`.

## Test

```sh
nvim --clean --headless -u test/run.lua                           # all of test/*_test.lua
CJLS_BIN=/path/to/cjls nvim --clean --headless -u test/run.lua    # the server too
TEST=cjfmt nvim --clean --headless -u test/run.lua                # the cases matching a Lua pattern
```

A case needing what is not there is skipped, not failed: the server's without `CJLS_BIN`, cjfmt's
without a cjfmt the plugin finds. CI runs them all on macOS, Linux and Windows with the Cangjie SDK
cjls builds with (in `CANGJIE_HOME` only, not on `PATH`) and the latest cjls release, downloaded by
`test/install_cjls.lua` (without the server until there is one); cjls's own CI runs them with the
binary it builds.
