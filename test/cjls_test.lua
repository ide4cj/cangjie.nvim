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
  t.wait('cjls to attach and initialize (see :LspLog)', function()
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
    t.wait('cjls to attach and initialize (see :LspLog)', function()
      client = vim.lsp.get_clients({ name = 'cjls', bufnr = 0 })[1]
      return client ~= nil and client.initialized
    end)
    client:stop()
    t.wait('cjls to exit after shutdown', function()
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
    t.wait('cjls to attach and initialize (see :LspLog)', function()
      local client = vim.lsp.get_clients({ name = 'cjls', bufnr = 0 })[1]
      return client ~= nil and client.initialized
    end)
    t.wait('folds from cjls', function()
      return vim.fn.foldlevel(4) > 0
    end)

    -- assert
    t.eq('v:lua.vim.lsp.foldexpr()', vim.wo.foldexpr, 'foldexpr')
    t.eq(1, vim.fn.foldlevel(4), 'the body folds')
    t.eq(0, vim.fn.foldlevel(1), 'the package header does not')
  end,

  ['settings.cjls reaches cjls: the projects of linkedProjects are loaded'] = function()
    if not vim.env.CJLS_BIN then
      t.skip('no CJLS_BIN')
    end
    -- arrange: an empty workspace of its own, attached to no buffer, so no other case meets this
    -- client; and a directory outside it, loaded only when linked
    local root = t.tempdir()
    local linked = t.tempdir()
    t.write(linked .. '/linked.cj', { 'func findLinked() {}' })
    local config = vim.tbl_deep_extend('force', vim.lsp.config.cjls, {
      root_dir = root,
      settings = { cjls = { linkedProjects = { linked } } },
    })

    -- act: started with them, cjls has them from `initializationOptions` (and, since it reads its
    -- settings, from `workspace/configuration` as well); it loads in the background, answering
    -- nothing or ContentModified meanwhile, so it is asked until it has: a hang is CI's to end
    local client = assert(vim.lsp.get_client_by_id(assert(vim.lsp.start(config, { attach = false }))))
    local ok, symbols = pcall(function()
      while true do
        local answer
        client:request('workspace/symbol', { query = 'findLinked' }, function(err, result)
          answer = { err = err, result = result or {} }
        end)
        while not answer do
          vim.wait(100, function()
            return answer ~= nil
          end)
        end
        local modified = answer.err and answer.err.code == vim.lsp.protocol.ErrorCodes.ContentModified
        assert(modified or not answer.err, vim.inspect(answer.err))
        if not modified and #answer.result > 0 then
          return answer.result
        end
      end
    end)
    client:stop()
    assert(ok, symbols)

    -- assert
    t.eq({ 'findLinked' }, vim.tbl_map(function(s)
      return s.name
    end, symbols))
    t.eq('linked.cj', vim.fs.basename(vim.uri_to_fname(symbols[1].location.uri)), 'the file')
  end,

  ['the buffer is formatted by cjls'] = function()
    -- arrange
    attached(UNFORMATTED)

    -- act
    vim.lsp.buf.format({ name = 'cjls', timeout_ms = t.FOREVER_MS })

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
    -- Neovim's formatexpr gives the server 500 ms and leaves the lines as they are past them, which
    -- a slow runner's first request misses: the same, waiting for the answer
    t.eq('v:lua.vim.lsp.formatexpr()', vim.bo.formatexpr, 'formatexpr')
    vim.bo.formatexpr = 'v:lua.vim.lsp.formatexpr(#{timeout_ms: ' .. t.FOREVER_MS .. '})'

    -- act: the line of `b` alone
    vim.cmd('normal! 5Ggqq')

    -- assert
    t.eq({ 'package fixture', '', 'main(): Int64 {', 'let a = 1', '    let b = 2', '0', '}' }, t.lines())
    vim.cmd('edit!')
  end,
}
