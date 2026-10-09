-- The server, given a cjls binary in CJLS_BIN: it attaches to a Cangjie buffer at its package root,
-- completes `initialize`, and exits with 0 after `shutdown`/`exit`; folds and formats.
local t = require('t')

--- The fixture's `main.cj` holding `lines`, once cjls is attached to it, or skips the case.
local function attached(lines)
  if not vim.env.CJLS_BIN then
    t.skip('no CJLS_BIN')
  end
  vim.cmd.edit(t.fixture .. '/src/main.cj')
  local client
  t.wait('cjls did not attach and initialize (see :LspLog)', function()
    client = vim.lsp.get_clients({ name = 'cjls', bufnr = 0 })[1]
    return client ~= nil and client.initialized
  end)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  return client
end

local UNFORMATTED = { 'package fixture', '', 'main(): Int64 {', 'let a = 1', 'let b = 2', '0', '}' }

return {
  ['cjls attaches at the package root and exits with 0 after shutdown'] = function()
    if not vim.env.CJLS_BIN then
      t.skip('no CJLS_BIN')
    end
    -- arrange
    local exit_code
    vim.lsp.config('cjls', {
      on_exit = function(code)
        exit_code = code
      end,
    })

    -- act
    vim.cmd.edit(t.fixture .. '/src/main.cj')
    local client
    t.wait('cjls did not attach and initialize (see :LspLog)', function()
      client = vim.lsp.get_clients({ name = 'cjls', bufnr = 0 })[1]
      return client ~= nil and client.initialized
    end)
    client:stop()
    t.wait('cjls did not exit after shutdown', function()
      return exit_code ~= nil
    end)

    -- assert
    t.eq(t.fixture, client.root_dir, 'root_dir')
    t.eq('cjls', client.server_info and client.server_info.name, 'serverInfo.name')
    t.eq(0, exit_code, 'exit code')
  end,

  ['folds come from cjls'] = function()
    if not vim.env.CJLS_BIN then
      t.skip('no CJLS_BIN')
    end
    -- arrange: `main` spans lines 3 to 6
    vim.cmd.edit(t.fixture .. '/src/main.cj')
    vim.wo.foldmethod = 'expr'

    -- act
    t.wait('cjls did not attach and initialize (see :LspLog)', function()
      local client = vim.lsp.get_clients({ name = 'cjls', bufnr = 0 })[1]
      return client ~= nil and client.initialized
    end)
    t.wait('no folds arrived', function()
      return vim.fn.foldlevel(4) > 0
    end)

    -- assert
    t.eq('v:lua.vim.lsp.foldexpr()', vim.wo.foldexpr, 'foldexpr')
    t.eq(1, vim.fn.foldlevel(4), 'the body folds')
    t.eq(0, vim.fn.foldlevel(1), 'the package header does not')
  end,

  ['the buffer is formatted by cjls'] = function()
    -- arrange
    attached(UNFORMATTED)

    -- act
    vim.lsp.buf.format({ name = 'cjls', timeout_ms = t.TIMEOUT_MS })

    -- assert
    t.eq({ 'package fixture', '', 'main(): Int64 {', '    let a = 1', '    let b = 2', '    0', '}' }, t.lines())
    vim.cmd('edit!')
  end,

  ['gq formats the lines it moves over with cjls'] = function()
    -- arrange
    local client = attached(UNFORMATTED)
    if not client:supports_method('textDocument/rangeFormatting') then
      t.skip('this cjls formats no ranges')
    end

    -- act: the line of `b` alone
    vim.cmd('normal! 5Ggqq')

    -- assert
    t.eq("v:lua.vim.lsp.formatexpr()", vim.bo.formatexpr, 'formatexpr')
    t.eq({ 'package fixture', '', 'main(): Int64 {', 'let a = 1', '    let b = 2', '0', '}' }, t.lines())
    vim.cmd('edit!')
  end,
}
