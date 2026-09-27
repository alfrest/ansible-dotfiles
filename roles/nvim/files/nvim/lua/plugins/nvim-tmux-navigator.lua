return {
  "alexghergh/nvim-tmux-navigation",
  keys = {
    {
      "<M-h>",
      function()
        require("nvim-tmux-navigation").NvimTmuxNavigateLeft()
      end,
      desc = "Navigate Left",
    },
    {
      "<M-j>",
      function()
        require("nvim-tmux-navigation").NvimTmuxNavigateDown()
      end,
      desc = "Navigate Down",
    },
    {
      "<M-k>",
      function()
        require("nvim-tmux-navigation").NvimTmuxNavigateUp()
      end,
      desc = "Navigate Up",
    },
    {
      "<M-l>",
      function()
        require("nvim-tmux-navigation").NvimTmuxNavigateRight()
      end,
      desc = "Navigate Right",
    },
  },
  opts = {
    disable_when_zoomed = true,
  },
}
