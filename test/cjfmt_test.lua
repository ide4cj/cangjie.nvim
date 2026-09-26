-- cjfmt: found in the SDK, run on the buffer, its result applied. The cases that run it are
-- skipped without cjfmt; CI installs the SDK and points CANGJIE_HOME at it, nothing more.
local t = require('t')
local cjfmt = require('cangjie.cjfmt')

local EXE = t.IS_WINDOWS and 'cjfmt.exe' or 'cjfmt'

--- A fake SDK at `home` with a cjfmt in it, which only has to look executable.
local function sdk(home)
  local exe = t.write(home .. '/tools/bin/' .. EXE, { '' })
  vim.uv.fs_chmod(exe, tonumber('755', 8))
  return exe
end

--- The real cjfmt, or skips the case.
local function need_cjfmt()
  local tool = cjfmt.find()
  if not tool then
    t.skip('no cjfmt')
  end
  return tool
end

local UNFORMATTED = { 'package a', 'main():Int64{', 'let x=1', '    x}' }
local FORMATTED = { 'package a', '', 'main(): Int64 {', '    let x = 1', '    x', '}' }

local TWO_FUNCTIONS = { 'package a', '', 'func f(){', 'let x=1', '}', '', 'func g(){', 'let y=2', '}' }

return {
  ['cjfmt on PATH wins, with the SDK it came with'] = function()
    -- arrange
    local dir = t.tempdir()
    local exe = sdk(dir .. '/on-path')
    sdk(dir .. '/home')

    -- act
    local tool
    t.with_env({ PATH = dir .. '/on-path/tools/bin', CANGJIE_HOME = dir .. '/home' }, function()
      tool = cjfmt.find()
    end)

    -- assert
    t.eq(vim.fs.normalize(vim.uv.fs_realpath(exe)), vim.fs.normalize(vim.uv.fs_realpath(tool.cmd)), 'cmd')
    t.eq(vim.uv.fs_realpath(dir .. '/on-path'), vim.uv.fs_realpath(tool.home), 'home')
    vim.fn.delete(dir, 'rf')
  end,

  ['without cjfmt on PATH it is taken from CANGJIE_HOME'] = function()
    -- arrange
    local dir = t.tempdir()
    local exe = sdk(dir .. '/sdk')
    sdk(dir .. '/user/.cangjie')

    -- act
    local tool
    t.with_env({ PATH = dir, CANGJIE_HOME = dir .. '/sdk', HOME = dir .. '/user' }, function()
      tool = cjfmt.find()
    end)

    -- assert
    t.eq({ cmd = exe, home = dir .. '/sdk' }, tool)
    vim.fn.delete(dir, 'rf')
  end,

  ['without CANGJIE_HOME it is taken from the SDK in the home directory'] = function()
    for _, name in ipairs({ '.cangjie', 'cangjie' }) do
      -- arrange
      local dir = t.tempdir()
      local exe = sdk(dir .. '/user/' .. name)

      -- act
      local tool
      t.with_env({ PATH = dir, CANGJIE_HOME = vim.NIL, HOME = dir .. '/user' }, function()
        tool = cjfmt.find()
      end)

      -- assert
      t.eq({ cmd = exe, home = dir .. '/user/' .. name }, tool, name)
      vim.fn.delete(dir, 'rf')
    end
  end,

  ['without cjfmt anywhere find says where it looked'] = function()
    -- arrange
    local dir = t.tempdir()

    -- act
    local tool, err
    t.with_env({ PATH = dir, CANGJIE_HOME = vim.NIL, HOME = dir }, function()
      tool, err = cjfmt.find()
    end)

    -- assert
    t.eq(nil, tool, 'tool')
    assert(err and err:match('CANGJIE_HOME'), tostring(err))
    vim.fn.delete(dir, 'rf')
  end,

  ['a cjfmt outside an SDK runs in the environment as it is'] = function()
    -- arrange
    local dir = t.tempdir()
    t.write(dir .. '/bin/' .. EXE, { '' })
    vim.uv.fs_chmod(dir .. '/bin/' .. EXE, tonumber('755', 8))

    -- act
    local tool
    t.with_env({ PATH = dir .. '/bin' }, function()
      tool = cjfmt.find()
    end)

    -- assert
    t.eq(nil, tool.home, 'home')
    t.eq(nil, cjfmt.env(tool.home), 'env')
    vim.fn.delete(dir, 'rf')
  end,

  ['the SDK hands cjfmt its home and its libraries'] = function()
    -- arrange
    local home = t.tempdir()
    vim.fn.mkdir(home .. '/runtime/lib/linux_x86_64_cjnative', 'p')

    -- act
    local env = cjfmt.env(home)

    -- assert
    t.eq(home, env.CANGJIE_HOME, 'CANGJIE_HOME')
    local libs = home .. '/tools/lib' .. (t.IS_WINDOWS and ';' or ':') .. home .. '/runtime/lib/linux_x86_64_cjnative'
    if t.IS_WINDOWS then
      t.eq(libs, env.PATH:sub(1, #libs), 'PATH')
    elseif vim.fn.has('mac') == 1 then
      t.eq(nil, env.LD_LIBRARY_PATH, 'LD_LIBRARY_PATH')
    else
      t.eq(libs, env.LD_LIBRARY_PATH:sub(1, #libs), 'LD_LIBRARY_PATH')
    end
    vim.fn.delete(home, 'rf')
  end,

  ['the configuration is the nearest cangjie-format.toml above the file'] = function()
    -- arrange
    local dir = t.tempdir()
    local outer = t.write(dir .. '/cangjie-format.toml', { 'indentWidth = 4' })
    local inner = t.write(dir .. '/inner/cangjie-format.toml', { 'indentWidth = 2' })

    -- act, assert
    t.eq(inner, cjfmt.config(dir .. '/inner/src/main.cj'), 'inner')
    t.eq(outer, cjfmt.config(dir .. '/src/main.cj'), 'outer')
    t.eq(outer, cjfmt.config(dir .. '/src'), 'a directory')
    t.eq(nil, cjfmt.config(''), 'no file')
    vim.fn.delete(dir, 'rf')
  end,

  ["errors reads each error's place and message out of cjfmt's colours"] = function()
    -- arrange: what cjfmt 1.3 prints for `main(){ let x = ` on line 2
    local output = table.concat({
      'Formatting start...',
      "\27[31merror\27[0m: expected expression after '=', found '<EOF>'",
      ' \27[36m==>\27[0m /tmp/x/input.cj:2:16:',
      '  \27[36m| \27[0m',
      "\27[31merror\27[0m: unclosed delimiter: '{'",
      ' \27[36m==>\27[0m C:/Users/me/x/input.cj:2:6:',
      '\27[33mwarning\27[0m: customized format configuration files not Exist',
      '\27[31merror\27[0m: Create target file error!',
      'Formatting complete.',
    }, '\n')

    -- act
    local errors = cjfmt.errors(output)

    -- assert
    t.eq({
      "2:16: expected expression after '=', found '<EOF>'",
      "2:6: unclosed delimiter: '{'",
      'Create target file error!',
    }, errors)
  end,

  ['text and lines round-trip a file with or without its final newline'] = function()
    t.eq('a\nb\n', cjfmt.text({ 'a', 'b' }, true))
    t.eq('a\nb', cjfmt.text({ 'a', 'b' }, false))
    t.eq({ 'a', 'b' }, cjfmt.lines('a\nb\n'))
    t.eq({ 'a', 'b' }, cjfmt.lines('a\r\nb\r\n'))
    t.eq({ 'a', '' }, cjfmt.lines('a\n\n'))
  end,

  ['apply leaves the buffer as the new lines, whatever the hunks'] = function()
    local cases = {
      { { 'a', 'b', 'c' }, { 'a', 'B', 'c' } },
      { { 'a', 'b', 'c' }, { 'x', 'a', 'b', 'c', 'y' } },
      { { 'a', 'b', 'c' }, { 'b' } },
      { { 'a', 'b', 'c' }, { '' } },
      { { '' }, { 'a', 'b' } },
      { { 'a', 'b', 'c', 'd' }, { 'a', 'c', 'x', 'd', 'e' } },
    }
    for _, case in ipairs(cases) do
      -- arrange
      local bufnr = t.buffer(case[1])

      -- act
      cjfmt.apply(bufnr, case[2])

      -- assert
      t.eq(case[2], t.lines(bufnr), vim.inspect(case[1]))
    end
  end,

  ['apply keeps the cursor and marks on the lines it does not change'] = function()
    -- arrange
    local bufnr = t.buffer({ 'package a', 'func f(){', 'let x=1', '}', 'let kept = 1' })
    vim.api.nvim_win_set_cursor(0, { 5, 4 })
    vim.api.nvim_buf_set_mark(bufnr, 'a', 5, 0, {})

    -- act
    cjfmt.apply(bufnr, { 'package a', '', 'func f() {', '    let x = 1', '}', 'let kept = 1' })

    -- assert
    t.eq({ 6, 4 }, vim.api.nvim_win_get_cursor(0), 'cursor')
    t.eq({ 6, 0 }, vim.api.nvim_buf_get_mark(bufnr, 'a'), 'mark')
  end,

  [':Cjfmt formats the buffer'] = function()
    need_cjfmt()
    -- arrange
    local dir = t.tempdir()
    t.buffer(UNFORMATTED, dir .. '/main.cj')

    -- act
    vim.cmd('Cjfmt')

    -- assert
    t.eq(FORMATTED, t.lines())
    vim.fn.delete(dir, 'rf')
  end,

  ['gq formats only the lines it is given'] = function()
    need_cjfmt()
    -- arrange
    local dir = t.tempdir()
    t.buffer(TWO_FUNCTIONS, dir .. '/main.cj')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    -- act
    vim.cmd('normal! gq2j')

    -- assert
    t.eq({ 'package a', '', 'func f(){', 'let x=1', '}', '', 'func g() {', '    let y = 2', '}' }, t.lines())
    vim.fn.delete(dir, 'rf')
  end,

  ['a syntax error leaves the buffer as it was and says where it is'] = function()
    need_cjfmt()
    -- arrange
    local dir = t.tempdir()
    local broken = { 'package a', 'main() { let x = ' }
    t.buffer(broken, dir .. '/main.cj')

    -- act
    local err = cjfmt.format_buffer()

    -- assert
    assert(err and err:match("2:%d+: expected expression after '='"), tostring(err))
    t.eq(broken, t.lines())
    vim.fn.delete(dir, 'rf')
  end,

  ["the project's cangjie-format.toml decides the indentation"] = function()
    need_cjfmt()
    -- arrange
    local dir = t.tempdir()
    t.write(dir .. '/cangjie-format.toml', { 'indentWidth = 2' })
    t.buffer(UNFORMATTED, dir .. '/src/main.cj')

    -- act
    local err = cjfmt.format_buffer()

    -- assert
    t.eq(nil, err, 'error')
    t.eq({ 'package a', '', 'main(): Int64 {', '  let x = 1', '  x', '}' }, t.lines())
    vim.fn.delete(dir, 'rf')
  end,

  ['conform gets the lines formatted, the whole or a range'] = function()
    need_cjfmt()
    -- arrange
    local formatter = require('conform.formatters.cjfmt')
    local dir = t.tempdir()
    local bufnr = t.buffer(TWO_FUNCTIONS, dir .. '/main.cj')
    local function format(range)
      local result
      local ctx = { buf = bufnr, filename = dir .. '/main.cj', dirname = dir, range = range, shiftwidth = 4 }
      assert(formatter:condition(ctx), 'the condition fails')
      formatter:format(ctx, TWO_FUNCTIONS, function(err, lines)
        result = { err = err, lines = lines }
      end)
      t.wait('conform was not called back', function()
        return result ~= nil
      end)
      t.eq(nil, result.err, 'error')
      return result.lines
    end

    -- act, assert
    t.eq({ 'package a', '', 'func f() {', '    let x = 1', '}', '', 'func g() {', '    let y = 2', '}' }, format(nil), 'whole')
    t.eq({ 'package a', '', 'func f() {', '    let x = 1', '}', '', 'func g(){', 'let y=2', '}' }, format({ start = { 3, 0 }, ['end'] = { 5, 0 } }), 'range')
    vim.fn.delete(dir, 'rf')
  end,

  ['the SDK in CANGJIE_HOME is enough, without its environment'] = function()
    local tool = need_cjfmt()
    if not tool.home then
      t.skip('cjfmt is not in an SDK')
    end
    -- arrange: nothing of envsetup's but CANGJIE_HOME, as an editor started from a desktop has
    local empty = t.tempdir()

    -- act
    local err, text
    t.with_env({ PATH = empty, CANGJIE_HOME = tool.home, LD_LIBRARY_PATH = vim.NIL }, function()
      err, text = cjfmt.format(cjfmt.text(UNFORMATTED, true))
    end)

    -- assert
    t.eq(nil, err, 'error')
    t.eq(FORMATTED, cjfmt.lines(text or ''))
    vim.fn.delete(empty, 'rf')
  end,
}
