-- Downloads a cjls release with the plugin's own installer and prints the binary's path, for CI:
--
--   nvim --clean --headless -l test/install_cjls.lua <dir> [version]
--
-- The latest release without a version. Exits with 1, saying why, when there is none to download.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(arg[0], ':p'))))
vim.opt.runtimepath:prepend(root)
local install = require('cangjie.install')

local dir = assert(arg[1], 'usage: nvim -l test/install_cjls.lua <dir> [version]')
local result
install.install({
  dir = dir,
  version = arg[2],
  on_done = function(err)
    result = err or false
  end,
})
vim.wait(5 * 60 * 1000, function()
  return result ~= nil
end)
if result ~= false then
  io.stderr:write('cjls: ' .. tostring(result or 'the download did not finish') .. '\n')
  os.exit(1)
end
io.stdout:write(vim.fs.joinpath(dir, 'bin', install.asset().exe) .. '\n')
