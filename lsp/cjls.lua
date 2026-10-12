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
  -- the section `cjls` is also what the server starts with, its `initializationOptions` unless
  -- they are set; it asks for the section again once initialized
  before_init = function(params, config)
    local settings = config.settings and config.settings.cjls
    if params.initializationOptions == nil and type(settings) == 'table' and next(settings) ~= nil then
      params.initializationOptions = settings
    end
  end,
}
