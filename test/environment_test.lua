local t = require('t')
local environment = require('cangjie.environment')

return {
  ['environment paths expand once without mutating the configured values'] = function()
    -- arrange
    local extra = {
      STDX = '$HOME/sdk/static/stdx',
      PATH = '${PATH}:/tools',
      EMPTY = '',
      COPY = '$SDK',
      HOME = '/override',
    }
    local inherited = { HOME = '/home/user', PATH = '/bin', SDK = '$HOME/sdk' }
    local warnings = {}

    -- act
    local result = environment.expand(extra, inherited, function(message)
      warnings[#warnings + 1] = message
    end)

    -- assert
    t.eq({
      STDX = '/override/sdk/static/stdx',
      PATH = '/bin:/tools',
      EMPTY = '',
      COPY = '$HOME/sdk',
      HOME = '/override',
    }, result)
    t.eq('$HOME/sdk/static/stdx', extra.STDX)
    t.eq({}, warnings)
  end,

  ['entry chains resolve independently of order and inherited values stay literal'] = function()
    -- arrange
    local extra = {
      STDX = '${SDK}/static/stdx',
      SDK = '$ROOT/sdk',
      ROOT = '$HOME',
      EMPTY = '',
      COPY = '$EMPTY',
      PATH = '${PATH}:/tools',
      INHERITED = '$RAW',
    }
    local expected = {
      STDX = '/home/user/sdk/static/stdx',
      SDK = '/home/user/sdk',
      ROOT = '/home/user',
      EMPTY = '',
      COPY = '',
      PATH = '/bin:/tools',
      INHERITED = '$HOME/literal',
    }
    local inherited = { HOME = '/home/user', PATH = '/bin', SDK = '/old', EMPTY = '/old', RAW = '$HOME/literal' }
    local reverse = {}
    local keys = vim.tbl_keys(extra)
    table.sort(keys)
    for i = #keys, 1, -1 do
      reverse[keys[i]] = extra[keys[i]]
    end

    -- act
    local result = environment.expand(extra, inherited, error)
    local reversed = environment.expand(reverse, inherited, error)

    -- assert
    t.eq(expected, result)
    t.eq(expected, reversed)
  end,

  ['cycles and their dependents keep original values without affecting unrelated entries'] = function()
    -- arrange
    local extra = { A = 'secret-$B', B = '${A}/suffix', CHILD = '$A/child', SELF = '$SELF', OK = '$HOME/ok' }
    local inherited = { HOME = '/home', A = '/old' }
    local expected = vim.tbl_extend('force', extra, { OK = '/home/ok' })
    local warnings = {}

    -- act
    local result = environment.expand(extra, inherited, function(message)
      warnings[#warnings + 1] = message
    end)

    -- assert
    t.eq(expected, result)
    t.eq(4, #warnings)
    for _, message in ipairs(warnings) do
      assert(message:find('cyclic', 1, true) and not message:find('secret-', 1, true))
    end
  end,

  ['home expansion and missing variables preserve literals without disclosing values'] = function()
    -- arrange
    local extra = {
      ROOT = '~',
      SDK = '~\\sdk',
      SRC = '~/src',
      LITERAL = '~user/$(pwd)',
      TOKEN = 'secret-${MISSING}-$MISSING',
    }
    local inherited = { USERPROFILE = 'C:\\Users\\user' }
    local warnings = {}

    -- act
    local result = environment.expand(extra, inherited, function(message)
      warnings[#warnings + 1] = message
    end)
    local preferred_home = environment.expand({ ROOT = '~' }, { HOME = '/home', USERPROFILE = '/fallback' }, error)
    local missing_home = environment.expand({ ROOT = '~' }, {}, function() end)

    -- assert
    t.eq('C:\\Users\\user', result.ROOT)
    t.eq('C:\\Users\\user\\sdk', result.SDK)
    t.eq('C:\\Users\\user/src', result.SRC)
    t.eq('~user/$(pwd)', result.LITERAL)
    t.eq('secret-${MISSING}-$MISSING', result.TOKEN)
    t.eq(1, #warnings)
    assert(warnings[1]:find('MISSING', 1, true) and not warnings[1]:find('secret-', 1, true))
    t.eq('/home', preferred_home.ROOT)
    t.eq('~', missing_home.ROOT)
  end,

  ['launch expands cmd_env before the transport sees it and preserves custom commands'] = function()
    -- arrange
    local previous = vim.deepcopy(vim.lsp.config.cjls)
    local seen
    local command = function(_, config)
      seen = config
      return 'transport'
    end
    local ok, err = pcall(function()
      vim.lsp.config('cjls', { cmd = command, cmd_env = { STDX = '$HOME/sdk' } })

      -- act
      environment.prepare()
      local config = vim.lsp.config.cjls
      local wrapped = config.cmd
      environment.prepare()
      local prepared = vim.lsp.config.cjls.cmd
      local original = environment.command(config)
      local transport
      t.with_env({ HOME = '/home/user' }, function()
        transport = wrapped({}, config)
      end)

      -- assert
      t.eq(wrapped, prepared, 'not wrapped twice')
      t.eq(command, original)
      t.eq('transport', transport)
      t.eq('/home/user/sdk', seen.cmd_env.STDX)
      t.eq('$HOME/sdk', config.cmd_env.STDX)
      t.eq(command, seen.cmd)
    end)
    vim.lsp.config.cjls = previous
    if not ok then
      error(err)
    end
  end,

  ['spawned process receives expanded values before initialize'] = function()
    -- arrange
    local previous = vim.deepcopy(vim.lsp.config.cjls)
    local dir = t.tempdir()
    local exited, transport
    local ok, err = pcall(function()
      local script = t.write(dir .. '/environment.lua', {
        "vim.fn.writefile({ vim.env.CJLS_TEST_PATH, os.getenv('CJLS_TEST_EMPTY') or 'unset' }, arg[1])",
        "vim.cmd('qall!')",
      })
      local destination = dir .. '/environment.txt'
      vim.lsp.config('cjls', {
        cmd = { vim.v.progpath, '--clean', '--headless', '-l', script, destination },
        cmd_env = {
          CJLS_TEST_PATH = '${CJLS_TEST_SDK}/static/stdx',
          CJLS_TEST_SDK = '$CJLS_TEST_HOME/sdk',
          CJLS_TEST_EMPTY = '',
        },
        detached = false,
      })

      -- act
      environment.prepare()
      local config = vim.lsp.config.cjls
      t.with_env({ CJLS_TEST_HOME = '/home/test user' }, function()
        transport = config.cmd({
          on_exit = function(code)
            exited = code
          end,
        }, config)
      end)
      t.wait('child process did not exit', function()
        return exited ~= nil
      end)
      local received = vim.fn.readfile(destination)

      -- assert
      t.eq(0, exited)
      t.eq({ '/home/test user/sdk/static/stdx', '' }, received)
    end)
    if transport and exited == nil then
      transport.terminate()
      vim.wait(t.TIMEOUT_MS, function()
        return exited ~= nil
      end)
    end
    vim.lsp.config.cjls = previous
    vim.fn.delete(dir, 'rf')
    if not ok then
      error(err)
    end
  end,

  ['command list launch forwards process options and expanded environment'] = function()
    -- arrange
    local previous = vim.deepcopy(vim.lsp.config.cjls)
    local original_start = vim.lsp.rpc.start
    local seen
    local ok, err = pcall(function()
      vim.lsp.rpc.start = function(command, dispatchers, options)
        seen = { command, dispatchers, options }
        return 'transport'
      end
      vim.lsp.config('cjls', {
        cmd = { 'custom-cjls', '--flag' },
        cmd_env = { SDK = '~/sdk' },
        cmd_cwd = '/workspace',
        detached = false,
      })

      -- act
      environment.prepare()
      local config = vim.lsp.config.cjls
      local transport
      t.with_env({ HOME = '/home/user' }, function()
        transport = config.cmd({ notification = 'handler' }, config)
      end)
      local command = environment.command(config)

      -- assert
      t.eq('transport', transport)
      t.eq({ 'custom-cjls', '--flag' }, command)
      t.eq({
        { 'custom-cjls', '--flag' },
        { notification = 'handler' },
        { cwd = '/workspace', env = { SDK = '/home/user/sdk' }, detached = false },
      }, seen)
    end)
    vim.lsp.rpc.start = original_start
    vim.lsp.config.cjls = previous
    if not ok then
      error(err)
    end
  end,
}
