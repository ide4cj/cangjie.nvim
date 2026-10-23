local t = require('t')
local sources = require('cangjie.binary_sources')

local function report(id, roots)
  sources.handler(nil, { roots = vim.tbl_map(vim.uri_from_fname, roots) }, { client_id = id })
end

return {
  ['the real server protects an open binary source and restores it on exit'] = function()
    if not vim.env.CJLS_BIN then t.skip('no CJLS_BIN') end
    local dir = t.tempdir()
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
    local id = vim.lsp.start(config)
    local client = vim.lsp.get_client_by_id(id)
    t.wait('cjls to initialize', function() return client.initialized end)
    if not (client.server_capabilities.experimental or {}).binarySourceRoots then
      client:stop()
      t.skip('server does not support cjls/binarySourceRoots')
    end
    t.wait('binary source roots from cjls', function() return not vim.bo[buf].modifiable end)
    t.eq(true, vim.bo[buf].readonly)
    client:stop()
    t.wait('source options restored after server exit', function() return vim.bo[buf].modifiable end)
    t.eq(false, vim.bo[buf].readonly)
  end,
  ['existing and new buffers are protected, siblings and path dependencies stay editable'] = function()
    local dir = t.tempdir()
    local root = dir .. '/std sources #1'
    local file = t.write(root .. '/core.cj', { 'package std.core' })
    vim.cmd.edit(vim.fn.fnameescape(file))
    local existing = vim.api.nvim_get_current_buf()
    report(1001, { root })
    t.eq(true, vim.bo[existing].readonly)
    t.eq(false, vim.bo[existing].modifiable)
    t.eq(false, pcall(vim.api.nvim_buf_set_lines, existing, 0, 1, false, { 'edited' }))
    local other = t.write(root .. '/collection/list.cj', { 'package std.collection' })
    vim.cmd.edit(vim.fn.fnameescape(other))
    t.eq(false, vim.bo.modifiable)
    local sibling = t.write(root .. '-other/main.cj', { 'main() {}' })
    vim.cmd.edit(vim.fn.fnameescape(sibling))
    t.eq(true, vim.bo.modifiable)
    local dependency = t.write(dir .. '/dependency/main.cj', { 'main() {}' })
    vim.cmd.edit(vim.fn.fnameescape(dependency))
    t.eq(true, vim.bo.modifiable)
    sources.clear(1001)
    t.eq(false, vim.bo[existing].readonly)
    t.eq(true, vim.bo[existing].modifiable)
  end,
  ['replacement and multiple sessions restore original options only after the last root leaves'] = function()
    local dir = t.tempdir()
    local file = t.write(dir .. '/main.cj', { 'main() {}' })
    vim.cmd.edit(vim.fn.fnameescape(file))
    vim.bo.readonly = true
    report(1002, { dir })
    report(1003, { dir })
    report(1002, {})
    t.eq(false, vim.bo.modifiable)
    sources.clear(1003)
    t.eq(true, vim.bo.readonly)
    t.eq(true, vim.bo.modifiable)
    sources.clear(1002)
  end,
}
