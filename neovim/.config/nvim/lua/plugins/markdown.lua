return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      heading = {
        backgrounds = {},
      },
    },
  },
  {
    -- Open the preview (<leader>cp) as a plain Chrome window, without tabs or an address bar,
    -- so it can be tiled next to the terminal. Falls back to the default browser.
    "iamcco/markdown-preview.nvim",
    init = function()
      vim.cmd([[
        function! OpenMarkdownPreview(url)
          if isdirectory('/Applications/Google Chrome.app')
            call jobstart(['open', '-na', 'Google Chrome', '--args', '--app=' . a:url])
          else
            call jobstart(['open', a:url])
          endif
        endfunction
      ]])
      vim.g.mkdp_browserfunc = "OpenMarkdownPreview"
    end,
  },
}
