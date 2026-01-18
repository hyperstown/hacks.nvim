local M = {}
local api = vim.api

local state = require("hacks.colorify.state")
state.ns = api.nvim_create_namespace("Colorify")

M.options = {
  mode = "virtual", -- fg, bg, virtual
  virt_text = "󱓻 ",
  highlight = { hex = true, lspvars = true },
}

function M.setup(opts)

  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
  M.attach = require("hacks.colorify.attach")
  
  api.nvim_create_autocmd({
    "TextChanged",
    "TextChangedI",
    "TextChangedP",
    "VimResized",
    "LspAttach",
    "WinScrolled",
    "BufEnter",
  }, {
    callback = function(args)
      if vim.bo[args.buf].bl then
        M.attach(args.buf, args.event)
      end
    end,
  })
end

return M
