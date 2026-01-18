local M = {}

function M.setup(opts) 
  local lspconfig = require "lspconfig"
  local configs = require "lspconfig.configs"
  local filetypes = opts.filetypes or { "html" }
  local settings = opts.settings or {}

  if not configs.inline_js_ls then
    configs.inline_js_ls = {
      default_config = {
        cmd = { vim.fn.stdpath("data") .. "/inline-js-ls/js/src/server.js" },
        filetypes = filetypes,
        root_dir = function() return vim.loop.cwd() end,
        settings = settings,
      },
    }
  end

  lspconfig.inline_js_ls.setup({})
end

return M
