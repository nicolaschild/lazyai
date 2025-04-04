# Lazy AI

AI assistant plugin for your lazy-vim workflow.

`Author`: Nicolas Child

https://github.com/user-attachments/assets/0473ec5f-1a6b-40bd-98b9-cae57b55f4e6

## Upcoming Features

- [ ] Context window(s) and another buffer to select between chats
- [ ] A CLI build with Golang

## Buffer Features

- Stream Status buffer
  - Loading animation when stream active
- Readonly response buffer
  - Markdown support
  - HTTP Streaming
- Input buffer
  - Input buffer clear on first insert

## Installation

1. Create the following `lazyai.lua` file in your nvim plugins folder:

```lua
return {
  "nicolaschild/lazyai",
  name = "lazyai",
  keys = {
    {
      "<space>0",
      function()
        require("lazyai").open()
      end,
      desc = "Open LazyAi",
    },
  },
}
```

Or you can simply clone this repository and set it up yourself

## Configuration

### OpenAI API Key Setup

1. Get your OpenAI API key from [OpenAI's website](https://platform.openai.com/api-keys)
2. Export your API key in your environment:

```bash
export OPENAI_API_KEY='your-api-key-here'
```

For Windows users, use:

```cmd
set OPENAI_API_KEY=your-api-key-here
```

## Usage

1. Press `<space>0` to open the content window
2. Type your question or request
3. Get AI-powered assistance instantly

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
