-- cjfmt, the formatter the Cangjie SDK ships in `tools/bin`: found without the SDK's environment,
-- run on a copy of the text, its result applied to the buffer as a diff.
--
-- cjfmt reads no stdin and writes only to a file whose name ends in `.cj`. On a syntax error it
-- exits with 0 and copies its input unchanged, so the errors it prints are what tells a failure.

local M = {}

local IS_WINDOWS = vim.fn.has('win32') == 1
local EXE = IS_WINDOWS and 'cjfmt.exe' or 'cjfmt'
local CONFIG = 'cangjie-format.toml'
local TIMEOUT_MS = 10000

---@class cangjie.cjfmt.Tool
---@field cmd string the executable
---@field home? string the SDK it came with, if it came with one

--- The SDK an executable belongs to: `<home>/tools/bin/<exe>`, symlinks resolved.
local function sdk_home(exe)
  local bin = vim.fs.dirname(vim.fs.normalize(vim.uv.fs_realpath(exe) or exe))
  local tools = vim.fs.dirname(bin)
  if vim.fs.basename(bin) == 'bin' and vim.fs.basename(tools) == 'tools' then
    return vim.fs.dirname(tools)
  end
end

--- The SDKs to look in when cjfmt is not on PATH: `$CANGJIE_HOME`, then where the SDK's archive
--- unpacks in the home directory.
local function sdk_candidates()
  local home = vim.env.HOME or vim.uv.os_homedir()
  local dirs = { vim.env.CANGJIE_HOME }
  if home then
    vim.list_extend(dirs, { vim.fs.joinpath(home, '.cangjie'), vim.fs.joinpath(home, 'cangjie') })
  end
  return dirs
end

--- cjfmt: the one on PATH, else the one in the first SDK found. Nil and why when there is none.
---@return cangjie.cjfmt.Tool?, string?
function M.find()
  local exe = vim.fn.exepath('cjfmt')
  if exe ~= '' then
    return { cmd = exe, home = sdk_home(exe) }
  end
  for _, home in ipairs(sdk_candidates()) do
    local candidate = vim.fs.joinpath(home, 'tools', 'bin', EXE)
    if vim.fn.executable(candidate) == 1 then
      return { cmd = candidate, home = vim.fs.normalize(home) }
    end
  end
  return nil, 'cjfmt is neither on PATH nor in $CANGJIE_HOME, ~/.cangjie or ~/cangjie'
end

--- What cjfmt needs from `envsetup` to run: CANGJIE_HOME, where it reads its default
--- configuration, and the SDK's libraries where the loader looks for them (macOS finds them
--- through the executable's rpath, Windows only through PATH).
---@param home? string
---@return table<string, string>?
function M.env(home)
  if true then -- EXPERIMENT: does cjfmt run without the libraries on the loader's path?
    return nil
  end
  local env = { CANGJIE_HOME = home }
  local libs = { vim.fs.joinpath(home, 'tools', 'lib') }
  for _, lib in ipairs(vim.fn.glob(vim.fs.joinpath(home, 'runtime', 'lib', '*_cjnative'), false, true)) do
    table.insert(libs, vim.fs.normalize(lib))
  end
  if IS_WINDOWS then
    env.PATH = table.concat(libs, ';') .. ';' .. (vim.env.PATH or '')
  elseif vim.fn.has('mac') == 0 then
    env.LD_LIBRARY_PATH = table.concat(libs, ':') .. (vim.env.LD_LIBRARY_PATH and (':' .. vim.env.LD_LIBRARY_PATH) or '')
  end
  return env
end

--- The project's `cangjie-format.toml`: the nearest one above `path`, a file or a directory.
---@param path string
---@return string?
function M.config(path)
  if path == '' then
    return nil
  end
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
  return vim.fs.find(CONFIG, { upward = true, path = dir, type = 'file' })[1]
end

--- The errors in cjfmt's output, `line:col: message` when it gives a place, colours stripped.
---@param output string
---@return string[]
function M.errors(output)
  local lines = vim.split(output:gsub('\27%[[%d;]*m', ''), '\n', { plain = true })
  local errors = {}
  for i, line in ipairs(lines) do
    local message = line:match('^error: (.*)$')
    if message then
      -- rustc's layout: ` ==> file:line:col:` on the next line
      local lnum, col = (lines[i + 1] or ''):match('==>.*:(%d+):(%d+):%s*$')
      table.insert(errors, lnum and (lnum .. ':' .. col .. ': ' .. message) or vim.trim(message))
    end
  end
  return errors
end

--- The text of lines, as a file holds them.
---@param lines string[]
---@param eol boolean whether the last line ends with a newline
function M.text(lines, eol)
  return table.concat(lines, '\n') .. (eol and '\n' or '')
end

--- The lines of a text, a final newline ending the last rather than starting another.
---@param text string
---@return string[]
function M.lines(text)
  local lines = vim.split(text:gsub('\r\n', '\n'), '\n', { plain = true })
  if lines[#lines] == '' then
    table.remove(lines)
  end
  return lines
end

---@class cangjie.cjfmt.Opts
---@field config? string a `cangjie-format.toml`; without one cjfmt takes the SDK's
---@field range? integer[] `{ first, last }`, 1-based and inclusive: only those lines change

--- Formats a text: `on_done(err, text)` once cjfmt exits, or without `on_done` the same two values
--- returned, waiting for it.
---@param text string
---@param opts? cangjie.cjfmt.Opts
---@param on_done? fun(err?: string, text?: string)
---@return string? err, string? text
function M.format(text, opts, on_done)
  opts = opts or {}
  local function finish(err, result)
    if on_done then
      on_done(err, result)
    end
    return err, result
  end

  local tool, missing = M.find()
  if not tool then
    return finish(missing)
  end
  -- run in a directory of its own with relative names: on Windows cjfmt cannot create an output
  -- whose path mixes `\` and `/`, as a temporary directory joined with a name does
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local input, output = 'input.cj', 'output.cj'
  local f = assert(io.open(vim.fs.joinpath(dir, input), 'wb'))
  f:write(text)
  f:close()

  local cmd = { tool.cmd, '-f', input, '-o', output }
  if opts.config then
    vim.list_extend(cmd, { '-c', opts.config })
  end
  if opts.range then
    vim.list_extend(cmd, { '-l', opts.range[1] .. ':' .. opts.range[2] })
  end

  ---@param out vim.SystemCompleted
  local function result(out)
    local errors = M.errors((out.stdout or '') .. '\n' .. (out.stderr or ''))
    local formatted
    if #errors == 0 and out.code == 0 then
      local o = io.open(vim.fs.joinpath(dir, output), 'rb')
      formatted = o and o:read('*a')
      if o then
        o:close()
      end
    end
    vim.fn.delete(dir, 'rf')
    if formatted then
      return nil, formatted
    end
    if #errors == 0 then
      table.insert(errors, out.code == 0 and 'wrote nothing' or ('exited with ' .. out.code))
    end
    return 'cjfmt: ' .. table.concat(errors, '\n')
  end

  local sys_opts = { cwd = dir, text = true, env = M.env(tool.home) }
  if on_done then
    vim.system(cmd, sys_opts, vim.schedule_wrap(function(out)
      finish(result(out))
    end))
    return
  end
  return result(vim.system(cmd, sys_opts):wait(TIMEOUT_MS))
end

--- Replaces a buffer's lines with `lines` by the hunks that differ, so marks, folds and the cursor
--- outside them stay where they were.
---@param bufnr integer
---@param lines string[]
function M.apply(bufnr, lines)
  local old = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local diff = (vim.text and vim.text.diff or vim.diff)(M.text(old, true), M.text(lines, true), {
    result_type = 'indices',
    algorithm = 'histogram',
  })
  ---@cast diff integer[][]
  -- from the end, so the line numbers of the hunks before stay right
  for i = #diff, 1, -1 do
    local old_start, old_count, new_start, new_count = unpack(diff[i])
    -- an insertion comes after `old_start`, a replacement starts at it
    local start = old_count == 0 and old_start or old_start - 1
    vim.api.nvim_buf_set_lines(bufnr, start, start + old_count, false, vim.list_slice(lines, new_start, new_start + new_count - 1))
  end
end

---@class cangjie.cjfmt.BufferOpts
---@field bufnr? integer the current buffer by default
---@field range? integer[] `{ first, last }`, 1-based and inclusive

--- Formats a buffer in place, waiting for cjfmt, with the configuration nearest its file.
---@param opts? cangjie.cjfmt.BufferOpts
---@return string? err
function M.format_buffer(opts)
  opts = opts or {}
  local bufnr = (opts.bufnr == nil or opts.bufnr == 0) and vim.api.nvim_get_current_buf() or opts.bufnr
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local err, text = M.format(M.text(lines, vim.bo[bufnr].eol), {
    config = M.config(name ~= '' and name or vim.fn.getcwd()),
    range = opts.range,
  })
  if err then
    return err
  end
  ---@cast text string
  M.apply(bufnr, M.lines(text))
end

--- `'formatexpr'`: `gq` formats the lines with cjfmt. Typing past `'textwidth'`, or without cjfmt,
--- is left to Neovim's own formatting.
function M.formatexpr()
  if vim.fn.mode():match('^[iR]') or not M.find() then
    return 1
  end
  local first = vim.v.lnum
  local err = M.format_buffer({ range = { first, first + vim.v.count - 1 } })
  if err then
    vim.notify(err, vim.log.levels.ERROR)
  end
  return 0
end

return M
