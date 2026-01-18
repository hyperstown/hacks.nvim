local M = {}

function M.setup(opts)
  for name, mod_opts in pairs(opts) do
    if mod_opts.enabled then
      require("hacks." .. name).setup(mod_opts)
    end
  end
end

return M
