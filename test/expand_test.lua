-- Macro expansion (cjls's D103): `:CjlsExpandMacro` in a scratch split, and the files the server
-- expands under `.cache/cjls/expanded/`, read-only and attached to the server of their source.
local t = require('t')
local expand = require('cangjie.expand')

--- Waits until `cond` holds, however long: a hang is CI's to end.
local function eventually(cond)
  while not cond() do
    vim.wait(100, cond)
  end
end

--- Asks cjls `method` with the params `make_params()` makes until `done(result)` holds, answering
--- nothing or ContentModified while it loads, and returns that result.
local function ask_until(client, method, make_params, done)
  while true do
    local answer
    client:request(method, make_params(), function(err, result)
      answer = { err = err, result = result ~= vim.NIL and result or nil }
    end, 0)
    eventually(function()
      return answer ~= nil
    end)
    local modified = answer.err and answer.err.code == vim.lsp.protocol.ErrorCodes.ContentModified
    assert(modified or not answer.err, vim.inspect(answer.err))
    if not modified and done(answer.result) then
      return answer.result
    end
  end
end

--- The fixture's `derive.cj`, the cursor on `@Derive[Equatable]`, once cjls is attached to it and
--- says it expands macros, or skips the case.
local function on_derive()
  if not vim.env.CJLS_BIN then
    t.skip('no CJLS_BIN')
  end
  vim.cmd.edit(t.fixture .. '/src/derive.cj')
  local client
  t.wait('cjls did not attach and initialize (see :LspLog)', function()
    client = vim.lsp.get_clients({ name = 'cjls', bufnr = 0 })[1]
    return client ~= nil and client.initialized
  end)
  local experimental = client.server_capabilities.experimental
  if type(experimental) ~= 'table' or not experimental.expandMacro then
    t.skip('this cjls expands no macros')
  end
  vim.api.nvim_win_set_cursor(0, { 5, 1 })
  return client
end

--- Captures `vim.notify` while `fn(messages)` runs, then puts it back, and returns what it got.
local function notified(fn)
  local messages, saved = {}, vim.notify
  vim.notify = function(msg)
    table.insert(messages, msg)
  end
  local ok, err = pcall(fn, messages)
  vim.notify = saved
  if not ok then
    error(err, 0)
  end
  return messages
end

return {
  ['an expanded file belongs to the root of the server of its source'] = function()
    -- arrange: a workspace whose module has a cjpm.toml of its own
    local ws = t.tempdir()
    t.write(ws .. '/cjpm.toml', { '[workspace]' })
    t.write(ws .. '/mod/cjpm.toml', { '[package]' })
    local function root_dir(path)
      local bufnr = vim.fn.bufadd(path)
      local root
      vim.lsp.config.cjls.root_dir(bufnr, function(dir)
        root = dir
      end)
      return root
    end

    -- act, assert
    t.eq(ws .. '/mod', root_dir(ws .. '/.cache/cjls/expanded/mod/src/a.cj.macrocall'), 'an expanded file')
    t.eq(ws .. '/mod', root_dir(ws .. '/mod/src/a.cj'), 'a source file')
    t.eq(ws .. '/mod', root_dir(ws .. '/mod/src/a.cj.macrocall'), "cjc's dump")
    t.eq(nil, expand.source_of(ws .. '/.cache/cjls/expanded/a.cj'), 'not a .macrocall')
  end,

  ['an expanded file maps back to its source, under its project'] = function()
    -- arrange
    local ws = t.tempdir()

    -- act, assert
    t.eq(ws .. '/mod/src/a.cj', expand.source_of(ws .. '/mod/.cache/cjls/expanded/src/a.cj.macrocall'))
    t.eq(nil, expand.source_of(ws .. '/expanded/src/a.cj.macrocall'), 'expanded/ of no cjls directory')
    t.eq(nil, expand.source_of(ws .. '/.cache/cjls/expanded/.macrocall'), 'no source name')
  end,

  ["an expanded file of the user's cache maps back through BASE"] = function()
    -- arrange: the project could not be written, so cjls wrote into its directory of the user's cache
    local project = t.tempdir()
    local dir = t.tempdir() .. '/cjls/project-0123abcd'
    t.write(dir .. '/LAYOUT', { '1' })
    vim.fn.writefile({ project }, dir .. '/BASE', 'b')
    local nobase = t.tempdir() .. '/cjls/other-0123abcd'
    vim.fn.mkdir(nobase, 'p')

    -- act, assert
    t.eq(project .. '/src/a.cj', expand.source_of(dir .. '/expanded/src/a.cj.macrocall'))
    t.eq(nil, expand.source_of(nobase .. '/expanded/src/a.cj.macrocall'), 'no BASE')
  end,

  ['an expanded file opens read-only and unmodifiable, a dump of cjc does not'] = function()
    -- arrange
    local root = t.tempdir()
    local expanded = t.write(root .. '/.cache/cjls/expanded/src/a.cj.macrocall', { 'main() {}' })
    local dump = t.write(root .. '/src/a.cj.macrocall', { 'main() {}' })

    -- act
    vim.cmd.edit(expanded)
    local expanded_buf = vim.api.nvim_get_current_buf()
    vim.cmd.edit(dump)

    -- assert
    t.eq('cangjie', vim.bo[expanded_buf].filetype, 'filetype')
    t.eq(true, vim.bo[expanded_buf].readonly, 'readonly')
    t.eq(false, vim.bo[expanded_buf].modifiable, 'modifiable')
    t.eq(true, vim.bo.modifiable, "cjc's dump is modifiable")
  end,

  ['an expanded file the server wrote again is read again when shown'] = function()
    -- arrange
    local path = t.write(t.tempdir() .. '/.cache/cjls/expanded/src/a.cj.macrocall', { 'old' })
    vim.cmd.edit(path)
    vim.fn.writefile({ 'new' }, path)

    -- act
    expand.reload(vim.uri_from_fname(path))

    -- assert
    t.eq({ 'new' }, t.lines())
    t.eq(false, vim.bo.modifiable, 'modifiable')
  end,

  ['an expansion is shown in an unmodifiable scratch split, with no server'] = function()
    -- arrange
    local source = t.buffer({ 'main() {}' })

    -- act
    local bufnr = expand.show({ name = '@Derive', expansion = 'extend Point <: Equatable<Point> {\n}' })
    expand.show({ name = '@Derive', expansion = 'extend Point {\n}' })

    -- assert
    t.eq(2, #vim.api.nvim_tabpage_list_wins(0), 'windows')
    t.eq(bufnr, vim.api.nvim_get_current_buf(), 'the same buffer, again')
    t.eq('cjls://expand/@Derive', vim.api.nvim_buf_get_name(bufnr), 'name')
    t.eq({ 'extend Point {', '}' }, t.lines(bufnr))
    t.eq('cangjie', vim.bo[bufnr].filetype, 'filetype')
    t.eq('nofile', vim.bo[bufnr].buftype, 'buftype')
    t.eq(false, vim.bo[bufnr].modifiable, 'modifiable')
    t.eq({}, vim.lsp.get_clients({ bufnr = bufnr }), 'clients')
    t.eq(true, vim.api.nvim_buf_is_valid(source), 'the source is kept')
  end,

  [':CjlsExpandMacro without cjls says so'] = function()
    -- arrange
    t.buffer({ 'main() {}' })

    -- act
    local messages = notified(function()
      vim.cmd.CjlsExpandMacro()
    end)

    -- assert
    t.eq({ 'cjls: not attached to this buffer' }, messages)
  end,

  [':CjlsExpandMacro shows what @Derive[Equatable] expands to'] = function()
    -- arrange: cjls has an expansion there once it has loaded
    local client = on_derive()
    local source = vim.api.nvim_get_current_buf()
    ask_until(client, 'cjls/expandMacro', function()
      return vim.lsp.util.make_position_params(0, client.offset_encoding)
    end, function(result)
      return result ~= nil
    end)

    -- act
    vim.cmd.CjlsExpandMacro()
    local bufnr
    eventually(function()
      bufnr = vim.fn.bufnr('cjls://expand/@Derive')
      return bufnr ~= -1
    end)

    -- assert
    local text = table.concat(t.lines(bufnr), '\n')
    assert(text:find('extend', 1, true), 'no extend in the expansion:\n' .. text)
    t.eq(bufnr, vim.api.nvim_get_current_buf(), 'the expansion has the focus')
    t.eq(source, vim.api.nvim_win_get_buf(vim.fn.win_getid(vim.fn.winnr('#'))), 'the source stays beside it')
  end,

  [':CjlsExpandMacro off a macro call says there is none'] = function()
    -- arrange
    local client = on_derive()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    -- once the call has its expansion, the server has loaded what it needs to say there is none
    local on_call = vim.lsp.util.make_position_params(0, client.offset_encoding)
    on_call.position = { line = 4, character = 1 }
    ask_until(client, 'cjls/expandMacro', function()
      return on_call
    end, function(result)
      return result ~= nil
    end)

    -- act
    local messages = notified(function(got)
      vim.cmd.CjlsExpandMacro()
      eventually(function()
        return #got > 0
      end)
    end)

    -- assert
    t.eq({ 'cjls: no macro expansion here' }, messages)
  end,

  ['the code action "Expand macro" opens the expanded file, attached to cjls'] = function()
    -- arrange: the action is offered once cjls has the expansion
    local client = on_derive()
    local function range_params()
      local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
      params.context = { diagnostics = {} }
      return params
    end
    local function expand_action(action)
      return action.title:match('^Expand macro') ~= nil
    end
    ask_until(client, 'textDocument/codeAction', range_params, function(actions)
      return vim.iter(actions or {}):any(expand_action)
    end)
    local expanded = t.fixture .. '/.cache/cjls/expanded/src/derive.cj.macrocall'

    -- act: executeCommand, then window/showDocument
    vim.lsp.buf.code_action({ apply = true, filter = expand_action })
    eventually(function()
      return vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == expanded
    end)
    eventually(function()
      return #vim.lsp.get_clients({ name = 'cjls', bufnr = 0 }) > 0
    end)

    -- assert
    local text = table.concat(t.lines(), '\n')
    pcall(vim.fn.delete, t.fixture .. '/.cache', 'rf')
    assert(text:find('extend', 1, true), 'no extend in the expanded file:\n' .. text)
    t.eq('cangjie', vim.bo.filetype, 'filetype')
    t.eq(false, vim.bo.modifiable, 'modifiable')
    t.eq(client.id, vim.lsp.get_clients({ name = 'cjls', bufnr = 0 })[1].id, 'the client of the source')
  end,
}
