-- cjfmt for conform.nvim, which looks its formatters up as `conform.formatters.<name>`: with this
-- plugin installed, `formatters_by_ft = { cangjie = { 'cjfmt' } }` is all it takes.
local cjfmt = require('cangjie.cjfmt')

---@type conform.FileLuaFormatterConfig
return {
  meta = {
    url = 'https://gitcode.com/Cangjie/cangjie_tools/tree/main/cjfmt',
    description = 'The formatter the Cangjie SDK ships, found on PATH or in $CANGJIE_HOME (cangjie.nvim).',
  },
  condition = function()
    return cjfmt.find() ~= nil
  end,
  format = function(_, ctx, lines, callback)
    cjfmt.format(cjfmt.text(lines, vim.bo[ctx.buf].eol), {
      config = cjfmt.config(ctx.filename ~= '' and ctx.filename or vim.fn.getcwd()),
      range = ctx.range and { ctx.range.start[1], ctx.range['end'][1] },
    }, function(err, text)
      callback(err, text and cjfmt.lines(text))
    end)
  end,
}
