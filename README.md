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

Releases are tags on cjls's minor with a patch of their own: `v0.5.x` downloads cjls `0.5`
([cjls's D133](https://github.com/ide4cj/cjls/blob/master/docs/adr/0133-client-versions-follow-the-server.md)),
tagged once Renovate moves the pin; `master` is the newest.

[kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) is on `vim.pack`: put the line above in
`lua/custom/plugins/cangjie.lua` and uncomment `require 'custom.plugins'` at the end of `init.lua`.
Don't add `cjls` to its `servers` table: those are the servers Mason installs, and Mason does not
know cjls. For highlighting, run `:TSInstall cangjie` once; kickstart starts it in Cangjie buffers
from then on (it lists the parsers it installs by itself before the plugin loads).

That is all: the server downloads itself, and needs no Cangjie SDK. `:checkhealth cangjie` shows
which cjls the plugin runs, and what to do when there is none.

| File | What it does |
|---|---|
| `lsp/cjls.lua` | the server's `vim.lsp.Config`, in nvim-lspconfig's format: `cjls` from `PATH`, rooted at the nearest `cjpm.toml`, a file cjls expanded at the root it was written under |
| `plugin/cjls.lua` | `vim.lsp.enable('cjls')`, `:CjlsInstall`, the download when there is no `cjls` on `PATH`, folds from the server, `:CjlsExpandMacro` |
| `lua/cangjie/install.lua` | the download itself |
| `lua/cangjie/expand.lua` | macro expansion: `:CjlsExpandMacro`, and the files cjls expands, read-only |
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

## Settings

The server's settings go under `settings.cjls` of its config, as rust-analyzer's under
`settings['rust-analyzer']`:

```lua
vim.lsp.config('cjls', {
  settings = { cjls = { linkedProjects = { '/path/to/another/project' } } },
})
```

The server starts with them (`lsp/cjls.lua` passes them as its `initializationOptions`, unless
`init_options` is set) and asks Neovim for them again once initialized
([cjls's D79](https://github.com/ide4cj/cjls/blob/master/docs/adr/0079-settings-are-r1s.md)). Changed
in a running client, they reach the server by a notification of yours:

```lua
local client = vim.lsp.get_clients({ name = 'cjls' })[1]
client.settings.cjls.linkedProjects = { '/path/to/another/project' }
client:notify('workspace/didChangeConfiguration', { settings = vim.NIL })
```

What cjls reads, as `cjls --config-schema` describes it (the cjls the plugin pins, written by a bot
in the PR that moves the pin; a key a cjls does not know, it leaves alone):

<!-- settings: made by scripts/settings.lua from `cjls --config-schema` -->
| `settings.cjls.` | type | default | |
|---|---|---|---|
| `linkedProjects` | string[] | `[]` | Projects to load, as rust-analyzer's: each an absolute path or a `file:` URI of a `cj-project.json`, or of a directory to find a project in. Under a root without a `cj-project.json`, they replace finding one there; outside every root, they are loaded besides. |
| `cangjieHome` | string or null | `null` | The Cangjie SDK, an absolute path or a `file:` URI: looked for first, before `CANGJIE_HOME`, cjsdk's default toolchain and `cjc` on `PATH`. `std` is taken from it, and `${CANGJIE_HOME}` in a project's paths expands to it. |
| `cangjieSrc` | string or null | `null` | The sources of the SDK's version, a directory holding `std/` as `cangjie_runtime`'s `stdlib/libs` does, an absolute path or a `file:` URI: looked for first, before `CANGJIE_SRC` and the SDK's `src`. Go to definition on a declaration of `std` goes there; `cjls fetch-src` puts them in the SDK's `src`. |
<!-- /settings -->

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

The plugin links the server's semantic tokens to the captures the grammar gives the same token
(`this` to `@variable.builtin`, `Int64` to `@type.builtin`, …), so a token keeps its color when
the server attaches; a link of your own, or your colorscheme's, takes precedence.

## Binary library sources

With a server supporting `cjls/binarySourceRoots`, sources attached to binary
libraries (including SDK std sources) open with buffer-local `readonly` and
`nomodifiable`. Existing buffers are protected when roots arrive; removed roots
and stopped servers restore the previous options. Source path dependencies stay
editable. File permissions and diagnostics are unchanged.

## Folding

Folds come from the server: once cjls attaches, the plugin sets `foldexpr` to
`v:lua.vim.lsp.foldexpr()` in the buffer's windows. Neovim uses it where `foldmethod` is `expr`,
which is not its default; to fold Cangjie by the server without everything closed at first:

```lua
vim.o.foldmethod = 'expr'
vim.o.foldlevelstart = 99
```

## Macro expansion

What a macro call expands to, from cjls ([cjls's D103](https://github.com/ide4cj/cjls/blob/master/docs/adr/0103-an-expansion-is-shown-as-a-request-and-as-a-read-only-file.md)),
two ways:

- `:CjlsExpandMacro`, the cursor on a call's head (`@`, its name or its attribute): the expansion of
  that call alone, in a split, a scratch buffer `cjls://expand/<name>`. A cjls that does not
  expand macros yet (no `experimental.expandMacro`) is said to.
- The code action "Expand macro" (`:lua vim.lsp.buf.code_action()`, `gra`): cjls writes the whole
  file with its calls expanded, `<project>/.cache/cjls/expanded/<path>.macrocall`, and Neovim opens it, the
  call's expansion selected. The buffer is read-only; hover, go to definition and highlight work
  in it, through the cjls of the source, until the source changes and the action is run again.

A binding of your own, for instance:

```lua
vim.keymap.set('n', '<leader>em', '<Cmd>CjlsExpandMacro<CR>', { desc = 'Expand macro' })
```

## Test

```sh
nvim --clean --headless -u test/run.lua                           # all of test/*_test.lua
CJLS_BIN=/path/to/cjls nvim --clean --headless -u test/run.lua    # the server too
TEST=cjls nvim --clean --headless -u test/run.lua                 # the cases matching a Lua pattern
nvim -l scripts/settings.lua /path/to/cjls                        # the server's settings into README.md
```

The PR that moves the pin gets the settings of the cjls it pins in this README as a commit of a
bot's (cjls's D107); a pin moved by hand runs the script itself.

A case needing what is not there is skipped, not failed: the server's without `CJLS_BIN`. CI runs
them all on macOS, Linux and Windows with the latest cjls release, downloaded by
`test/install_cjls.lua` (without the server until there is one); cjls's own CI runs them with the
binary it builds.

## Contributing

Commits are [Conventional Commits](https://www.conventionalcommits.org/) (`feat: ...`, `fix: ...`),
checked by [cocogitto](https://docs.cocogitto.io/) in CI, on each commit and the PR title, and
locally once the hooks are on: `git config core.hooksPath .githooks`. `master` takes pull requests
only, squashed or rebased, once CI passes.

Tests follow the shared [AAA and cleanup conventions](https://github.com/ide4cj/.github/blob/master/CONTRIBUTING.md#tests).
