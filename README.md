# cangjie.nvim

[Cangjie](https://cangjie-lang.cn) in Neovim 0.11 or newer: the [cjls](https://github.com/ide4cj/cjls)
language server, started for `.cj` files and downloaded on first use; `//` comments and
indentation as cjfmt writes them; and the tree-sitter grammar for nvim-treesitter.

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

| File | What it does |
|---|---|
| `lsp/cjls.lua` | the server's `vim.lsp.Config`, in nvim-lspconfig's format: `cjls` from `PATH`, rooted at the nearest `cjpm.toml` |
| `plugin/cjls.lua` | `vim.lsp.enable('cjls')`, `:CjlsInstall`, the download when there is no `cjls` on `PATH` |
| `lua/cangjie/install.lua` | the download itself |
| `ftplugin/cangjie.lua` | `//` comments (`gc`), 4-space indentation as cjfmt writes it |
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

The release is the one the plugin pins in `lua/cangjie/install.lua`, the one it is tested with (the
latest release until there is a first one), so when the plugin manager updates the plugin to a
newer pin, the next session downloads that release. `vim.g.cjls_version = 'v0.2.0'` picks another
one; `:CjlsInstall` downloads it again.

Elsewhere, or to run your own build, put `cjls` on `PATH`, or point the server at it:

```lua
vim.lsp.config('cjls', { cmd = { '/path/to/cjls/target/release/bin/cjls' } })
```

The plugin then downloads nothing.

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
nvim --clean --headless -u test/smoke.lua                                  # without the server
CJLS_BIN=/path/to/cjls nvim --clean --headless -u test/smoke.lua           # and with it
```

CI runs it with the latest cjls release (without the server until there is one), and cjls's own CI with the binary it builds.
