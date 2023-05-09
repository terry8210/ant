local ltask = require "ltask"

local S = {}
local lables = {}
local command = {}
local tasks = {}

local function querylabel(id)
	if not id then
		return "unknown"
	end
	if id == 0 then
		return "system"
	end
	if lables[id] then
		return lables[id]
	end
	return "unknown"
end

local function service(id)
	return ("(%s:%d)"):format(querylabel(id), id)
end

function command.startup(id, label)
	lables[id] = label:sub(9)
	return service(id) .. " startup."
end

function command.quit(id)
	tasks[#tasks+1] = function ()
		lables[id] = nil
	end
	return service(id) .. " quit."
end

function command.service(_, id)
	id = tonumber(id)
	return service(id)
end

local function parse(id, s)
	local name, args = s:match "^([^:]*):(.*)$"
	if not name then
		name = s
		args = nil
	end
	local f = command[name]
	if f then
		return f(id, args)
	end
	return s
end

local function runtask()
	if #tasks > 0 then
		for i = 1, #tasks do
			tasks[i]()
		end
		tasks = {}
	end
end

local LOG

if __ANT_RUNTIME__ then
    local platform = require "bee.platform"
    local ServiceIO = ltask.queryservice "io"
	local function app_path(name)
		if platform.os == "ios" then
			local ios = require "ios"
			return ios.directory(ios.NSDocumentDirectory)
		elseif platform.os == 'android' then
			local android = require "android"
			return android.directory(android.ExternalDataPath)
		end
	end
	local document = app_path()
	if document then
		local fs = require "bee.filesystem"
		local logfile = document .. "/log/" .. (os.date '%Y%m%d_%H%M%S') .. ".log"
		fs.create_directories(document .. "/log")
		function LOG(data)
			ltask.send(ServiceIO, "SEND", "LOG", data)
			local f <close> = io.open(logfile, "a+")
			if f then
				f:write(data)
				f:write("\n")
			end
		end
	else
		function LOG(data)
			ltask.send(ServiceIO, "SEND", "LOG", data)
		end
	end
else
    function LOG(data)
        io.write(data)
        io.write("\n")
        io.flush()
    end
end

local function writelog()
	while true do
		local ti, id, msg, sz = ltask.poplog()
		if ti == nil then
			break
		end
		local tsec = ti // 100
		local msec = ti % 100
		local t = table.pack(ltask.unpack_remove(msg, sz))
		local str = {}
		for i = 1, t.n do
			str[#str+1] = tostring(t[i])
		end

		local message = table.concat(str, "\t")
		message = string.gsub(message, "%$%{([^}]*)%}", function (s)
			return parse(id, s)
		end)
		LOG(string.format("[%s.%02d : %-10s]%s", os.date("%Y-%m-%d %H:%M:%S", tsec), msec, querylabel(id), message))
	end
end

ltask.fork(function ()
	while true do
		writelog()
		ltask.sleep(100)
	end
end)

function S.quit()
	writelog()
end

function S.labels()
	return lables
end

return S
