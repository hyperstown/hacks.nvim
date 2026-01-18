local image = require("image")

-- Attach image lifetime to buffer (only once)
local function attach_image_lifecycle(buf, img)
  if vim.b[buf].image_lifecycle_attached then return end

  vim.b[buf].image_lifecycle_attached = true

  vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout", "BufUnload" }, {
    buffer = buf,
    callback = function()
      if img then img:clear() end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = buf,
    callback = function()
      if img then img:render() end
    end,
  })
end

function M.setup()
  vim.api.nvim_create_autocmd("BufReadPost", {
    pattern = "*.pdf",
    callback = function(args)
      local buf = args.buf
      local win = vim.api.nvim_get_current_win()
      local png = vim.fn.tempname() .. ".jpg"

      vim.fn.system {
        "magick",
        "-density",
        "150",
        args.file .. "[0]",
        png,
      }

      vim.bo[buf].swapfile = false
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].filetype = "image"
      vim.bo[buf].modifiable = true
      vim.bo[buf].readonly = false

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = "no"
      vim.wo[win].cursorline = false

      image.clear()

      local img = image.from_file(png, {
        window = win,
        inline = true,
      })
      if not img then return end

      img:render()

      vim.b[buf].pdf_img = img

      -- Lock buffer
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].modifiable = false
          vim.bo[buf].readonly = true
        end
      end)

      attach_image_lifecycle(buf, img)
    end,
  })
end

