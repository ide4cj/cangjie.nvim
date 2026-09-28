-- The server, given a cjls binary in CJLS_BIN: it attaches to a Cangjie buffer at its package root,
-- completes `initialize`, exits with 0 after `shutdown`/`exit`, and answers `cjls/memoryUsage`.
-- `:CjlsMemoryUsage` and `:CjlsHeapDump` themselves run against a server in Lua standing in for it,
-- without CJLS_BIN.
local t = require('t')
local cjls = require('cangjie.cjls')

local MIB = 1024 * 1024
local USAGE = {
  usedHeap = 35 * MIB,
  allocatedHeap = 2.3 * MIB,
  maxHeap = 4096 * MIB,
  gcFreed = 22.8 * MIB,
  gcCount = 3,
  gcTime = 12400,
  threads = 9,
}
local SUPPORTED = { memoryUsage = true }

--- A server in Lua named cjls, rooted at `root`, attached to the current buffer unless
--- `opts.detached`, advertising `opts.experimental`. It answers `cjls/memoryUsage` with
--- `opts.answer(params)`, USAGE by default, and records the params of each such request.
---@return vim.lsp.Client client, table[] requests
local function fake(root, opts)
  opts = opts or {}
  local requests = {}
  local function cmd(dispatchers)
    local closing = false
    local id = 0
    local function exit()
      if not closing then
        closing = true
        dispatchers.on_exit(0, 0)
      end
    end
    return {
      request = function(method, params, callback)
        id = id + 1
        local err, result = nil, vim.NIL
        if method == 'initialize' then
          result = { capabilities = { experimental = opts.experimental }, serverInfo = { name = 'cjls', version = '0.0.0' } }
        elseif method == 'cjls/memoryUsage' then
          table.insert(requests, params)
          if opts.answer then
            err, result = opts.answer(params)
          else
            result = USAGE
          end
        end
        vim.schedule(function()
          callback(err, result)
        end)
        return true, id
      end,
      notify = function(method)
        if method == 'exit' then
          exit()
        end
        return true
      end,
      is_closing = function()
        return closing
      end,
      terminate = exit,
    }
  end
  local id = assert(vim.lsp.start({ name = 'cjls', cmd = cmd, root_dir = root }, { attach = not opts.detached }))
  local client = assert(vim.lsp.get_client_by_id(id))
  t.wait('the fake cjls did not initialize', function()
    return client.initialized
  end)
  return client, requests
end

--- The notifications made while `fn` runs, as `{ msg, level }`, waiting for `count` of them if given.
local function notifications(fn, count)
  local seen = {}
  local notify = vim.notify
  vim.notify = function(msg, level)
    table.insert(seen, { msg, level or vim.log.levels.INFO })
  end
  local ok, err = pcall(function()
    fn()
    if count then
      t.wait('expected ' .. count .. ' notifications, got ' .. vim.inspect(seen), function()
        return #seen >= count
      end)
    end
  end)
  vim.notify = notify
  if not ok then
    error(err, 0)
  end
  return seen
end

local function stop_all()
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop(true)
  end
  t.wait('the clients did not stop', function()
    return #vim.lsp.get_clients() == 0
  end)
end

--- cjls on the fixture, initialized and answering cjls/memoryUsage, or skips the case.
local function need_cjls()
  if not vim.env.CJLS_BIN then
    t.skip('no CJLS_BIN')
  end
  vim.cmd.edit(t.fixture .. '/src/main.cj')
  local client
  t.wait('cjls did not attach and initialize (see :LspLog)', function()
    client = vim.lsp.get_clients({ name = 'cjls', bufnr = 0 })[1]
    return client ~= nil and client.initialized
  end)
  local why = cjls.unsupported(client)
  if why then
    stop_all()
    t.skip(why)
  end
  return client
end

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

  ['cjls advertises experimental.memoryUsage'] = function()
    -- arrange, act
    local client = need_cjls()

    -- assert
    t.eq(true, client.server_capabilities.experimental.memoryUsage)
    stop_all()
  end,

  ['memory_usage with collect answers after at least one collection'] = function()
    -- arrange
    need_cjls()

    -- act
    local done
    cjls.memory_usage({ collect = true }, function(err, result)
      done = { err = err, result = result }
    end)
    t.wait('cjls did not answer cjls/memoryUsage', function()
      return done ~= nil
    end)

    -- assert
    t.eq(nil, done.err, 'error')
    local r = done.result
    assert(r.gcCount >= 1, 'gcCount is ' .. r.gcCount)
    assert(0 < r.usedHeap and r.usedHeap <= r.maxHeap, 'usedHeap ' .. r.usedHeap .. ', maxHeap ' .. r.maxHeap)
    stop_all()
  end,

  [':CjlsHeapDump writes the dump where it is told'] = function()
    -- arrange
    need_cjls()
    local dir = t.tempdir()

    -- act
    local seen = notifications(function()
      vim.cmd('CjlsHeapDump ' .. dir .. '/heap.data')
    end, 2)

    -- assert
    t.eq(vim.log.levels.INFO, seen[2][2], seen[2][1])
    assert(vim.uv.fs_stat(dir .. '/heap.data'), 'no heap dump in ' .. dir)
    stop_all()
    vim.fn.delete(dir, 'rf')
  end,

  [':CjlsHeapDump into a directory that is not there is an error, not a stack'] = function()
    -- arrange
    need_cjls()
    local dir = t.tempdir()

    -- act
    local seen = notifications(function()
      vim.cmd('CjlsHeapDump ' .. dir .. '/missing/heap.data')
    end, 2)

    -- assert
    t.eq(vim.log.levels.ERROR, seen[2][2], seen[2][1])
    t.eq(nil, vim.uv.fs_stat(dir .. '/missing/heap.data'), 'the dump')
    stop_all()
    vim.fn.delete(dir, 'rf')
  end,

  [':CjlsMemoryUsage sends an empty params object and reports what is allocated'] = function()
    -- arrange
    vim.cmd.enew()
    local _, requests = fake('/root', { experimental = SUPPORTED })

    -- act
    local seen = notifications(function()
      vim.cmd('CjlsMemoryUsage')
    end, 1)

    -- assert
    t.eq('{}', vim.json.encode(requests[1]), 'params')
    t.eq({
      {
        table.concat({
          'cjls (/root): allocated 2.3 MiB · heap 35.0 / 4096.0 MiB',
          'collections 3, 12.4 ms, freed 22.8 MiB · 9 threads',
          'garbage not collected yet included: :CjlsMemoryUsage! gives what is actually held',
        }, '\n'),
        vim.log.levels.INFO,
      },
    }, seen)
    stop_all()
  end,

  [':CjlsMemoryUsage! collects first and reports what is held'] = function()
    -- arrange
    vim.cmd.enew()
    local _, requests = fake('/root', { experimental = SUPPORTED })

    -- act
    local seen = notifications(function()
      vim.cmd('CjlsMemoryUsage!')
    end, 2)

    -- assert
    t.eq({ { collect = true } }, requests, 'params')
    t.eq({ 'cjls: collecting…', vim.log.levels.INFO }, seen[1])
    t.eq({
      table.concat({
        'cjls (/root): held 2.3 MiB (after a collection) · heap 35.0 / 4096.0 MiB',
        'collections 3, 12.4 ms, freed 22.8 MiB · 9 threads',
      }, '\n'),
      vim.log.levels.INFO,
    }, seen[2])
    stop_all()
  end,

  ['a server without experimental.memoryUsage is sent nothing, and told why'] = function()
    for _, experimental in ipairs({ vim.NIL, {}, { memoryUsage = false } }) do
      -- arrange
      vim.cmd.enew()
      local _, requests = fake('/root', { experimental = experimental ~= vim.NIL and experimental or nil })

      -- act
      local seen = notifications(function()
        vim.cmd('CjlsMemoryUsage!')
        vim.cmd('CjlsHeapDump')
      end)

      -- assert
      t.eq({}, requests, 'requests')
      local why = 'cjls: cjls 0.0.0 does not answer cjls/memoryUsage: it needs a newer cjls (:CjlsInstall)'
      t.eq({ { why, vim.log.levels.ERROR }, { why, vim.log.levels.ERROR } }, seen, vim.inspect(experimental))
      stop_all()
    end
  end,

  ['without a running cjls the command says so'] = function()
    -- arrange
    stop_all()

    -- act
    local seen = notifications(function()
      vim.cmd('CjlsMemoryUsage')
    end)

    -- assert
    t.eq({ { 'cjls: cjls is not running', vim.log.levels.ERROR } }, seen)
  end,

  ['memory_usage hands a script the error when nothing could be sent'] = function()
    -- arrange
    stop_all()

    -- act
    local got
    cjls.memory_usage({}, function(err, result)
      got = { err = err, result = result }
    end)

    -- assert
    t.eq({ err = { message = 'cjls is not running' } }, got)
  end,

  ["a server's error is one ERROR notification with its message"] = function()
    -- arrange
    vim.cmd.enew()
    fake('/root', {
      experimental = SUPPORTED,
      answer = function()
        return { code = -32803, message = 'cannot write /nowhere/heap.data' }
      end,
    })

    -- act
    local seen = notifications(function()
      vim.cmd('CjlsHeapDump /nowhere/heap.data')
    end, 2)

    -- assert
    t.eq({ 'cjls: cannot write /nowhere/heap.data', vim.log.levels.ERROR }, seen[2])
    stop_all()
  end,

  [':CjlsHeapDump sends the path absolute, expanded, or a new file in the log directory'] = function()
    -- arrange
    vim.cmd.enew()
    local _, requests = fake('/root', { experimental = SUPPORTED })
    local cwd = t.tempdir()
    vim.fn.chdir(cwd)

    -- act
    local ok, seen = pcall(notifications, function()
      vim.cmd('CjlsHeapDump heap.data')
      vim.cmd('CjlsHeapDump ~/heap.data')
      vim.cmd('CjlsHeapDump')
    end, 6)
    vim.fn.chdir(t.root)

    -- assert
    assert(ok, seen)
    t.eq({ collect = true, heapDump = vim.fs.normalize(vim.uv.fs_realpath(cwd)) .. '/heap.data' }, requests[1], 'relative')
    t.eq(vim.fs.normalize('~/heap.data'), requests[2].heapDump, '~')
    local log = vim.fs.normalize(vim.fn.stdpath('log'))
    assert(requests[3].heapDump:match('^' .. vim.pesc(log) .. '/cjls%-heap%-%d+%-%d+%.data$'), requests[3].heapDump)
    local dump = requests[3].heapDump
    t.eq({ 'cjls: heap dump written to ' .. dump .. '; open it with cjprof heap -i ' .. dump, vim.log.levels.INFO }, seen[6])
    stop_all()
    vim.fn.delete(cwd, 'rf')
  end,

  ['with several servers and none on the buffer, the one picked is asked'] = function()
    -- arrange
    vim.cmd.enew()
    local _, a = fake('/a', { experimental = SUPPORTED, detached = true })
    local _, b = fake('/b', { experimental = SUPPORTED, detached = true })
    local select = vim.ui.select
    local offered, picked
    vim.ui.select = function(items, opts, on_choice)
      offered = vim.tbl_map(opts.format_item, items)
      picked = items[2].root_dir
      on_choice(items[2])
    end

    -- act
    local ok, err = pcall(notifications, function()
      vim.cmd('CjlsMemoryUsage')
    end, 1)
    vim.ui.select = select

    -- assert
    assert(ok, err)
    table.sort(offered)
    t.eq({ '/a', '/b' }, offered, 'offered')
    t.eq({ 1, 0 }, picked == '/a' and { #a, #b } or { #b, #a }, 'requests to the picked and the other')
    stop_all()
  end,
}
