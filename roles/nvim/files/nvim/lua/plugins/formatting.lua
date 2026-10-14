return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters = {
        ["google-java-format"] = {
          -- Prepend the --aosp flag to switch from 2 to 4 space indentation
          prepend_args = { "--aosp" },
        },
      },
      formatters_by_ft = {
        java = { "google-java-format" },
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "google-java-format" } },
  },
}
