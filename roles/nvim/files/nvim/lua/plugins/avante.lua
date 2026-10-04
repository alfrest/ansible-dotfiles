return {
  "yetone/avante.nvim",
  opts = {
    provider = "gemini",
    providers = {
      gemini = {
        endpoint = "https://generativelanguage.googleapis.com/v1beta/models",
        model = "gemini-3.5-flash",
        timeout = 30000,
        context_window = 1048576, -- 1M+ tokens
        extra_request_body = {
          generationConfig = {
            temperature = 0.75,
          },
        },
      },
    },
  },
}
