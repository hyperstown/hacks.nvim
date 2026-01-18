# PDF Support

A simple PDF support based on [ImageMagick](https://imagemagick.org) 
& [image.nvim](https://github.com/3rd/image.nvim). \
It converts pdf to jpg and then displays it using 
[image.nvim](https://github.com/3rd/image.nvim). \
Currently Image.nvim doesn't support pdf out of the box. Refer to
[this](https://github.com/3rd/image.nvim/issues/338) issue. \
If this issue ever gets resolved remove this snack.

## Example image.nvim config

```lua
return {
  "3rd/image.nvim",
  lazy = false,
  build = false, -- so that it doesn't build the rock https://github.com/3rd/image.nvim/issues/91#issuecomment-2453430239
  opts = {
    backend = "sixel",
    processor = "magick_cli",
    max_width_window_percentage = 95,
    max_height_window_percentage = 95,
    scale_factor = 1.0,
    window_overlap_clear_enabled = false, -- toggles images when windows are overlapped
    window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "snacks_notif", "scrollview", "scrollview_sign" },
    editor_only_render_when_focused = false, 
    hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" }, -- render image files as images when opened
  }
}
```

This should also work with Kitty Graphic Protocol. \
[image.nvim](https://github.com/3rd/image.nvim) can use use other process than [ImageMagick](https://imagemagick.org) but it's still required to be installed globally on the system for this hack to work.
