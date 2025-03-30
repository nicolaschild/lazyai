-- TODO: Code organization
-- TODO: Create context window(s)

local config = require("lazyai.config")

-- Initialize conversation array
local conversation = {}

-- Function to add message to conversation
local function addToConversation(role, message)
	table.insert(conversation, {role = role, message = message})
end

local M = {
	_windows = {},
	_loading = {
		timer = nil,
		frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
		index = 1,
	},
}

-- Function to update output buffer with conversation history
function M.update_output_buffer()
	if not M._windows.output or not M._windows.output.buf then
		return
	end
	
	local formatted_lines = {}
	for i, entry in ipairs(conversation) do
		-- Add prefix for user messages
		local prefix = entry.role == "user" and "> " or ""
		
		-- Split message into lines and format each line
		local message_lines = vim.split(entry.message, "\n", { plain = true })
		for _, line in ipairs(message_lines) do
			table.insert(formatted_lines, prefix .. line)
		end
		
		-- Add empty line after each message
		table.insert(formatted_lines, "")
		
		-- Add extra empty line after each assistant message (which completes a chat pair)
		if entry.role == "assistant" and i < #conversation then
			table.insert(formatted_lines, "")
		end
	end
	
	-- Schedule the buffer update
	vim.schedule(function()
		-- Update output buffer
		vim.bo[M._windows.output.buf].modifiable = true
		vim.api.nvim_buf_set_lines(M._windows.output.buf, 0, -1, false, formatted_lines)
		vim.bo[M._windows.output.buf].modifiable = false
		
		-- Ensure spell check remains disabled
		vim.api.nvim_buf_set_option(M._windows.output.buf, "spell", false)
		vim.api.nvim_win_set_option(M._windows.output.win, "spell", false)
	end)
end

-- Create a window helper function
local function create_window(opts)
	local buf = vim.api.nvim_create_buf(false, true)

	-- Remove non-window options before creating window
	local win_opts = vim.tbl_extend("force", {}, opts)
	win_opts.highlight = nil
	win_opts.readonly = nil
	win_opts.initial_text = nil
	win_opts.spell = nil -- remove to avoid being passed to nvim_open_win

	local win = vim.api.nvim_open_win(buf, true, win_opts)

	-- Make sure buffer is modifiable before setting initial text
	vim.bo[buf].modifiable = true
	if opts.initial_text then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.initial_text })
		if opts.highlight then
			vim.api.nvim_buf_add_highlight(buf, -1, opts.highlight, 0, 0, -1)
		end
	end

	-- Final modifiable state
	vim.bo[buf].modifiable = not opts.readonly

	if opts.spell ~= nil then
		vim.api.nvim_buf_set_option(buf, "spell", opts.spell)
		vim.api.nvim_win_set_option(win, "spell", opts.spell)
	end

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
		spell = false,
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
				vim.api.nvim_buf_set_lines(
					M._windows.status.buf,
					0,
					-1,
					false,
					{ "Status: Fetching response " .. frame }
				)
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

	-- Store user message in conversation
	addToConversation("user", prompt)
	M.update_output_buffer()

	if not config.api_key or config.api_key == "" then
		vim.notify("Missing API key in lazyai.config", vim.log.levels.ERROR)
		return
	end

	M.toggle_loading(true)

	-- Setup output buffer
	vim.bo[M._windows.output.buf].modifiable = true
	vim.api.nvim_buf_set_lines(M._windows.output.buf, 0, -1, false, {})
	vim.bo[M._windows.output.buf].filetype = "markdown"
	vim.bo[M._windows.output.buf].modifiable = false

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
	local full_response = ""
	
	stdout:read_start(function(err, data)
		assert(not err, err)
		if not data then
			addToConversation("assistant", full_response)
			M.update_output_buffer()
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
				if json_str == "[DONE]" then
					addToConversation("assistant", full_response)
					M.update_output_buffer()
					vim.schedule(function()
						M.toggle_loading(false)
						vim.bo[M._windows.status.buf].modifiable = true
						vim.api.nvim_buf_set_lines(M._windows.status.buf, 0, -1, false, { "Status: Ready" })
						vim.bo[M._windows.status.buf].modifiable = false
					end)
					break
				end

				vim.schedule(function()
					local success, result = pcall(vim.fn.json_decode, json_str)
					if not success then
						return
					end

					if
						not result.choices
						or not result.choices[1]
						or not result.choices[1].delta
						or not result.choices[1].delta.content
					then
						return
					end

					local content = result.choices[1].delta.content
					full_response = full_response .. content

					-- Format all lines including the streaming response
					local formatted_lines = {}
					
					-- Add existing conversation
					for i, entry in ipairs(conversation) do
						local prefix = entry.role == "user" and "> " or ""
						local message_lines = vim.split(entry.message, "\n", { plain = true })
						for _, msg_line in ipairs(message_lines) do
							table.insert(formatted_lines, prefix .. msg_line)
						end
						table.insert(formatted_lines, "")
						
						-- Add extra empty line after each assistant message (which completes a chat pair)
						if entry.role == "assistant" and i < #conversation then
							table.insert(formatted_lines, "")
						end
					end

					-- Add current streaming response
					local stream_lines = vim.split(full_response, "\n", { plain = true })
					for _, stream_line in ipairs(stream_lines) do
						table.insert(formatted_lines, stream_line)
					end

					-- Ensure there's always a blank line at the end
					if #formatted_lines > 0 and formatted_lines[#formatted_lines] ~= "" then
						table.insert(formatted_lines, "")
					end

					-- Update buffer
					vim.bo[M._windows.output.buf].modifiable = true
					vim.api.nvim_buf_set_lines(M._windows.output.buf, 0, -1, false, formatted_lines)
					vim.bo[M._windows.output.buf].modifiable = false

					-- Ensure spell check remains disabled
					vim.api.nvim_buf_set_option(M._windows.output.buf, "spell", false)
					vim.api.nvim_win_set_option(M._windows.output.win, "spell", false)
				end)
			end
		end
	end)
end

return M
