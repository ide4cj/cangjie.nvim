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

-- The grammar's queries capture parameters as `@parameter`, nvim-treesitter's name before 0.10
vim.api.nvim_set_hl(0, '@parameter.cangjie', { link = '@variable.parameter', default = true })
