return {
  "yetone/avante.nvim",
  opts = {
    provider = "gemini",
    providers = {
      groq = {
        __inherited_from = "openai",
        endpoint = "https://api.groq.com/openai/v1",
        model = "qwen/qwen3.8-27b",
        api_key_name = "GROQ_API_KEY",
      },
    },
  },
}
