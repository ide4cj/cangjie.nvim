-- The server's settings in README.md and doc/cangjie.txt, from the JSON Schema `cjls --config-schema`
-- prints (cjls's D32, D79): in the README a row per setting between the markers, its type, default
-- and description; in the help file an entry per setting, from the line tagged
-- `*cangjie-settings-list*` to the next section.
--
--   nvim -l scripts/settings.lua <cjls>            # writes README.md and doc/cangjie.txt
--   nvim -l scripts/settings.lua --check <cjls>    # fails when they are not what it would write
--
-- A cjls before its settings had a schema prints none: the check then passes, with a notice.

local BEGIN = '<!-- settings: made by scripts/settings.lua from `cjls --config-schema` -->'
local END = '<!-- /settings -->'
local DOC_TAG = '*cangjie-settings-list*'
local DOC_WIDTH = 78

local check = arg[1] == '--check'
local cjls = check and arg[2] or arg[1]
if not cjls then
  io.stderr:write('usage: nvim -l scripts/settings.lua [--check] <cjls>\n')
  os.exit(2)
end
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(arg[0])))

local run = vim.system({ cjls, '--config-schema' }, { text = true }):wait()
if run.code ~= 0 then
  if (run.stderr or ''):find('no command `--config-schema`', 1, true) then
    io.stdout:write('::notice::' .. cjls .. " prints no settings' schema: README.md and doc/cangjie.txt are not checked against it\n")
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

local function default_of(p)
  return p.default == nil and 'null' or vim.json.encode(p.default)
end

local function description_of(p)
  return ((p.description or ''):gsub('\n', ' '))
end

local function readme_section()
  local rows = { BEGIN, '| `settings.cjls.` | type | default | |', '|---|---|---|---|' }
  for _, key in ipairs(keys) do
    local p = schema.properties[key]
    rows[#rows + 1] = ('| `%s` | %s | `%s` | %s |'):format(key, type_of(p), default_of(p), description_of(p))
  end
  rows[#rows + 1] = END
  return rows
end

-- `text`'s words in lines of at most DOC_WIDTH (a longer word alone), each indented by `indent`
local function wrap(text, indent)
  local lines, line = {}, nil
  for word in text:gmatch('%S+') do
    if line and #line + 1 + #word > DOC_WIDTH then
      lines[#lines + 1] = line
      line = nil
    end
    line = line and (line .. ' ' .. word) or (indent .. word)
  end
  lines[#lines + 1] = line
  return lines
end

local function doc_section()
  local lines = { '' }
  for _, key in ipairs(keys) do
    local p = schema.properties[key]
    local name = 'settings.cjls.' .. key
    local tag = '*cangjie-settings.' .. key .. '*'
    lines[#lines + 1] = name .. string.rep(' ', math.max(1, DOC_WIDTH - #name - #tag)) .. tag
    lines[#lines + 1] = ('    Type: `%s`, default: `%s`'):format(type_of(p), default_of(p))
    vim.list_extend(lines, wrap(description_of(p), '    '))
    lines[#lines + 1] = ''
  end
  return lines
end

--- `lines` with the section between the first line `is_from` holds of and the next one `is_to`
--- holds of replaced by `section`: those two lines too in the README, kept in the help file.
local function replace(lines, name, is_from, is_to, section, inclusive)
  local from, to
  for i, line in ipairs(lines) do
    if not from and is_from(line) then
      from = i
    elseif from and is_to(line) then
      to = i
      break
    end
  end
  assert(from and to, name .. ' has no settings section to write')
  local out = vim.list_extend(vim.list_slice(lines, 1, inclusive and from - 1 or from), section)
  return vim.list_extend(out, vim.list_slice(lines, inclusive and to + 1 or to))
end

local files = {
  ['README.md'] = function(lines)
    return replace(lines, 'README.md', function(l)
      return l == BEGIN
    end, function(l)
      return l == END
    end, readme_section(), true)
  end,
  ['doc/cangjie.txt'] = function(lines)
    return replace(lines, 'doc/cangjie.txt', function(l)
      return l:find(DOC_TAG, 1, true) ~= nil
    end, function(l)
      return vim.startswith(l, '====')
    end, doc_section(), false)
  end,
}

local stale = {}
for _, name in ipairs({ 'README.md', 'doc/cangjie.txt' }) do
  local path = vim.fs.joinpath(root, name)
  local lines = vim.fn.readfile(path)
  local made = files[name](lines)
  if not check then
    vim.fn.writefile(made, path)
  elseif not vim.deep_equal(made, lines) then
    stale[#stale + 1] = name
  end
end
if #stale > 0 then
  io.stdout:write(('::error::the settings in %s are not those of %s: run `nvim -l scripts/settings.lua %s`\n'):format(table.concat(stale, ' and '), cjls, cjls))
  os.exit(1)
end
