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

---@type vim.lsp.Config
return {
  cmd = { 'cjls' },
  filetypes = { 'cangjie' },
  root_markers = { 'cjpm.toml' },
}
