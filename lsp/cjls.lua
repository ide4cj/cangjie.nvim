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
	cmd = { "cjls" },
	filetypes = { "cangjie" },
	root_markers = { "cjpm.toml", "cj-project.json", ".git" },
	on_exit = function(_, _, client_id)
		vim.schedule(function()
			require("cangjie.binary_sources").clear(client_id)
		end)
	end,
	-- the nearest `cjpm.toml` or `cj-project.json` (or the `root_markers` one sets).
	-- for *.cj.macrocall file tries to restore an original *.cj file and search from there.
	root_dir = function(bufnr, on_dir)
		local source = require("cangjie.expand").source_of(vim.api.nvim_buf_get_name(bufnr))
		local config = vim.lsp.config.cjls
		on_dir(
			vim.fs.root(source or bufnr, config and config.root_markers or { "cjpm.toml", "cj-project.json", ".git" })
		)
	end,
	handlers = {
		["cjls/binarySourceRoots"] = require("cangjie.binary_sources").handler,
		-- reload expansions
		["window/showDocument"] = function(err, params, ctx)
			require("cangjie.expand").reload(params and params.uri)
			return vim.lsp.handlers["window/showDocument"](err, params, ctx)
		end,
	},
	before_init = function(params, config)
		local settings = config.settings and config.settings.cjls
		if params.initializationOptions == nil and type(settings) == "table" and next(settings) ~= nil then
			params.initializationOptions = settings
		end
	end,
}
