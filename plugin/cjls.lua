-- The language server: enabled for Cangjie buffers, and downloaded from its GitHub release when
-- there is no cjls on PATH (lua/cangjie/install.lua).
if vim.g.loaded_cjls then
  return
end
vim.g.loaded_cjls = true

local install = require('cangjie.install')

-- After whatever is on PATH, so a cjls of one's own wins over the download
vim.env.PATH = vim.env.PATH .. (vim.fn.has('win32') == 1 and ';' or ':') .. install.bin_dir()

local function install_and_start(version)
  vim.notify('cjls: downloading ' .. (version or 'the latest release') .. '…')
  install.install({
    version = version,
    on_done = function(err)
      if err then
        return vim.notify(
          'cjls: ' .. err .. '\nBuild cjls from source and put it on PATH, or retry with :CjlsInstall',
          vim.log.levels.ERROR
        )
      end
      vim.notify('cjls: installed ' .. install.installed())
      -- starts the server in the Cangjie buffers already open
      vim.lsp.enable('cjls')
    end,
  })
end

vim.api.nvim_create_user_command('CjlsInstall', function()
  install_and_start(install.wanted())
end, { desc = 'Download the cjls binary from its GitHub release' })

-- cjls/memoryUsage (lua/cangjie/cjls.lua)
vim.api.nvim_create_user_command('CjlsMemoryUsage', function(args)
  require('cangjie.cjls').show_memory_usage({ collect = args.bang })
end, { bang = true, desc = "cjls's heap and collections; with ! after a collection" })

vim.api.nvim_create_user_command('CjlsHeapDump', function(args)
  require('cangjie.cjls').heap_dump(args.args)
end, { nargs = '?', complete = 'file', desc = "Write cjls's heap dump, for cjprof heap -i" })

-- Once per session, at the first Cangjie buffer: download the server if it is missing, or if the
-- plugin (or `vim.g.cjls_version`) has moved on to another release since
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'cangjie',
  once = true,
  group = vim.api.nvim_create_augroup('cjls.install', {}),
  callback = function()
    local cmd = vim.lsp.config.cjls and vim.lsp.config.cjls.cmd
    if type(cmd) ~= 'table' or cmd[1] ~= 'cjls' then
      return -- pointed at a binary of one's own
    end
    local exe = vim.fn.exepath('cjls')
    if exe ~= '' and not vim.startswith(vim.fs.normalize(exe), vim.fs.normalize(install.bin_dir())) then
      return -- one's own on PATH
    end
    local wanted = install.wanted()
    if exe == '' or (wanted and wanted ~= install.installed()) then
      install_and_start(wanted)
    end
  end,
})

vim.lsp.enable('cjls')
