local M = {}

local function plugin_root()
  local source = debug.getinfo(1, "S").source
  local file = source:sub(2)
  return vim.fn.fnamemodify(file, ":p:h:h:h")
end

function M.setup(opts)
  local lspconfig = require("lspconfig")
  local configs = require("lspconfig.configs")

  local filetypes = opts.filetypes or { "html" }
  local settings = opts.settings or {}

  if not configs.inline_js_ls then
    configs.inline_js_ls = {
      default_config = {
        cmd = {
          "node",
          plugin_root() .. "/hacks/inline_js_ls/js/src/server.js",
        },
        filetypes = filetypes,
        root_dir = function()
          return vim.loop.cwd()
        end,
        settings = settings,
      },
    }
  end

  lspconfig.inline_js_ls.setup({})
end

return M
