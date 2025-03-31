local M = {}

-- Read .env file
local function read_env_file()
	-- Get the directory of the current file
	local current_file = debug.getinfo(1, "S").source:sub(2)
	local current_dir = vim.fn.fnamemodify(current_file, ":p:h")
	local env_path = current_dir .. "/.env"

	local lines = vim.fn.readfile(env_path)
	if not lines or #lines == 0 then
		return nil
	end

	-- Parse the first line for LAZYAI_API_KEY
	local line = lines[1]
	local key = line:match("LAZYAI_API_KEY=\"([^"]+)\"")
	return key
end

M.api_key = vim.env.LAZYAI_API_KEY or read_env_file() or os.getenv("LAZYAI_API_KEY")

if not M.api_key or M.api_key == "" then
	vim.notify("No API key found. Please set LAZYAI_API_KEY in your environment or .env file", vim.log.levels.ERROR)
end

return M
