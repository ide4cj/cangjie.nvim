-- What `plugin/` and `ftplugin/` set up without the server.
local t = require('t')

return {
  ['a Cangjie buffer is commented and indented as cjfmt writes it'] = function()
    -- act
    t.buffer({ 'main() {}' })

    -- assert
    t.eq('// %s', vim.bo.commentstring, 'commentstring')
    t.eq(4, vim.bo.shiftwidth, 'shiftwidth')
    t.eq(true, vim.bo.expandtab, 'expandtab')
  end,

  ['gq goes through cjfmt'] = function()
    -- act
    t.buffer({ 'main() {}' })

    -- assert
    t.eq("v:lua.require'cangjie.cjfmt'.formatexpr()", vim.bo.formatexpr)
  end,

  ['another file type undoes the ftplugin'] = function()
    -- arrange
    t.buffer({ 'main() {}' })

    -- act
    vim.bo.filetype = 'text'

    -- assert
    t.eq('', vim.bo.formatexpr, 'formatexpr')
    t.eq(false, vim.bo.expandtab, 'expandtab')
  end,

  ['the macro expansions cjc dumps are Cangjie'] = function()
    t.eq('cangjie', vim.filetype.match({ filename = 'main.cj.macrocall' }))
  end,

  ['nvim-treesitter learns of the grammar when it reads its parsers'] = function()
    -- arrange: a stand-in parser table, so neither nvim-treesitter nor the network is needed
    package.loaded['nvim-treesitter.parsers'] = {}

    -- act
    vim.api.nvim_exec_autocmds('User', { pattern = 'TSUpdate' })

    -- assert
    local cangjie = package.loaded['nvim-treesitter.parsers'].cangjie
    package.loaded['nvim-treesitter.parsers'] = nil
    assert(cangjie and cangjie.install_info.url and cangjie.install_info.revision, 'the cangjie grammar is not registered')
  end,

  ['checkhealth reports on the server, the formatter and the grammar'] = function()
    -- act
    vim.cmd('silent checkhealth cangjie')

    -- assert
    local text = table.concat(t.lines(), '\n')
    for _, section in ipairs({ 'cjls', 'cjfmt', 'tree%-sitter' }) do
      assert(text:match(section), 'no ' .. section .. ' section in\n' .. text)
    end
    assert(not text:match('ERROR'), text)
  end,
}
