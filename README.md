# hacks.nvim

A collection of extremely hacky plugins for Neovim. 
Those plugins were written in a very short time for a sole purpose of solving selected problems. 
Source code can have questionable quality and almost definitely doesn't follow best practices. 
It solved my problem however and it *might* solve yours.

### Hacks list:

| **Hack**     | **Description**                                                                                                |
|--------------|----------------------------------------------------------------------------------------------------------------|
| term         | [NvChad](https://github.com/NvChad/ui) term + tabs                                                             |
| cspell-lang  | Collection of commands that allow easy language installation                                                   |
| inline-js-ls | Supplementary LSP for html-lsp that enables js features in inline (`<script>`) tags. Depends on lspconfig      |
| pdf          | Adds support for viewing PDF documents inside nvim. Depends on [image.nvim](https://github.com/3rd/image.nvim) |
| mouse        | Various mouse utils in case you can't merry just your keyboard                                                 |
| colorify     | [NvChad](https://github.com/NvChad/ui) colorify + color picker (WIP)                                           |


### Installation

Install the plugin with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "hyperstown/hacks.nvim",
  lazy = false,
  opts = {
    -- some plugins require to be enabled
    inline_js_ls = { enabled = true }, -- requires node and npm to be installed
    pdf = { enabled = true },
    mouse = { enabled = true },
    colorify = { enabled = true },
  },
}
```

### Example config

Plugins can be configured through opts.

```lua
{
  "hyperstown/hacks.nvim",
  lazy = false,
  build = function()
    vim.notify("[hacks.nvim] Installing inline-js-ls dependencies…")

    vim.fn.system({
      "npm",
      "install",
      "--silent",
    }, "lua/hacks/inline-js-ls/js")

    vim.notify("[hacks.nvim] inline-js-ls install complete")
  end,
  opts = {
    inline_js_ls = { enabled = true },
    pdf = { enabled = true },
    mouse = { enabled = true },
    colorify = { enabled = true },
  },
  keys = {
    -- Terminal
    { "<leader>th", function() require("hacks.term").new({ pos = "sp" }) end, desc = "Spawn horizontal terminal" },
    { "<leader>tv", function() require("hacks.term").new({ pos = "vsp" }) end, desc = "Spawn vertical terminal" },
    {
      "<leader>,",
      function()
        local enable_neo_tree = true
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].filetype == "neo-tree" then
            enable_neo_tree = false
            break
          end
        end
        require("hacks.term").new({ pos = "sp" })
        require("hacks.term").new({ pos = "vsp" })
        if enable_neo_tree then
          vim.cmd("Neotree show")
        end
      end,
      desc = "Spawn splitted horizontal terminal",
    },
    {
      "<leader>td",
      function()
        local term_buf = vim.api.nvim_get_current_buf()
        -- make sure we are in a terminal
        if vim.bo[term_buf].buftype ~= "terminal" then
          print("Not a terminal buffer!")
          return
        end
        -- Find project root (where manage.py is)
        local manage_py = vim.fn.findfile("manage.py", vim.fn.getcwd() .. "/**")
        if root == "" then
          print("manage.py not found")
          return
        end
        
        local django_dir = vim.fn.fnamemodify(manage_py, ":h")
        -- Send commands to the terminal
        local cmds = {
          "cd " .. django_dir,
          "python manage.py runserver"
        }
        for _, cmd in ipairs(cmds) do
          vim.api.nvim_chan_send(vim.b[term_buf].terminal_job_id, cmd .. "\n")
        end
        -- make sure terminal stays in insert mode
        vim.cmd("startinsert")
        end, 
        desc = "Run django in terminal"
    },
  },
}
```

### Why

For every problem that specific hack solves currently there's no good working solution. \
Some solutions might be incomplete, some might not work at all, some might don't event exist. \
If nobody decided to solve certain problem I'm doing it myself! Unfortunately I always have tight schedule
and I can't put hours of research for every topic. That's why create hacks. A solution that works for me
it might not work for you and does not care about any other than solving one specific problem.


### Graduation

Some of the hacks can graduate from being just hacks and become a proper plugins. \
This can happen when:
1. I find a time to clean up the code, make a proper plugin structure and decide I have time to maintain it.
2. Someone else decides to take a hack and make it a plugin.
3. Someone decides to collaborate with me and co-maintain the plugin.
4. A proper solution appear and make a hack obsolete
