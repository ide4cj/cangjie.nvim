-- What the tests share: assertions, temporary files and buffers, the environment put back.
local t = {}

t.root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p'))))
t.fixture = t.root .. '/test/fixture'
-- a request's timeout that never comes: a hang is the CI job's to end (#19)
t.FOREVER_MS = 2147483647
-- how often a wait says what it waits for
t.NOTICE_MS = 10000
t.IS_WINDOWS = vim.fn.has('win32') == 1

function t.eq(expected, actual, what)
  if not vim.deep_equal(expected, actual) then
    error((what and (what .. ': ') or '') .. 'expected ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(actual), 2)
  end
end

function t.skip(why)
  error({ skip = why }, 0)
end

--- Waits until `cond` holds, as long as it takes: a deadline fails a slow runner whose answer was
--- coming (#19), and a hang is the CI job's timeout to end. Every `t.NOTICE_MS` it says what it
--- waits for, so the log of a job killed names it.
function t.wait(what, cond)
  local waited = 0
  while not vim.wait(t.NOTICE_MS, cond) do
    waited = waited + t.NOTICE_MS
    io.stdout:write(string.format('wait %s: %s, %d s so far\n', t.case or '?', what, waited / 1000))
    io.stdout:flush()
  end
end

--- A new empty directory, `/`-separated as Neovim reports paths.
function t.tempdir()
  local dir = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(dir, 'p')
  return dir
end

--- Writes a file, its directories included, and returns its path.
function t.write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(lines, path)
  return path
end

--- The current buffer holding `lines` as a Cangjie file, named `name` if given.
function t.buffer(lines, name)
  vim.cmd.enew()
  if name then
    vim.api.nvim_buf_set_name(0, name)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = 'cangjie'
  return vim.api.nvim_get_current_buf()
end

function t.lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr or 0, 0, -1, false)
end

--- Runs `fn` with the environment variables in `vars` set (`vim.NIL` unsets one), then puts them
--- back.
function t.with_env(vars, fn)
  local saved = {}
  for k, v in pairs(vars) do
    saved[k] = vim.env[k] or vim.NIL
    vim.env[k] = v ~= vim.NIL and v or nil
  end
  local ok, err = pcall(fn)
  for k, v in pairs(saved) do
    vim.env[k] = v ~= vim.NIL and v or nil
  end
  if not ok then
    error(err, 0)
  end
end

return t
