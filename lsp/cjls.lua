---@brief
---
--- https://github.com/ide4cj/cjls
---
--- Language server for Cangjie, written in Cangjie. Put the `cjls` binary on your `PATH`
--- (or point `cmd` at it), then:
---
--- ```lua
--- vim.lsp.enable('cjls')
--- ```
---
--- Its settings go under `settings.cjls`
--- (https://github.com/ide4cj/cjls/blob/master/docs/lsp-extensions.md#settings):
---
--- ```lua
--- vim.lsp.config('cjls', { settings = { cjls = { linkedProjects = { '/path/to/project' } } } })
--- ```

---@type vim.lsp.Config
return {
  cmd = { 'cjls' },
  filetypes = { 'cangjie' },
  root_markers = { 'cjpm.toml' },
  -- the nearest `cjpm.toml` (or the `root_markers` one sets); but a file the server expanded,
  -- `<project>/.cache/cjls/expanded/<path>.macrocall`, belongs to the server of its source, which
  -- wrote it and answers hover and definition in it
  root_dir = function(bufnr, on_dir)
    local source = require('cangjie.expand').source_of(vim.api.nvim_buf_get_name(bufnr))
    local config = vim.lsp.config.cjls
    on_dir(vim.fs.root(source or bufnr, config and config.root_markers or { 'cjpm.toml' }))
  end,
  handlers = {
    -- a file the server expanded again is shown as written now, not as a buffer last read it
    ['window/showDocument'] = function(err, params, ctx)
      require('cangjie.expand').reload(params and params.uri)
      return vim.lsp.handlers['window/showDocument'](err, params, ctx)
    end,
  },
  -- the section `cjls` is also what the server starts with, its `initializationOptions` unless
  -- they are set; it asks for the section again once initialized
  before_init = function(params, config)
    local settings = config.settings and config.settings.cjls
    if params.initializationOptions == nil and type(settings) == 'table' and next(settings) ~= nil then
      params.initializationOptions = settings
    end
  end,
}
