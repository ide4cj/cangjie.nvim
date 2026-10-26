-- Roots belong to a server session; buffer options belong to the buffer, which may outlive it.
local M = {}
local roots_by_client = {}
local protected = {}

local function path(name)
  local normalized = vim.fs.normalize(name):gsub('\\', '/'):gsub('/+$', '')
  return vim.fn.has('win32') == 1 and normalized:lower() or normalized
end

local function covered(name)
  name = path(name)
  for _, roots in pairs(roots_by_client) do
    for _, root in ipairs(roots) do
      if name == root or vim.startswith(name, root .. '/') then
        return true
      end
    end
  end
  return false
end

function M.apply(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    protected[buf] = nil
    return
  end
  local options = vim.bo[buf]
  if covered(vim.api.nvim_buf_get_name(buf)) then
    if not protected[buf] then
      protected[buf] = { readonly = options.readonly, modifiable = options.modifiable }
      options.readonly = true
      options.modifiable = false
    end
  elseif protected[buf] then
    local previous = protected[buf]
    protected[buf] = nil
    -- Leave an explicit user override alone.
    if options.readonly then options.readonly = previous.readonly end
    if not options.modifiable then options.modifiable = previous.modifiable end
  end
end

local function apply_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do M.apply(buf) end
end

function M.handler(err, params, ctx)
  if err then return end
  local roots = {}
  for _, uri in ipairs(params.roots) do
    if vim.startswith(uri, 'file:') then
      roots[#roots + 1] = path(vim.uri_to_fname(uri))
    end
  end
  roots_by_client[ctx.client_id] = roots
  apply_all()
end

function M.clear(client_id)
  roots_by_client[client_id] = nil
  apply_all()
end

local group = vim.api.nvim_create_augroup('cjls.binary_sources', {})
vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter', 'BufFilePost' }, {
  group = group,
  callback = function(args) M.apply(args.buf) end,
})
vim.api.nvim_create_autocmd('BufWipeout', {
  group = group,
  callback = function(args) protected[args.buf] = nil end,
})

return M
