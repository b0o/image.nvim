local utils = require("image/utils")
local image = require("image/image")

---@type Options
local default_options = {
  backend = "ueberzug",
  -- backend = "kitty",
  integrations = {
    markdown = {
      enabled = true,
      sizing_strategy = "auto",
    },
  },
  max_width = nil,
  max_height = nil,
  max_width_window_percentage = nil,
  max_height_window_percentage = 50,
}

---@type State
local state = {
  ---@diagnostic disable-next-line: assign-type-mismatch
  backend = nil,
  options = default_options,
  images = {},
  extmarks_namespace = nil,
}

---@type API
local api = {}

---@param options Options
api.setup = function(options)
  local opts = vim.tbl_deep_extend("force", default_options, options or {})
  state.options = opts

  -- load backend
  local ok, backend = pcall(require, "image/backends/" .. opts.backend)
  if not ok then
    utils.throw("render: failed to load " .. opts.backend .. " backend")
    return
  end
  if type(backend.setup) == "function" then backend.setup(state) end
  state.backend = backend

  -- load integrations
  for name, integration_options in pairs(opts.integrations) do
    if integration_options.enabled then
      local integration_ok, integration = pcall(require, "image/integrations." .. name)
      if not integration_ok then utils.throw("render: failed to load " .. name .. " integration") end
      if type(integration.setup) == "function" then integration.setup(api, integration_options) end
    end
  end

  -- setup namespaces
  state.extmarks_namespace = vim.api.nvim_create_namespace("image.nvim")
  vim.api.nvim_set_decoration_provider(state.extmarks_namespace, {
    -- on_win = function(_, _, buf, top, bot)
    --   vim.schedule(function()
    --     hologram.buf_render_images(buf, top, bot)
    --   end)
    -- end,
  })

  -- setup autocommands
  local group = vim.api.nvim_create_augroup("image.nvim", { clear = true })

  -- auto-clear on buffer change
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function()
      local windows = utils.window.get_visible_windows()
      local win_buf_map = {}
      for _, window in ipairs(windows) do
        win_buf_map[window.id] = window.buffer
      end

      local images = api.get_images()
      for _, current_image in ipairs(images) do
        local is_window_bound = type(current_image.window) == "number"
        local is_window_binding_valid = win_buf_map[current_image.window] ~= nil
        local is_buffer_bound = type(current_image.buffer) == "number"
        local is_buffer_binding_valid = win_buf_map[current_image.window] == current_image.buffer

        local should_clear = false
        if is_window_bound and not is_window_binding_valid then
          should_clear = true
        elseif is_buffer_bound and not is_buffer_binding_valid then
          should_clear = true
        end
        if should_clear then current_image.clear() end
      end
    end,
  })

  -- auto-clear on window close
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(au) -- auto-clear images when windows and buffers change
      local images = api.get_images({ window = tonumber(au.file) })
      for _, current_image in ipairs(images) do
        current_image.clear()
      end
    end,
  })
end

---@param path string
---@param options? ImageOptions
api.from_file = function(path, options)
  return image.from_file(path, options, state)
end

---@param id? string
api.clear = function(id)
  local target = state.images[id]
  if target then
    target.clear()
  else
    state.backend.clear(id)
  end
end

---@param opts? { window?: number, buffer?: number }
---@return Image[]
api.get_images = function(opts)
  local images = {}
  for _, current_image in pairs(state.images) do
    if
      (opts and opts.window and opts.window == current_image.window and not opts.buffer)
      or (opts and opts.window and opts.window == current_image.window and opts.buffer and opts.buffer == current_image.buffer)
      or not opts
    then
      table.insert(images, current_image)
    end
  end
  return images
end

return api