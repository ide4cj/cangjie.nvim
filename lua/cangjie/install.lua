-- The cjls binary, downloaded from its GitHub release: the archive cjls's `release.yml` publishes
-- for this platform, checked against the release's SHA256SUMS, unpacked into
-- `stdpath('data')/cjls/bin`.

local M = {}

local RELEASES = 'https://github.com/ide4cj/cjls/releases'

-- The cjls release this plugin is tested with and downloads; Renovate moves it after each release
-- (renovate.json). Nil would mean the latest.
local CJLS_VERSION = 'v0.4.0'
local IS_WINDOWS = vim.fn.has('win32') == 1
local EXE = IS_WINDOWS and 'cjls.exe' or 'cjls'

-- The targets release.yml packages, by `vim.uv.os_uname()`
local TARGETS = {
  Darwin = { arm64 = { 'aarch64-apple-darwin', 'tar.gz' } },
  Linux = { x86_64 = { 'x86_64-unknown-linux-gnu', 'tar.gz' } },
  Windows_NT = { x86_64 = { 'x86_64-pc-windows-gnu', 'zip' } },
}

--- The tar to unpack with: on Windows the bsdtar it ships, which reads zip, rather than a GNU tar
--- a Git Bash may put first on PATH, which reads neither zip nor `C:` paths.
function M.tar()
  local system = IS_WINDOWS and vim.env.SystemRoot and vim.fs.joinpath(vim.env.SystemRoot, 'System32', 'tar.exe')
  return system and vim.uv.fs_stat(system) and system or 'tar'
end

--- Where the downloaded binary lives, whether or not it is there.
function M.dir()
  return vim.fs.joinpath(vim.fn.stdpath('data'), 'cjls')
end

function M.bin_dir()
  return vim.fs.joinpath(M.dir(), 'bin')
end

--- The release installed in `dir`, or nil.
function M.installed(dir)
  local f = io.open(vim.fs.joinpath(dir or M.dir(), 'version'), 'r')
  if not f then
    return nil
  end
  local version = f:read('*l')
  f:close()
  return version
end

--- The release to download: `vim.g.cjls_version` if set, else the one this plugin pins. Nil means
--- the latest.
function M.wanted()
  return vim.g.cjls_version or CJLS_VERSION
end

--- The target and archive format of this platform, or nil and why not.
function M.target()
  local uname = vim.uv.os_uname()
  local machine = uname.machine == 'aarch64' and 'arm64' or uname.machine
  local target = (TARGETS[uname.sysname] or {})[machine == 'AMD64' and 'x86_64' or machine]
  if not target then
    return nil, 'there is no prebuilt cjls for ' .. uname.sysname .. ' ' .. uname.machine .. '; build it from source and put it on PATH'
  end
  return target[1], target[2]
end

---@class cangjie.install.Asset
---@field archive string the file release.yml attaches to a release, `cjls-<target>.<format>`
---@field dir string the directory in it, `cjls-<target>`
---@field exe string the binary in that directory

--- What this platform downloads from a release, or nil and why not.
---@return cangjie.install.Asset?, string?
function M.asset()
  local target, format = M.target()
  if not target then
    return nil, format
  end
  local dir = 'cjls-' .. target
  return { archive = dir .. '.' .. format, dir = dir, exe = EXE }
end

-- Runs the steps one after another on the main loop, a command or a function, then `done(err)`.
local function run(steps, done)
  local function step(i)
    if i > #steps then
      return done(nil)
    end
    local s = steps[i]
    if type(s) == 'function' then
      local ok, err = pcall(s)
      if not ok then
        return done(tostring(err))
      end
      return step(i + 1)
    end
    vim.system(s, { text = true }, vim.schedule_wrap(function(out)
      if out.code ~= 0 then
        return done((s.what or (table.concat(s, ' ') .. ' failed')) .. ': ' .. vim.trim(out.stderr or ''))
      end
      step(i + 1)
    end))
  end
  step(1)
end

local function read_bytes(path)
  local f = assert(io.open(path, 'rb'))
  local data = f:read('*a')
  f:close()
  return data
end

--- Downloads and installs the release asynchronously.
---@param opts? { version?: string, on_done?: fun(err?: string), base?: string, dir?: string }
--- `version` defaults to `wanted()`, `base` to the GitHub releases and `dir` to `dir()`.
function M.install(opts)
  opts = opts or {}
  local done = opts.on_done or function(err)
    if err then
      vim.notify('cjls: ' .. err, vim.log.levels.ERROR)
    end
  end
  local asset, why = M.asset()
  if not asset then
    return done(why)
  end
  local version = opts.version or M.wanted()
  local base = opts.base or RELEASES
  local url = version and (base .. '/download/' .. version) or (base .. '/latest/download')
  local dir = opts.dir or M.dir()
  local archive_name = asset.archive

  -- downloaded and unpacked under `dir`, not in Neovim's temporary directory: the binary is moved
  -- into `bin` by a rename, which cannot cross filesystems (EXDEV), and `/tmp` is often a tmpfs
  -- and `%TEMP%` on another drive. Removed once done, whichever way.
  local tmp = vim.fs.joinpath(dir, string.format('.download-%d-%x', vim.uv.getpid(), vim.uv.hrtime()))
  vim.fn.mkdir(tmp, 'p')
  local function finish(err)
    vim.fn.delete(tmp, 'rf')
    done(err)
  end
  local archive = vim.fs.joinpath(tmp, archive_name)
  local sums = vim.fs.joinpath(tmp, 'SHA256SUMS')
  local function curl(from, to)
    return { 'curl', '--fail', '--silent', '--show-error', '--location', '--retry', '2', '--output', to, from, what = 'could not download ' .. from }
  end

  run({
    curl(url .. '/' .. archive_name, archive),
    curl(url .. '/SHA256SUMS', sums),
    function()
      local expected = read_bytes(sums):match('(%x+)%s+%*?' .. vim.pesc(archive_name))
      local actual = vim.fn.sha256(read_bytes(archive))
      assert(expected, archive_name .. ' is not in SHA256SUMS')
      assert(expected:lower() == actual, archive_name .. ' does not match its SHA256SUMS entry')
    end,
    { M.tar(), '-xf', archive, '-C', tmp },
    function()
      local bin_dir = vim.fs.joinpath(dir, 'bin')
      vim.fn.mkdir(bin_dir, 'p')
      local bin = vim.fs.joinpath(bin_dir, EXE)
      -- a running binary can be renamed away, not overwritten, on Windows
      pcall(vim.uv.fs_unlink, bin .. '.old')
      if vim.uv.fs_stat(bin) then
        assert(vim.uv.fs_rename(bin, bin .. '.old'))
      end
      assert(vim.uv.fs_rename(vim.fs.joinpath(tmp, asset.dir, EXE), bin))
      pcall(vim.uv.fs_unlink, bin .. '.old')
      if not IS_WINDOWS then
        assert(vim.uv.fs_chmod(bin, tonumber('755', 8)))
      end
      local f = assert(io.open(vim.fs.joinpath(dir, 'version'), 'w'))
      f:write((version or 'latest') .. '\n')
      f:close()
    end,
  }, finish)
end

return M
