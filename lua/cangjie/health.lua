-- `:checkhealth cangjie`: which cjls and cjfmt the plugin runs, and whether the grammar is there.
local M = {}

local function version(cmd, env)
  local ok, out = pcall(function()
    return vim.system(cmd, { text = true, env = env }):wait(5000)
  end)
  local text = ok and vim.trim((out.stdout or '') .. (out.stderr or '')) or ''
  return text ~= '' and vim.split(text, '\n')[1] or nil
end

local function check_cjls()
  vim.health.start('cjls')
  local install = require('cangjie.install')
  local cmd = vim.lsp.config.cjls and vim.lsp.config.cjls.cmd
  if type(cmd) ~= 'table' then
    return vim.health.info('`cmd` is a function: the plugin neither checks nor downloads the server')
  end
  local exe = vim.fn.exepath(cmd[1])
  if exe == '' then
    return vim.health.warn(cmd[1] .. ' is not on PATH', {
      'It is downloaded at the first Cangjie buffer; :CjlsInstall downloads it now',
      'Or build cjls and put it on PATH, or set `cmd` with vim.lsp.config',
    })
  end
  if vim.startswith(vim.fs.normalize(exe), vim.fs.normalize(install.bin_dir())) then
    vim.health.ok(exe .. ', release ' .. (install.installed() or 'unknown') .. ' downloaded by the plugin')
    local wanted = install.wanted()
    if wanted and wanted ~= install.installed() then
      vim.health.warn('the plugin wants ' .. wanted .. ': it is downloaded at the next Cangjie buffer, or :CjlsInstall')
    end
  else
    vim.health.ok(exe)
  end
  if not vim.lsp.is_enabled or vim.lsp.is_enabled('cjls') then
    return
  end
  vim.health.warn('cjls is not enabled', { "vim.lsp.enable('cjls')" })
end

local function check_cjfmt()
  vim.health.start('cjfmt')
  local cjfmt = require('cangjie.cjfmt')
  local tool, err = cjfmt.find()
  if not tool then
    return vim.health.warn(err or 'cjfmt not found', {
      'Install the Cangjie SDK: cjfmt comes with it, in tools/bin',
      'Point CANGJIE_HOME at it, or put its tools/bin on PATH',
    })
  end
  local v = version({ tool.cmd, '-v' }, cjfmt.env(tool.home))
  vim.health.ok(tool.cmd .. (v and (' (' .. v .. ')') or ''))
  local config = cjfmt.config(vim.fn.getcwd())
  if config then
    vim.health.info('configuration: ' .. config)
  else
    vim.health.info('no cangjie-format.toml above ' .. vim.fn.getcwd() .. ": cjfmt formats with the SDK's")
  end
end

local function check_grammar()
  vim.health.start('tree-sitter')
  if pcall(vim.treesitter.language.add, 'cangjie') then
    vim.health.ok('the cangjie parser is installed')
  else
    vim.health.info('no cangjie parser: highlighting comes from syntax/cangjie.vim', { ':TSInstall cangjie, with nvim-treesitter' })
  end
end

function M.check()
  check_cjls()
  check_cjfmt()
  check_grammar()
end

return M
