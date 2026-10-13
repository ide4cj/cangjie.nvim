-- Macro expansion through cjls (its `cjls/expandMacro` and `cjls.expandMacro`, cjls's D103): the
-- expansion at the cursor in a scratch buffer, and the files the server writes into the `expanded/`
-- of its directory (cjls's D106), which belong to the server of their source and are not to be
-- edited.
local M = {}

local SUFFIX = '.macrocall'

--- The project directory of the cjls directory `dir`: `<base>` for `<base>/.cache/cjls`, else what
--- its `BASE` names, for one of the user's cache (which has `LAYOUT` beside it); nil for neither.
---@param dir string
---@return string?
local function base_of(dir)
  local base = dir:match('^(.*)/%.cache/cjls$')
  if base then
    return base ~= '' and base or '/'
  end
  if vim.uv.fs_stat(dir .. '/LAYOUT') then
    local file = io.open(dir .. '/BASE', 'rb')
    if file then
      local named = file:read('*a')
      file:close()
      return named ~= '' and vim.fs.normalize(named) or nil
    end
  end
  return nil
end

--- The source file `path` is the expanded file of, as cjls maps it back (its `sourceOfExpanded`):
--- `<cjls dir>/expanded/<path under the project>.macrocall`, the innermost `expanded/` of a cjls
--- directory, else nil.
---@param path string
---@return string?
function M.source_of(path)
  path = vim.fs.normalize(path)
  if not vim.endswith(path, SUFFIX) or vim.fs.basename(path) == SUFFIX then
    return nil
  end
  for dir in vim.fs.parents(path) do
    if vim.fs.basename(dir) == 'expanded' then
      local base = base_of(vim.fs.dirname(dir))
      if base then
        local under = path:sub(#dir + 2, -#SUFFIX - 1)
        return base == '/' and '/' .. under or base .. '/' .. under
      end
    end
  end
  return nil
end

--- Whether `path` is a file the server expanded.
---@param path string
function M.is_expanded(path)
  return M.source_of(path) ~= nil
end

--- Reads the buffer of `uri` again, if it is a loaded expanded file nobody changed: the server has
--- just written it anew.
---@param uri string?
function M.reload(uri)
  if type(uri) ~= 'string' or not vim.startswith(uri, 'file:') then
    return
  end
  local path = vim.uri_to_fname(uri)
  local bufnr = vim.fn.bufnr(path)
  if not M.is_expanded(path) or bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].modified then
    return
  end
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd('silent edit')
  end)
end

--- The expanded file in `bufnr` as the server wrote it: read-only, unmodifiable.
---@param bufnr integer
function M.protect(bufnr)
  vim.bo[bufnr].readonly = true
  vim.bo[bufnr].modifiable = false
end

--- The cjls client of `bufnr` that expands macros, or nil after saying why there is none.
---@param bufnr integer
---@return vim.lsp.Client?
local function client_of(bufnr)
  local client = vim.lsp.get_clients({ name = 'cjls', bufnr = bufnr })[1]
  if not client then
    vim.notify('cjls: not attached to this buffer', vim.log.levels.WARN)
    return nil
  end
  local experimental = client.server_capabilities and client.server_capabilities.experimental
  if type(experimental) ~= 'table' or not experimental.expandMacro then
    vim.notify('cjls: this cjls does not expand macros', vim.log.levels.WARN)
    return nil
  end
  return client
end

--- Asks cjls what the macro call at the cursor of the current window expands to; `on_result(err,
--- result)` gets the answer, `result` nil off a call.
---@param on_result fun(err: lsp.ResponseError?, result: { name: string, expansion: string, kind: string }?)
---@return boolean asked false if there is no cjls expanding macros (said by a notification)
function M.request(on_result)
  local bufnr = vim.api.nvim_get_current_buf()
  local client = client_of(bufnr)
  if not client then
    return false
  end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request('cjls/expandMacro', params, function(err, result)
    on_result(err, result ~= vim.NIL and result or nil)
  end, bufnr)
  return true
end

--- Shows `expansion` in a scratch buffer named `cjls://expand/<name>`, in a split (or the window
--- already showing it), and returns the buffer.
---@param result { name: string, expansion: string }
---@return integer
function M.show(result)
  local name = 'cjls://expand/' .. result.name
  local bufnr = vim.iter(vim.api.nvim_list_bufs()):find(function(b)
    return vim.api.nvim_buf_get_name(b) == name
  end)
  if not bufnr then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, name)
    vim.bo[bufnr].bufhidden = 'wipe'
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result.expansion, '\r?\n'))
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  -- after `buftype`, so no server attaches to a buffer of no file
  vim.bo[bufnr].filetype = 'cangjie'
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    vim.cmd.split()
    vim.api.nvim_win_set_buf(0, bufnr)
  else
    vim.api.nvim_set_current_win(win)
  end
  return bufnr
end

--- `:CjlsExpandMacro`: the expansion of the macro call at the cursor, in a split.
function M.expand()
  M.request(function(err, result)
    if err then
      vim.notify('cjls: ' .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
    elseif not result then
      vim.notify('cjls: no macro expansion here', vim.log.levels.INFO)
    else
      M.show(result)
    end
  end)
end

return M
