# Term

A simple terminal based on excellent 
[nvchad terminal](https://github.com/NvChad/ui/blob/v3.0/lua/nvchad/term/init.lua) 
with added tabs support.

## Installation

Term config
```lua
["<Leader>,"] = { 
    function()
    local enable_neo_tree = true
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "neo-tree" then
        enable_neo_tree = false
        break
        end
    end
    require("nvchad.term").new { pos = "sp" }
    require("nvchad.term").new { pos = "vsp" }
    if enable_neo_tree then
        vim.cmd("Neotree show")
    end
    end, 
    desc = "Spawn splitted horizontal terminal" 
},
```

## Why

While I was looking for a perfect integrated terminal for NeoVim 
I noticed that almost all terminals while opened take entire width of the NeoVim.
You also can't put them anywhere you want and for me floating window isn't an answer. 
Only one terminal that behaved like I wanted was NvChad term.
Another issue was that I also found only one terminal that supported tabs.

