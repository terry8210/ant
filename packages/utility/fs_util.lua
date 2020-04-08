local util = {}; util.__index = util
local fs = require "filesystem.local"

local platform  = require "platform"

function util.list_files(subpath, filter, excludes)
	local prefilter = {}
	if type(filter) == "string" then
		for f in filter:gmatch("([.%w]+)") do
			local ext = f:upper()
			prefilter[ext] = true
		end
	end

	local function list_fiels_1(subpath, filter, excludes, files)
		for p in subpath:list_directory() do
			local name = p:filename():string()
			if not excludes[name] then
				if fs.is_directory(p) then
					list_fiels_1(p, filter, excludes, files)
				else
					if type(filter) == "function" then
						if filter(p) then
							files[#files+1] = p
						end
					else
						local fileext = p:extension():string():upper()
						if filter[fileext] then
							files[#files+1] = p
						end
					end
					
				end
			end
		end		
	end

    local files = {}
    list_fiels_1(subpath, prefilter, excludes, files)
    return files
end

function util.raw_table(filepath, fetchresult)
	local env = {}
	local r = assert(fs.loadfile(filepath, "t", env))
	local result = r()
	if fetchresult then
		return result
	end
	return env
end

function util.fetch_file_content(filepath)
	local f = fs.open(filepath, "rb")
	local c = f:read "a"
	f:close()
	return c
end

function util.write_file(filepath, c)
    local f = fs.open(filepath, "wb")
    f:write(c)
    f:close()
end

local OS        = platform.OS
local CWD       = fs.current_path()

local vspath    = "projects/msvc/vs_bin"

local function is_msvc()
    -- TODO
    return not not package.cpath:match 'projects[\\/]msvc[\\/]vs_bin'
end

local function which_platfrom_type()
    if OS == "Windows" then
        return is_msvc() and "msvc" or "mingw"
    else
        return "osx"
    end
end
local plattype = which_platfrom_type()

local toolsuffix = OS == "OSX" and "" or ".exe"

local function to_execute_path(pathname)
    return CWD / (pathname .. toolsuffix)
end

local function tool_paths(toolbasename)
    local toolnameDebug = toolbasename .. "Debug"
    local toolnameRelease = toolbasename .. "Release"
    local function to_binpath(name)
        return "bin/" .. plattype .. "/" .. name
    end

    if plattype == "msvc" then
        return {
            vspath .. "/Release/" .. toolnameRelease,
            vspath .. "/Debug/" .. toolnameDebug,
            vspath .. "/Release/" .. toolbasename,
            vspath .. "/Debug/" .. toolbasename,
            to_binpath(toolbasename),
        }
    end

    return {
        "clibs/" .. toolbasename,
        "clibs/" .. toolnameRelease,
        "clibs/" .. toolnameDebug,
        to_binpath(toolnameRelease),
        to_binpath(toolnameDebug),
        to_binpath(toolbasename),
    }
end

function util.valid_tool_exe_path(toolname)
    local toolpaths = tool_paths(toolname)

    for _, name in ipairs(toolpaths) do
        local exepath = to_execute_path(name)
        if fs.exists(exepath) then
            return exepath
        end
    end

    error(string.format("not found any valid texturec path. update bin folder or compile from 3rd/bgfx [texturec] project"))
end

return util