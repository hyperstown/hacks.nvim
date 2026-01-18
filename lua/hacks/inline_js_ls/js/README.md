# inline-js-lsp

Supplementary LSP that extracts the first `<script>` section from HTML files and forwards TypeScript/JavaScript requests to `typescript-language-server`.

### Quick start:

1. Install dependencies:

```bash
cd inline-js-lsp
npm install
```

2. Start the server as the LSP command for your editor. Example nvim `lspconfig` snippet:

```lua
require('lspconfig').inline_js_ls = {
  default_config = {
    cmd = { 'node', '/path/to/inline-js-lsp/src/server.js' },
    filetypes = { 'html' },
    root_dir = function() return vim.loop.cwd() end,
  }
}
require('lspconfig').inline_js_ls.setup({})
```

What it does

- When the editor opens or changes an HTML document, the server extracts the first `<script>` content and opens a virtual `__inline.ts` document with `typescript-language-server`.
- Requests for positions outside the script are ignored (the server returns empty results), while requests inside the script are proxied to the TS server and mapped back.
