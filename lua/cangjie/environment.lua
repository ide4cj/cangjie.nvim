local M = {}
local commands = setmetatable({}, { __mode = 'k' })

--- Expands configured values once against the inherited environment, not against each other.
function M.expand(extra, inherited, warn)
  local result = {}
  for key, value in pairs(extra or {}) do
    if type(value) ~= 'string' then
      result[key] = value
    else
      local missing = {}
      local function variable(reference, name)
        if inherited[name] ~= nil then
          return inherited[name]
        end
        missing[name] = true
        return reference
      end
      -- One scan prevents values inserted by either syntax from being expanded again.
      local parts, offset = {}, 1
      while offset <= #value do
        local first, last, name = value:find('%${([^}]+)}', offset)
        local bare_first, bare_last, bare = value:find('%$([%a_][%w_]*)', offset)
        if bare_first and (not first or bare_first < first) then
          first, last, name = bare_first, bare_last, bare
        end
        if not first then
          parts[#parts + 1] = value:sub(offset)
          break
        end
        parts[#parts + 1] = value:sub(offset, first - 1)
        parts[#parts + 1] = variable(value:sub(first, last), name)
        offset = last + 1
      end
      local expanded = table.concat(parts)
      if value == '~' or value:sub(1, 2) == '~/' or value:sub(1, 2) == '~\\' then
        local home = inherited.HOME or inherited.USERPROFILE
        if home and home ~= '' then
          expanded = home .. expanded:sub(2)
        else
          warn('cjls.cmd_env.' .. key .. ': HOME and USERPROFILE do not provide a home directory; keeping ~')
        end
      end
      if next(missing) then
        local names = vim.tbl_keys(missing)
        table.sort(names)
        warn('cjls.cmd_env.' .. key .. ': environment variables are not set: ' .. table.concat(names, ', ') .. '; keeping references')
      end
      result[key] = expanded
    end
  end
  return result
end

--- Returns the configured command for installation and health checks, even after wrapping it.
function M.command(config)
  return config and (commands[config.cmd] or config.cmd)
end

--- Wraps the resolved command before automatic LSP startup, including user-supplied commands.
function M.prepare()
  local config = vim.lsp.config.cjls
  if not config or not config.cmd or commands[config.cmd] then
    return
  end
  local command = config.cmd
  local function start(dispatchers, launch)
    launch = vim.deepcopy(launch)
    launch.cmd_env = M.expand(launch.cmd_env, vim.fn.environ(), function(message)
      vim.notify(message, vim.log.levels.WARN)
    end)
    launch.cmd = command
    if type(command) == 'function' then
      return command(dispatchers, launch)
    end
    return vim.lsp.rpc.start(command, dispatchers, {
      cwd = launch.cmd_cwd,
      env = launch.cmd_env,
      detached = launch.detached,
    })
  end
  commands[start] = command
  vim.lsp.config('cjls', { cmd = start })
end

return M
