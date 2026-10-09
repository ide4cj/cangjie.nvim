-- Runs the tests headless, from any directory:
--
--   nvim --clean --headless -u test/run.lua
--
-- Every `test/*_test.lua` returns its cases, `{ ['what it does'] = function() … end }`, each run
-- in a buffer of its own. `TEST=<lua pattern>` runs those whose `file: case` matches. A case fails
-- by throwing, and is skipped by `t.skip(why)`: those of the server without a cjls binary in
-- CJLS_BIN.

-- the plugin as a plugin manager installs it: its root on the runtimepath
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p'))))
vim.opt.runtimepath:prepend(root)
package.path = root .. '/test/?.lua;' .. package.path

-- never the bare `cjls`, which the plugin would download
vim.lsp.config('cjls', { cmd = { vim.env.CJLS_BIN or 'cjls-not-under-test' } })

local function run()
  if not vim.env.CJLS_BIN then
    vim.lsp.enable('cjls', false)
  end
  local counts = { ok = 0, skip = 0, FAIL = 0 }
  for _, file in ipairs(vim.fn.glob(root .. '/test/*_test.lua', false, true)) do
    local cases = dofile(file)
    local names = vim.tbl_keys(cases)
    table.sort(names)
    for _, name in ipairs(names) do
      local id = vim.fn.fnamemodify(file, ':t:r') .. ': ' .. name
      if not vim.env.TEST or id:match(vim.env.TEST) then
        vim.cmd('silent! %bwipeout!')
        local ok, err = xpcall(cases[name], function(e)
          return type(e) == 'table' and e or debug.traceback(e, 2)
        end)
        local status = ok and 'ok' or (type(err) == 'table' and err.skip and 'skip' or 'FAIL')
        counts[status] = counts[status] + 1
        local detail = status == 'skip' and (': ' .. err.skip) or (status == 'FAIL' and ('\n' .. tostring(err)) or '')
        io.stdout:write(string.format('%-4s %s%s\n', status, id, detail))
      end
    end
  end
  io.stdout:write(string.format('\n%d passed, %d skipped, %d failed\n', counts.ok, counts.skip, counts.FAIL))
  vim.cmd(counts.FAIL > 0 and 'cquit 1' or 'qall!')
end

-- filetype detection is switched on only after the init file
vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = vim.schedule_wrap(run) })
