-- The server, given a cjls binary in CJLS_BIN: it attaches to a Cangjie buffer at its package root,
-- completes `initialize`, and exits with 0 after `shutdown`/`exit`.
local t = require('t')

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
}
