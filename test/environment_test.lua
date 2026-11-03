local t = require('t')
local environment = require('cangjie.environment')

return {
  ['environment paths expand once without mutating the configured values'] = function()
    local extra = { STDX = '$HOME/sdk/static/stdx', PATH = '${PATH}:/tools', EMPTY = '', COPY = '$SDK', HOME = '/override' }
    local warnings = {}
    local result = environment.expand(extra, { HOME = '/home/user', PATH = '/bin', SDK = '$HOME/sdk' }, function(message)
      warnings[#warnings + 1] = message
    end)
    t.eq({ STDX = '/override/sdk/static/stdx', PATH = '/bin:/tools', EMPTY = '', COPY = '$HOME/sdk', HOME = '/override' }, result)
    t.eq('$HOME/sdk/static/stdx', extra.STDX)
    t.eq({}, warnings)
  end,

  ['entry chains resolve independently of order and inherited values stay literal'] = function()
    local extra = { STDX = '${SDK}/static/stdx', SDK = '$ROOT/sdk', ROOT = '$HOME', EMPTY = '', COPY = '$EMPTY', PATH = '${PATH}:/tools', INHERITED = '$RAW' }
    local expected = { STDX = '/home/user/sdk/static/stdx', SDK = '/home/user/sdk', ROOT = '/home/user', EMPTY = '', COPY = '', PATH = '/bin:/tools', INHERITED = '$HOME/literal' }
    local inherited = { HOME = '/home/user', PATH = '/bin', SDK = '/old', EMPTY = '/old', RAW = '$HOME/literal' }
    t.eq(expected, environment.expand(extra, inherited, error))
    local reverse = {}
    local keys = vim.tbl_keys(extra)
    table.sort(keys)
    for i = #keys, 1, -1 do reverse[keys[i]] = extra[keys[i]] end
    t.eq(expected, environment.expand(reverse, inherited, error))
  end,

  ['cycles and their dependents keep original values without affecting unrelated entries'] = function()
    local extra = { A = 'secret-$B', B = '${A}/suffix', CHILD = '$A/child', SELF = '$SELF', OK = '$HOME/ok' }
    local warnings = {}
    local expected = vim.tbl_extend('force', extra, { OK = '/home/ok' })
    t.eq(expected, environment.expand(extra, { HOME = '/home', A = '/old' }, function(message) warnings[#warnings + 1] = message end))
    t.eq(4, #warnings)
    for _, message in ipairs(warnings) do
      assert(message:find('cyclic', 1, true) and not message:find('secret-', 1, true))
    end
  end,

  ['home expansion and missing variables preserve literals without disclosing values'] = function()
    local warnings = {}
    local result = environment.expand({ ROOT = '~', SDK = '~\\sdk', SRC = '~/src', LITERAL = '~user/$(pwd)', TOKEN = 'secret-${MISSING}-$MISSING' },
      { USERPROFILE = 'C:\\Users\\user' }, function(message) warnings[#warnings + 1] = message end)
    t.eq('C:\\Users\\user', result.ROOT)
    t.eq('C:\\Users\\user\\sdk', result.SDK)
    t.eq('C:\\Users\\user/src', result.SRC)
    t.eq('~user/$(pwd)', result.LITERAL)
    t.eq('secret-${MISSING}-$MISSING', result.TOKEN)
    t.eq(1, #warnings)
    assert(warnings[1]:find('MISSING', 1, true) and not warnings[1]:find('secret-', 1, true))
    t.eq('/home', environment.expand({ ROOT = '~' }, { HOME = '/home', USERPROFILE = '/fallback' }, error).ROOT)
    t.eq('~', environment.expand({ ROOT = '~' }, {}, function() end).ROOT)
  end,

  ['launch expands cmd_env before the transport sees it and preserves custom commands'] = function()
    local previous = vim.deepcopy(vim.lsp.config.cjls)
    local inherited = vim.env.HOME or vim.env.USERPROFILE
    local seen
    local command = function(_, config)
      seen = config
      return 'transport'
    end
    local ok, err = pcall(function()
      vim.lsp.config('cjls', { cmd = command, cmd_env = { STDX = '$HOME/sdk' } })
      environment.prepare()
      local config = vim.lsp.config.cjls
      local wrapped = config.cmd
      environment.prepare()
      t.eq(wrapped, vim.lsp.config.cjls.cmd, 'not wrapped twice')
      t.eq(command, environment.command(config))
      t.with_env({ HOME = inherited }, function()
        t.eq('transport', wrapped({}, config))
      end)
      t.eq(inherited .. '/sdk', seen.cmd_env.STDX)
      t.eq('$HOME/sdk', config.cmd_env.STDX)
      t.eq(command, seen.cmd)
    end)
    vim.lsp.config.cjls = previous
    if not ok then error(err) end
  end,

  ['spawned process receives expanded values before initialize'] = function()
    local previous = vim.deepcopy(vim.lsp.config.cjls)
    local dir = t.tempdir()
    local script = t.write(dir .. '/environment.lua', {
      "vim.fn.writefile({ vim.env.CJLS_TEST_PATH, os.getenv('CJLS_TEST_EMPTY') or 'unset' }, arg[1])",
      "vim.cmd('qall!')",
    })
    local destination = dir .. '/environment.txt'
    local exited, transport
    local ok, err = pcall(function()
      vim.lsp.config('cjls', {
        cmd = { vim.v.progpath, '--clean', '--headless', '-l', script, destination },
        cmd_env = { CJLS_TEST_PATH = '${CJLS_TEST_SDK}/static/stdx', CJLS_TEST_SDK = '$CJLS_TEST_HOME/sdk', CJLS_TEST_EMPTY = '' },
        detached = false,
      })
      environment.prepare()
      local config = vim.lsp.config.cjls
      t.with_env({ CJLS_TEST_HOME = '/home/test user' }, function()
        transport = config.cmd({ on_exit = function(code) exited = code end }, config)
      end)
      t.wait('child process did not exit', function() return exited ~= nil end)
      t.eq(0, exited)
      t.eq({ '/home/test user/sdk/static/stdx', '' }, vim.fn.readfile(destination))
    end)
    if transport and not exited then transport.terminate() end
    vim.lsp.config.cjls = previous
    vim.fn.delete(dir, 'rf')
    if not ok then error(err) end
  end,

  ['command list launch forwards process options and expanded environment'] = function()
    local previous = vim.deepcopy(vim.lsp.config.cjls)
    local original_start = vim.lsp.rpc.start
    local seen
    local ok, err = pcall(function()
      vim.lsp.rpc.start = function(command, dispatchers, options)
        seen = { command, dispatchers, options }
        return 'transport'
      end
      vim.lsp.config('cjls', { cmd = { 'custom-cjls', '--flag' }, cmd_env = { SDK = '~/sdk' }, cmd_cwd = '/workspace', detached = false })
      environment.prepare()
      local config = vim.lsp.config.cjls
      t.with_env({ HOME = '/home/user' }, function()
        t.eq('transport', config.cmd({ notification = 'handler' }, config))
      end)
      t.eq({ 'custom-cjls', '--flag' }, environment.command(config))
      t.eq({ { 'custom-cjls', '--flag' }, { notification = 'handler' }, { cwd = '/workspace', env = { SDK = '/home/user/sdk' }, detached = false } }, seen)
    end)
    vim.lsp.rpc.start = original_start
    vim.lsp.config.cjls = previous
    if not ok then error(err) end
  end,
}
