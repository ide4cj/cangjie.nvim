-- Neovim ships a syntax file for Cangjie but no ftplugin: comments and indentation as cjfmt
-- writes them, and `gq` through cjfmt itself (lua/cangjie/cjfmt.lua).
vim.bo.commentstring = '// %s'
vim.bo.comments = 's1:/*,mb:*,ex:*/,://'
vim.bo.expandtab = true
vim.bo.shiftwidth = 4
vim.bo.softtabstop = 4
vim.bo.suffixesadd = '.cj'
vim.bo.formatexpr = "v:lua.require'cangjie.cjfmt'.formatexpr()"

vim.b.undo_ftplugin = (vim.b.undo_ftplugin and (vim.b.undo_ftplugin .. ' | ') or '')
  .. 'setlocal commentstring< comments< expandtab< shiftwidth< softtabstop< suffixesadd< formatexpr<'
