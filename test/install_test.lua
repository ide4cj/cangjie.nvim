-- The installer, against a release in a directory, packaged as cjls's release.yml does it:
-- `cjls-<target>/cjls` in an archive, and SHA256SUMS.
local t = require('t')
local install = require('cangjie.install')

--- A release `version` under `<dir>/download`, of `exe` (any file: the installer does not run it).
local function release(dir, version, exe)
  local asset = assert(install.asset())
  local pkg = dir .. '/pkg/' .. asset.dir
  local out = dir .. '/download/' .. version
  vim.fn.mkdir(pkg, 'p')
  vim.fn.mkdir(out, 'p')
  if exe then
    assert(vim.uv.fs_copyfile(exe, pkg .. '/' .. asset.exe))
  else
    vim.fn.writefile({ 'cjls' }, pkg .. '/' .. asset.exe)
  end
  local pack = asset.archive:match('%.zip$') and { install.tar(), '-a', '-cf' } or { install.tar(), '-czf' }
  local packed = vim.system(vim.list_extend(pack, { out .. '/' .. asset.archive, '-C', dir .. '/pkg', asset.dir })):wait()
  assert(packed.code == 0, 'could not pack the release: ' .. (packed.stderr or ''))
  local f = assert(io.open(out .. '/' .. asset.archive, 'rb'))
  vim.fn.writefile({ vim.fn.sha256(f:read('*a')) .. '  ' .. asset.archive }, out .. '/SHA256SUMS')
  f:close()
  return 'file://' .. (dir:sub(1, 1) == '/' and '' or '/') .. dir
end

local function run_install(opts)
  local result
  opts.on_done = function(err)
    result = err or false
  end
  install.install(opts)
  t.wait('the installer did not finish', function()
    return result ~= nil
  end)
  return result or nil
end

return {
  ['a release is unpacked, executable, with its version'] = function()
    -- arrange
    local asset, why = install.asset()
    if not asset then
      t.skip(why)
    end
    local dir = t.tempdir()
    local exe = vim.env.CJLS_BIN and (vim.uv.fs_stat(vim.env.CJLS_BIN) and vim.env.CJLS_BIN or (vim.env.CJLS_BIN .. '.exe'))
    local base = release(dir, 'v0.0.0', exe)

    -- act
    local err = run_install({ version = 'v0.0.0', base = base, dir = dir .. '/data' })

    -- assert
    t.eq(nil, err, 'error')
    t.eq(1, vim.fn.executable(dir .. '/data/bin/' .. asset.exe), 'executable')
    t.eq('v0.0.0', install.installed(dir .. '/data'), 'installed')
    vim.fn.delete(dir, 'rf')
  end,

  ['an archive that does not match SHA256SUMS is refused'] = function()
    -- arrange
    local asset, why = install.asset()
    if not asset then
      t.skip(why)
    end
    local dir = t.tempdir()
    local base = release(dir, 'v0.0.0')
    vim.fn.writefile({ string.rep('0', 64) .. '  ' .. asset.archive }, dir .. '/download/v0.0.0/SHA256SUMS')

    -- act
    local err = run_install({ version = 'v0.0.0', base = base, dir = dir .. '/data' })

    -- assert
    assert(err and err:match('SHA256SUMS'), 'expected a checksum error, got ' .. tostring(err))
    t.eq(nil, install.installed(dir .. '/data'), 'installed')
    vim.fn.delete(dir, 'rf')
  end,
}
