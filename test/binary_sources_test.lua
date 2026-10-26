local t = require('t')
local sources = require('cangjie.binary_sources')

local function report(id, roots)
  sources.handler(nil, { roots = vim.tbl_map(vim.uri_from_fname, roots) }, { client_id = id })
end

-- Preserve skip values and failure traces while always releasing session state.
local function with_cleanup(run, cleanup)
  local ok, err = xpcall(run, function(e)
    return type(e) == 'table' and e or debug.traceback(e, 2)
  end)
  cleanup()
  if not ok then error(err, 0) end
end

return {
  ['the real server protects an open binary source and restores it on exit'] = function()
    -- arrange
    if not vim.env.CJLS_BIN then t.skip('no CJLS_BIN') end
    local dir = t.tempdir()
    local client, id
    with_cleanup(function()
      local root = dir .. '/library sources'
      local file = t.write(root .. '/lib.cj', { 'package lib' })
      t.write(dir .. '/cj-project.json', { vim.json.encode({
        modules = {},
        binaries = { { name = 'lib', paths = {}, sources = root } },
      }) })
      vim.cmd.edit(vim.fn.fnameescape(file))
      local buf = vim.api.nvim_get_current_buf()
      local config = dofile(t.root .. '/lsp/cjls.lua')
      config.name = 'cjls-readonly-test'
      config.cmd = { vim.env.CJLS_BIN }
      config.root_dir = dir

      -- act: the real server reports the binary source root
      id = vim.lsp.start(config)
      client = vim.lsp.get_client_by_id(id)
      t.wait('cjls to initialize', function() return client.initialized end)
      if not (client.server_capabilities.experimental or {}).binarySourceRoots then
        t.skip('server does not support cjls/binarySourceRoots')
      end
      t.wait('binary source roots from cjls', function() return not vim.bo[buf].modifiable end)

      -- assert
      t.eq(true, vim.bo[buf].readonly)

      -- act
      client:stop()
      t.wait('source options restored after server exit', function() return vim.bo[buf].modifiable end)

      -- assert
      t.eq(false, vim.bo[buf].readonly)
    end, function()
      if client then
        client:stop(true)
        t.wait('test client to stop', function() return client:is_stopped() end)
      end
      if id then sources.clear(id) end
      vim.fn.delete(dir, 'rf')
    end)
  end,
  ['existing and new buffers are protected, siblings and path dependencies stay editable'] = function()
    -- arrange
    local dir = t.tempdir()
    with_cleanup(function()
      local root = dir .. '/std sources #1'
      local file = t.write(root .. '/core.cj', { 'package std.core' })
      local other = t.write(root .. '/collection/list.cj', { 'package std.collection' })
      local sibling = t.write(root .. '-other/main.cj', { 'main() {}' })
      local dependency = t.write(dir .. '/dependency/main.cj', { 'main() {}' })
      vim.cmd.edit(vim.fn.fnameescape(file))
      local existing = vim.api.nvim_get_current_buf()

      -- act
      report(1001, { root })
      local edited = pcall(vim.api.nvim_buf_set_lines, existing, 0, 1, false, { 'edited' })

      -- assert
      t.eq(true, vim.bo[existing].readonly)
      t.eq(false, vim.bo[existing].modifiable)
      t.eq(false, edited)

      -- act: a buffer opened after the notification is protected too
      vim.cmd.edit(vim.fn.fnameescape(other))

      -- assert
      t.eq(false, vim.bo.modifiable)

      -- act
      vim.cmd.edit(vim.fn.fnameescape(sibling))

      -- assert
      t.eq(true, vim.bo.modifiable)

      -- act
      vim.cmd.edit(vim.fn.fnameescape(dependency))

      -- assert
      t.eq(true, vim.bo.modifiable)

      -- act
      sources.clear(1001)

      -- assert
      t.eq(false, vim.bo[existing].readonly)
      t.eq(true, vim.bo[existing].modifiable)
    end, function()
      sources.clear(1001)
      vim.fn.delete(dir, 'rf')
    end)
  end,
  ['replacement and multiple sessions restore original options only after the last root leaves'] = function()
    -- arrange
    local dir = t.tempdir()
    with_cleanup(function()
      local file = t.write(dir .. '/main.cj', { 'main() {}' })
      vim.cmd.edit(vim.fn.fnameescape(file))
      vim.bo.readonly = true
      report(1002, { dir })
      report(1003, { dir })

      -- act
      report(1002, {})

      -- assert
      t.eq(false, vim.bo.modifiable)

      -- act
      sources.clear(1003)

      -- assert
      t.eq(true, vim.bo.readonly)
      t.eq(true, vim.bo.modifiable)
    end, function()
      sources.clear(1002)
      sources.clear(1003)
      vim.fn.delete(dir, 'rf')
    end)
  end,
}
