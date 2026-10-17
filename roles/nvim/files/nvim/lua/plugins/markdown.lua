-- Markdown files are linted by markdownlint-cli2 through nvim-lint, not by the marksman LSP.
-- Rule MD013 (line-length) defaults to 80 columns, has no `--fix` (so neither markdownlint nor
-- prettier can clear it on save), and used to flag practically every prose line.
--
-- `.markdownlint.jsonc` next to this config's init.lua turns MD013 off and nothing else. Two
-- things to keep in mind when editing it:
--   * markdownlint only auto-discovers configs from the linted file's directory upward (plus
--     cwd), so a config sitting next to init.lua has to be passed with `--config`.
--   * markdownlint-cli2 silently ignores a config file that contains any comment, so keep it
--     plain JSON and document it here.
return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          prepend_args = { "--config", vim.fn.stdpath("config") .. "/.markdownlint.jsonc" },
        },
      },
    },
  },
}
