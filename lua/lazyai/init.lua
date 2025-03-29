-- TODO: Code organization
-- TODO: Create context window(s)

local config = require("lazyai.config")

-- Simplified JSON decoder that only handles what we need
local function decode_streaming_json(str)
  local content = str:match('"content":"([^"]*)"')
  if not content then
    return nil
  end

  return {
    choices = {
      {
        delta = {
          content = content:gsub('\\(["\\/nrt])', {
            n = "\n",
            r = "\r",
            t = "\t",
            ['"'] = '"',
            ["\\"] = "\\",
            ["/"] = "/",
          }),
        },
      },
    },
  }
end

local M = {
  _windows = {},
  _loading = {
    timer = nil,
    frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    index = 1,
  },
}

-- Create a window helper function
local function create_window(opts)
  local buf = vim.api.nvim_create_buf(false, true)

  -- Remove non-window options before creating window
  local win_opts = vim.tbl_extend("force", {}, opts)
  win_opts.highlight = nil
  win_opts.readonly = nil
  win_opts.initial_text = nil

  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Make sure buffer is modifiable before setting initial text
  vim.bo[buf].modifiable = true
  if opts.initial_text then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.initial_text })
    if opts.highlight then
      vim.api.nvim_buf_add_highlight(buf, -1, opts.highlight, 0, 0, -1)
    end
  end

  -- Set final modifiable state
  vim.bo[buf].modifiable = not opts.readonly
  return buf, win
end

function M.open()
  local dims = {
    height = math.floor(vim.o.lines * 0.8),
    width = math.floor(vim.o.columns * 0.8),
    row = math.floor(vim.o.lines * 0.1),
    col = math.floor(vim.o.columns * 0.1),
  }

  -- Create windows
  local status_buf, status_win = create_window({
    relative = "editor",
    width = dims.width,
    height = 1,
    row = dims.row,
    col = dims.col,
    style = "minimal",
    border = "rounded",
    initial_text = "Status: Ready",
    highlight = "Title",
    readonly = true,
  })

  local output_buf, output_win = create_window({
    relative = "editor",
    width = dims.width,
    height = math.floor(dims.height * 0.7) - 2,
    row = dims.row + 2,
    col = dims.col,
    style = "minimal",
    border = "rounded",
    initial_text = "Response will show here...",
    highlight = "Title",
    readonly = true,
  })

  -- Configure output window
  vim.wo[output_win].wrap = true
  vim.wo[output_win].linebreak = true
  vim.wo[output_win].breakindent = true

  local input_buf, input_win = create_window({
    relative = "editor",
    width = dims.width,
    height = dims.height - math.floor(dims.height * 0.7),
    row = dims.row + math.floor(dims.height * 0.7),
    col = dims.col,
    style = "minimal",
    border = "rounded",
    initial_text = "Ask anything...",
    highlight = "Question",
  })

  -- Store references
  M._windows = {
    status = { buf = status_buf, win = status_win },
    output = { buf = output_buf, win = output_win },
    input = { buf = input_buf, win = input_win },
  }

  -- Setup keymaps and autocmds
  local function close_all()
    for _, w in pairs(M._windows) do
      if vim.api.nvim_win_is_valid(w.win) then
        vim.api.nvim_win_close(w.win, true)
      end
    end
  end

  -- Clear welcome message on first insert
  vim.api.nvim_create_autocmd("InsertEnter", {
    buffer = input_buf,
    once = true,
    callback = function()
      vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, {})
    end,
  })

  -- Set keymaps
  local function set_keymap(buf)
    vim.keymap.set("n", "q", close_all, { buffer = buf, noremap = true })
  end

  set_keymap(input_buf)
  set_keymap(output_buf)
  set_keymap(status_buf)
  vim.keymap.set("n", "<CR>", function()
    M.send_prompt()
  end, { buffer = input_buf, noremap = true })
end

-- Simplified loading animation
function M.toggle_loading(enable)
  if enable then
    if M._loading.timer then
      return
    end
    M._loading.timer = vim.loop.new_timer()
    M._loading.timer:start(
      0,
      100,
      vim.schedule_wrap(function()
        if not vim.api.nvim_buf_is_valid(M._windows.status.buf) then
          M.toggle_loading(false)
          return
        end

        local frame = M._loading.frames[M._loading.index]
        -- Make buffer modifiable before updating
        vim.bo[M._windows.status.buf].modifiable = true
        vim.api.nvim_buf_set_lines(M._windows.status.buf, 0, -1, false, { "Status: Fetching response " .. frame })
        vim.bo[M._windows.status.buf].modifiable = false
        M._loading.index = (M._loading.index % #M._loading.frames) + 1
      end)
    )
  else
    if M._loading.timer then
      M._loading.timer:stop()
      M._loading.timer:close()
      M._loading.timer = nil
    end
  end
end

function M.send_prompt()
  local lines = vim.api.nvim_buf_get_lines(M._windows.input.buf, 0, -1, false)
  local prompt = table.concat(lines, "\n")

  if not config.api_key or config.api_key == "" then
    vim.notify("Missing API key in lazyai.config", vim.log.levels.ERROR)
    return
  end

  M.toggle_loading(true)

  -- Setup output buffer
  vim.bo[M._windows.output.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M._windows.output.buf, 0, -1, false, {})
  vim.bo[M._windows.output.buf].filetype = "markdown"
  vim.bo[M._windows.output.buf].modifiable = false -- Set back to non-modifiable

  -- Call OpenAI API
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  vim.loop.spawn("curl", {
    args = {
      "-N",
      "-s",
      "-H",
      "Content-Type: application/json",
      "-H",
      "Authorization: Bearer " .. config.api_key,
      "-d",
      vim.fn.json_encode({
        model = "gpt-4",
        messages = { { role = "user", content = prompt } },
        stream = true,
      }),
      "https://api.openai.com/v1/chat/completions",
    },
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()

    if code ~= 0 then
      vim.schedule(function()
        vim.notify("OpenAI API request failed", vim.log.levels.ERROR)
      end)
    end
  end)

  -- Handle response streaming
  stdout:read_start(function(err, data)
    assert(not err, err)
    if not data then
      vim.schedule(function()
        M.toggle_loading(false)
        vim.bo[M._windows.status.buf].modifiable = true
        vim.api.nvim_buf_set_lines(M._windows.status.buf, 0, -1, false, { "Status: Ready" })
        vim.bo[M._windows.status.buf].modifiable = false
      end)
      return
    end

    for line in vim.gsplit(data, "\n") do
      if line:match("^data: ") then
        local json_str = line:sub(6)
        if json_str ~= "[DONE]" then
          local decoded = decode_streaming_json(json_str)
          if decoded and decoded.choices[1].delta.content then
            vim.schedule(function()
              local content = decoded.choices[1].delta.content
              local current = vim.api.nvim_buf_get_lines(M._windows.output.buf, -2, -1, false)
              local new_lines = vim.split(content, "\n", { plain = true })
              -- Make buffer modifiable before changes
              vim.bo[M._windows.output.buf].modifiable = true
              if #current > 0 then
                new_lines[1] = current[#current] .. new_lines[1]
                vim.api.nvim_buf_set_lines(M._windows.output.buf, -2, -1, false, { new_lines[1] })
                if #new_lines > 1 then
                  vim.api.nvim_buf_set_lines(M._windows.output.buf, -1, -1, false, { unpack(new_lines, 2) })
                end
              else
                vim.api.nvim_buf_set_lines(M._windows.output.buf, 0, -1, false, new_lines)
              end
              -- Make buffer non-modifiable after changes
              vim.bo[M._windows.output.buf].modifiable = false
            end)
          end
        end
      end
    end
  end)
end

return M
