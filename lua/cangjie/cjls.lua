-- What cjls answers beyond LSP, in cjls's `docs/lsp-extensions.md`: `cjls/memoryUsage`, the
-- Cangjie runtime's numbers for the server's heap and collections, and a heap dump on request.

local M = {}

local MIB = 1024 * 1024

---@class cangjie.cjls.Error
---@field code? integer the server's error code; none when the request was never sent
---@field message string

--- The cjls client to ask, `on_client(client)`, or `on_error(message)` without one: the client
--- attached to the current buffer, else the only one running, else the one picked among them.
---@param on_client fun(client: vim.lsp.Client)
---@param on_error fun(message: string)
function M.client(on_client, on_error)
  -- one stopped but not yet gone would never answer
  local function clients(filter)
    return vim.tbl_filter(function(client)
      return not client:is_stopped()
    end, vim.lsp.get_clients(vim.tbl_extend('force', { name = 'cjls' }, filter or {})))
  end
  local attached = clients({ bufnr = 0 })[1]
  if attached then
    return on_client(attached)
  end
  local running = clients()
  if #running == 0 then
    return on_error('cjls is not running')
  end
  if #running == 1 then
    return on_client(running[1])
  end
  vim.ui.select(running, {
    prompt = 'cjls:',
    format_item = function(client)
      return client.root_dir or ('client ' .. client.id)
    end,
  }, function(client)
    if client then
      on_client(client)
    end
  end)
end

--- Why `client` cannot be asked `cjls/memoryUsage`, or nil if it can.
---@param client vim.lsp.Client
---@return string?
function M.unsupported(client)
  local experimental = client.server_capabilities and client.server_capabilities.experimental
  if type(experimental) == 'table' and experimental.memoryUsage == true then
    return nil
  end
  local version = client.server_info and client.server_info.version or 'of an unknown version'
  return 'cjls ' .. version .. ' does not answer cjls/memoryUsage: it needs a newer cjls (:CjlsInstall)'
end

--- Sends `cjls/memoryUsage` to `client`, never waiting for it: `collect` can take seconds.
---@param client vim.lsp.Client
---@param params table
---@param on_done fun(err?: cangjie.cjls.Error, result?: table)
local function request(client, params, on_done)
  local why = M.unsupported(client)
  if why then
    return on_done({ message = why })
  end
  -- an empty table goes out as `[]`, which is no params object
  client:request('cjls/memoryUsage', next(params) and params or vim.empty_dict(), function(err, result)
    on_done(err, result)
  end)
end

--- `cjls/memoryUsage`, for scripts: `on_done(err, result)`, the result as the server sent it, the
--- error the server's or, when nothing was sent, one with only a `message`.
---@param opts? { collect?: boolean, heapDump?: string } the request's params, sent as they are
---@param on_done fun(err?: cangjie.cjls.Error, result?: table)
function M.memory_usage(opts, on_done)
  M.client(function(client)
    request(client, opts or {}, on_done)
  end, function(message)
    on_done({ message = message })
  end)
end

local function mib(bytes)
  return string.format('%.1f MiB', bytes / MIB)
end

--- The report of a `cjls/memoryUsage` result, two lines.
---@param result table
---@param root? string the server's root_dir
---@param collected boolean whether a collection came first
---@return string
function M.report(result, root, collected)
  local held = collected and ('held ' .. mib(result.allocatedHeap) .. ' (after a collection)')
    or ('allocated ' .. mib(result.allocatedHeap))
  local lines = {
    string.format(
      'cjls%s: %s · heap %.1f / %s',
      root and (' (' .. vim.fn.fnamemodify(root, ':~') .. ')') or '',
      held,
      result.usedHeap / MIB,
      mib(result.maxHeap)
    ),
    string.format(
      'collections %d, %.1f ms, freed %s · %d threads',
      result.gcCount,
      result.gcTime / 1000,
      mib(result.gcFreed),
      result.threads
    ),
  }
  if not collected then
    table.insert(lines, 'garbage not collected yet included: :CjlsMemoryUsage! gives what is actually held')
  end
  return table.concat(lines, '\n')
end

local function notify_error(err)
  vim.notify('cjls: ' .. err.message, vim.log.levels.ERROR)
end

--- `:CjlsMemoryUsage[!]`: the numbers, after a collection with `collect`.
---@param opts? { collect?: boolean }
function M.show_memory_usage(opts)
  local collect = opts and opts.collect or false
  M.client(function(client)
    if collect and not M.unsupported(client) then
      vim.notify('cjls: collecting…')
    end
    request(client, collect and { collect = true } or {}, function(err, result)
      if err then
        return notify_error(err)
      end
      vim.notify(M.report(result, client.root_dir, collect), vim.log.levels.INFO)
    end)
  end, function(message)
    notify_error({ message = message })
  end)
end

--- Where `:CjlsHeapDump [path]` writes: `path` absolute against Neovim's cwd, `~` and environment
--- variables expanded (the server's cwd is not Neovim's); without one, a new file in
--- `stdpath('log')`.
---@param path? string
---@return string
function M.dump_path(path)
  if not path or path == '' then
    path = vim.fs.joinpath(vim.fn.stdpath('log'), 'cjls-heap-' .. os.date('%Y%m%d-%H%M%S') .. '.data')
  end
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fs.normalize(path), ':p'))
end

--- `:CjlsHeapDump [path]`: a collection, then a heap dump written to `path`, for `cjprof heap -i`.
---@param path? string
function M.heap_dump(path)
  local target = M.dump_path(path)
  M.client(function(client)
    if not M.unsupported(client) then
      vim.notify('cjls: collecting…')
    end
    request(client, { collect = true, heapDump = target }, function(err)
      if err then
        return notify_error(err)
      end
      vim.notify('cjls: heap dump written to ' .. target .. '; open it with cjprof heap -i ' .. target)
    end)
  end, function(message)
    notify_error({ message = message })
  end)
end

return M
