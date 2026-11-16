-- Cangjie in Neovim, beyond the language server: the tree-sitter grammar for nvim-treesitter,
-- and the file types Neovim does not detect.
if vim.g.loaded_cangjie then
  return
end
vim.g.loaded_cangjie = true

-- The compiler's macro-expansion dumps, next to the sources: the same language
vim.filetype.add({ pattern = { ['.*%.cj%.macrocall'] = 'cangjie' } })

-- `:TSInstall cangjie` fetches, compiles and installs the grammar with its queries. nvim-treesitter
-- (its `main` branch) fires `User TSUpdate` whenever it reads its parser table, so registering
-- after the init file is soon enough. The grammar is ours, so it is followed at its `master`, not
-- pinned: with no `revision`, nvim-treesitter downloads the branch's head on every `:TSUpdate`.
vim.api.nvim_create_autocmd('User', {
  pattern = 'TSUpdate',
  callback = function()
    require('nvim-treesitter.parsers').cangjie = {
      install_info = {
        url = 'https://github.com/ide4cj/tree-sitter-cangjie',
        branch = 'master',
        queries = 'queries',
      },
    }
  end,
})

-- cjls names a token as the grammar's queries capture it, colors being the theme's (cjls D105);
-- Neovim links no `@lsp.typemod.*`, and type parameters and macros elsewhere than the grammar.
-- A typemod's mark is above its type's (priority 127 to 125): `@constructor` wins over
-- `@lsp.type.method`, `@constant` over `@lsp.type.variable`
vim.api.nvim_set_hl(0, '@lsp.typemod.variable.defaultLibrary.cangjie', { link = '@variable.builtin', default = true })
vim.api.nvim_set_hl(0, '@lsp.typemod.type.defaultLibrary.cangjie', { link = '@type.builtin', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.typeParameter.cangjie', { link = '@type', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.macro.cangjie', { link = '@function.macro', default = true })
vim.api.nvim_set_hl(0, '@lsp.typemod.method.constructor.cangjie', { link = '@constructor', default = true })
vim.api.nvim_set_hl(0, '@lsp.typemod.variable.constant.cangjie', { link = '@constant', default = true })
-- A token of the server resolves to the group the grammar's queries capture the same thing as, so
-- the color is the one the grammar would have given, whether treesitter or the server paints.
-- `decorator` (the grammar paints `@function.macro`) and `unresolvedReference` are left to the
-- theme on purpose.
vim.api.nvim_set_hl(0, '@lsp.type.type.cangjie', { link = '@type', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.class.cangjie', { link = '@type', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.interface.cangjie', { link = '@type', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.struct.cangjie', { link = '@type', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.enum.cangjie', { link = '@type', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.function.cangjie', { link = '@function', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.method.cangjie', { link = '@function.method', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.property.cangjie', { link = '@variable.member', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.namespace.cangjie', { link = '@module', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.variable.cangjie', { link = '@variable', default = true })
vim.api.nvim_set_hl(0, '@lsp.type.parameter.cangjie', { link = '@variable.parameter', default = true })
-- The grammar captures enum cases `@enum_member` (tree-sitter-cangjie, apart from `const`); the
-- capture resolves where the server's `enumMember` tokens do: one color for both.
vim.api.nvim_set_hl(0, '@enum_member.cangjie', { link = '@lsp.type.enumMember', default = true })
