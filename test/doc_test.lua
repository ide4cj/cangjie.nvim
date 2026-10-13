-- `:help cangjie`: its tags made without an error, its links to tags that are there, its settings
-- the README's.
local t = require('t')

local DOC = t.root .. '/doc/cangjie.txt'

-- the help file's tags, made by `:helptags` in a directory of their own, not beside the file
local function tags()
  local dir = t.tempdir()
  vim.fn.writefile(vim.fn.readfile(DOC, 'b'), dir .. '/cangjie.txt', 'b')
  vim.cmd.helptags(vim.fn.fnameescape(dir))
  local names = {}
  for _, line in ipairs(vim.fn.readfile(dir .. '/tags')) do
    names[line:match('^[^\t]+')] = true
  end
  return names
end

return {
  ['the help tags are made without an error'] = function()
    -- act
    local ok, err = pcall(tags)

    -- assert
    assert(ok, err)
  end,

  ['every link in the help is to a tag of its own or of Neovim'] = function()
    -- arrange
    local own = tags()

    -- act
    local missing = {}
    for _, line in ipairs(vim.fn.readfile(DOC)) do
      -- a link outside a code span: `|...|` in backticks is code
      for link in line:gsub('`[^`]*`', ''):gmatch('|([^|%s]+)|') do
        if not own[link] and not vim.tbl_contains(vim.fn.getcompletion(link, 'help'), link) then
          missing[#missing + 1] = link
        end
      end
    end

    -- assert
    t.eq({}, missing, 'links to no tag')
  end,

  ['the help lists the settings the README does'] = function()
    -- arrange
    local readme, help = {}, {}
    for _, line in ipairs(vim.fn.readfile(t.root .. '/README.md')) do
      readme[#readme + 1] = line:match('^| `(%w+)` |')
    end
    for _, line in ipairs(vim.fn.readfile(DOC)) do
      help[#help + 1] = line:match('^settings%.cjls%.(%w+)%s+%*cangjie%-settings%.%w+%*$')
    end

    -- assert
    assert(#readme > 0, 'README.md lists no settings')
    t.eq(readme, help)
  end,
}
