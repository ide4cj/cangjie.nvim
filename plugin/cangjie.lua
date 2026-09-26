-- Cangjie in Neovim, beyond the language server: cjfmt, the tree-sitter grammar for
-- nvim-treesitter, and the file types Neovim does not detect.
if vim.g.loaded_cangjie then
  return
end
vim.g.loaded_cangjie = true

-- The compiler's macro-expansion dumps, next to the sources: the same language
vim.filetype.add({ pattern = { ['.*%.cj%.macrocall'] = 'cangjie' } })

-- `:TSInstall cangjie` fetches, compiles and installs the grammar with its queries. nvim-treesitter
-- (its `main` branch) fires `User TSUpdate` whenever it reads its parser table, so registering
-- after the init file is soon enough.
vim.api.nvim_create_autocmd('User', {
  pattern = 'TSUpdate',
  callback = function()
    require('nvim-treesitter.parsers').cangjie = {
      install_info = {
        url = 'https://github.com/BonZirka/tree-sitter-cangjie',
        revision = '4c66f4b9a5f10d373fc637ebe915bf7698e7de13',
        queries = 'queries',
      },
    }
  end,
})

-- The grammar's queries capture parameters as `@parameter`, nvim-treesitter's name before 0.10
vim.api.nvim_set_hl(0, '@parameter.cangjie', { link = '@variable.parameter', default = true })

-- The buffer, or the lines given, through cjfmt (lua/cangjie/cjfmt.lua)
vim.api.nvim_create_user_command('Cjfmt', function(args)
  local err = require('cangjie.cjfmt').format_buffer({ range = args.range > 0 and { args.line1, args.line2 } or nil })
  if err then
    vim.notify(err, vim.log.levels.ERROR)
  end
end, { range = true, desc = 'Format the buffer, or the lines in the range, with cjfmt' })
