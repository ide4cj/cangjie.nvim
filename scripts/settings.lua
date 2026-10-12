-- The server's settings in README.md, from the JSON Schema `cjls --config-schema` prints (cjls's
-- D32, D79): a row per setting between the markers, its type, default and description.
--
--   nvim -l scripts/settings.lua <cjls>            # writes README.md
--   nvim -l scripts/settings.lua --check <cjls>    # fails when README.md is not what it would write
--
-- A cjls before its settings had a schema prints none: the check then passes, with a notice.

local BEGIN = '<!-- settings: made by scripts/settings.lua from `cjls --config-schema` -->'
local END = '<!-- /settings -->'

local check = arg[1] == '--check'
local cjls = check and arg[2] or arg[1]
if not cjls then
  io.stderr:write('usage: nvim -l scripts/settings.lua [--check] <cjls>\n')
  os.exit(2)
end
local readme = vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(arg[0]))), 'README.md')

local run = vim.system({ cjls, '--config-schema' }, { text = true }):wait()
if run.code ~= 0 then
  if (run.stderr or ''):find('no command `--config-schema`', 1, true) then
    io.stdout:write('::notice::' .. cjls .. " prints no settings' schema: README.md is not checked against it\n")
    os.exit(0)
  end
  io.stderr:write(cjls .. ' --config-schema failed: ' .. (run.stderr or '') .. '\n')
  os.exit(1)
end
-- the members in the order the server prints them, which a Lua table forgets
local text = run.stdout
local schema = vim.json.decode(text, { luanil = { object = true } })
local keys = {}
for key in pairs(schema.properties) do
  keys[#keys + 1] = key
end
local properties = text:sub((text:find('"properties"', 1, true)))
table.sort(keys, function(a, b)
  return properties:find('"' .. a .. '"', 1, true) < properties:find('"' .. b .. '"', 1, true)
end)

local function type_of(p)
  local types = type(p.type) == 'table' and p.type or { p.type }
  local shown = vim.tbl_map(function(t)
    return t == 'array' and p.items and (p.items.type .. '[]') or t
  end, types)
  return table.concat(shown, ' or ')
end

local rows = { BEGIN, '| `settings.cjls.` | type | default | |', '|---|---|---|---|' }
for _, key in ipairs(keys) do
  local p = schema.properties[key]
  local default = p.default == nil and 'null' or vim.json.encode(p.default)
  rows[#rows + 1] = ('| `%s` | %s | `%s` | %s |'):format(key, type_of(p), default, (p.description or ''):gsub('\n', ' '))
end
rows[#rows + 1] = END

local lines = vim.fn.readfile(readme)
local from, to
for i, line in ipairs(lines) do
  if line == BEGIN then
    from = i
  elseif line == END then
    to = i
  end
end
assert(from and to and from < to, 'README.md has no ' .. BEGIN .. ' … ' .. END)
local made = vim.list_extend(vim.list_slice(lines, 1, from - 1), rows)
made = vim.list_extend(made, vim.list_slice(lines, to + 1))

if not check then
  vim.fn.writefile(made, readme)
elseif not vim.deep_equal(made, lines) then
  io.stdout:write("::error::README.md's settings are not those of " .. cjls .. ': run `nvim -l scripts/settings.lua ' .. cjls .. '`\n')
  os.exit(1)
end
