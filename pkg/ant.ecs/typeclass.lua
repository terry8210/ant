local interface = require "interface"
local pm = require "packagemanager"
local serialization = require "bee.serialization"

local function sortpairs(t)
    local sort = {}
    for k in pairs(t) do
        sort[#sort+1] = k
    end
    table.sort(sort)
    local n = 1
    return function ()
        local k = sort[n]
        if k == nil then
            return
        end
        n = n + 1
        return k, t[k]
    end
end

local function splitname(fullname)
    return fullname:match "^([^|]*)|(.*)$"
end

local function create_importor(w)
	local import = {}
	local feature_decl = w._decl.feature
	local system_decl = w._decl.system
	local component_decl = w._decl.component
	local policy_decl = w._decl.policy
	local function import_ecs(packname, filename)
		local res = w._decl:load(packname, filename)
		if res then
			for k in pairs(res.import_feature) do
				import.feature(k)
			end
			for k in pairs(res.system) do
				import.system(k)
			end
		end
	end
	function import.feature(name)
		local packname, _ = splitname(name)
		if not packname then
			import_ecs(name, "package.ecs")
			return
		else
			import_ecs(packname, "package.ecs")
		end
		local v = feature_decl[name]
		if not v then
			error(("invalid feature name: `%s`."):format(name))
		end
		if v.imported then
			return
		end
		v.imported = true
		if v.import then
			log.debug("Import  feature", name)
			for _, fullname in ipairs(v.import) do
				local packname, filename
				if fullname:sub(1,1) == "@" then
					if fullname:find "/" then
						packname, filename = fullname:match "^@([^/]*)/(.*)$"
					else
						packname = fullname:sub(2)
						filename = "package.ecs"
					end
				else
					packname = v.packname
					filename = fullname
				end
				import_ecs(packname, filename)
			end
		end
	end
	function import.system(name)
		local v = system_decl[name]
		if not v then
			error(("invalid system name: `%s`."):format(name))
		end
		if v.imported then
			return
		end
		if not w._initializing then
			error(("system `%s` can only be imported during initialization."):format(name))
		end
		v.imported = true
		if v.implement and v.implement[1] then
			log.debug("Import  system", name)
			local impl = v.implement[1]
			if impl:sub(1,1) == ":" then
				v.c = true
				w._class.system[name] = w:clibs(impl:sub(2))
			else
				local pkg = v.packname
				local file = impl:gsub("^(.*)%.lua$", "%1"):gsub("/", ".")
				w:_package_require(pkg, file)
			end
		end
	end
	function import.component(name)
		local v = component_decl[name]
		if not v then
			error(("invalid component name: `%s`."):format(name))
		end
		if v.imported then
			return
		end
		v.imported = true
		if v.implement and v.implement[1] then
			log.debug("Import  component", name)
			local impl = v.implement[1]
			local pkg = v.packname
			local file = impl:gsub("^(.*)%.lua$", "%1"):gsub("/", ".")
			w:_package_require(pkg, file)
		end
	end
	function import.policy(name)
		local v = policy_decl[name]
		if not v then
			error(("invalid policy name: `%s`."):format(name))
		end
		if v.imported then
			return
		end
		log.debug("Import  policy", name)
		v.imported = true
		local check_map = {
			include_policy = "policy",
			component = "component",
			component_opt = "component",
		}
		for _, tuple in ipairs(v.value) do
			local what, k = tuple[1], tuple[2]
			local attrib = check_map[what]
			if attrib then
				import[attrib](k)
			end
		end
	end
	return import
end

local function toint(v)
	local t = type(v)
	if t == "userdata" then
		local s = tostring(v)
		s = s:match "^%a+: (%x+)$" or s:match "^%a+: 0x(%x+)$"
		return tonumber(assert(s), 16)
	end
	if t == "number" then
		return v
	end
	assert(false)
end

local function cstruct(...)
	local ref = table.pack(...)
	local t = {}
	for i = 1, ref.n do
		t[i] = toint(ref[i])
	end
	local ecs_util = require "ecs.util"
	local data = string.pack("<"..("T"):rep(ref.n), table.unpack(t))
	return ecs_util.userdata(data, ref)
end

local function create_context(w)
	local bgfx       = require "bgfx"
	local math3d     = require "math3d"
	local components = require "ecs.components"
	local ecs = w.w
	local component_decl = w._component_decl
	local function register_component(i, decl)
		local id, size = ecs:register(decl)
		assert(id == i)
		assert(size == components[decl.name] or 0)
	end
	for i, name in ipairs(components) do
		local decl = component_decl[name]
		if decl then
			component_decl[name] = nil
			register_component(i, decl)
		else
			local csize = components[name]
			if csize then
				register_component(i, {
					name = name,
					type = "raw",
					size = csize
				})
			else
				register_component(i, { name = name })
			end
		end
	end
	for _, decl in pairs(component_decl) do
		ecs:register(decl)
	end
	w._component_decl = nil
	local ecs_context = ecs:context()
	w._ecs_world = cstruct(
		ecs_context,
		bgfx.CINTERFACE,
		math3d.CINTERFACE,
		bgfx.encoder_get(),
		0,0,0,0 --kMaxMember == 4
	)
end


local function slove_component(w)
    w._component_decl = {}
    local function register_component(decl)
        w._component_decl[decl.name] = decl
    end
    local component_class = w._class.component
    for name, info in pairs(w._decl.component) do
        local type = info.type[1]
        local class = component_class[name] or {}
        if type == "lua" then
            register_component {
                name = name,
                type = "lua",
                init = class.init,
                marshal = class.marshal or serialization.packstring,
                demarshal = class.demarshal or nil,
                unmarshal = class.unmarshal or serialization.unpack,
            }
        elseif type == "c" then
            local t = {
                name = name,
                init = class.init,
                marshal = class.marshal,
                demarshal = class.demarshal,
                unmarshal = class.unmarshal,
            }
            for i, v in ipairs(info.field) do
                t[i] = v:match "^(.*)|.*$" or v
            end
            register_component(t)
        elseif type == "raw" then
            local t = {
                name = name,
                type = "raw",
                size = assert(math.tointeger(info.size[1])),
                init = class.init,
                marshal = class.marshal,
                demarshal = class.demarshal,
                unmarshal = class.unmarshal,
            }
            register_component(t)
        elseif type == nil then
            register_component {
                name = name
            }
        else
            register_component {
                name = name,
                type = type,
            }
        end
    end
end

local function import_ecs(w, ecs)
	local import = create_importor(w)
	for _, k in ipairs(ecs.feature) do
		import.feature(k)
	end
	w._decl:check()
	for name, v in pairs(w._decl.component) do
		if v.implement[1] then
			import.component(name)
		end
	end
end

local function create_ecs(w, package, tasks)
    local ecs = { world = w }
    function ecs.system(name)
        local fullname = package .. "|" .. name
        local r = w._class.system[fullname]
        if r == nil then
            if not w._decl.system[fullname] then
                w._decl.system[fullname] = {
					value = {}
				}
            end
            log.debug("Register system   ", fullname)
            r = {}
            w._class.system[fullname] = r
            table.insert(tasks.system, fullname)
        end
        return r
    end
    function ecs.component(fullname)
        local r = w._class.component[fullname]
        if r == nil then
            if not w._decl.component[fullname] then
                error(("component `%s` has no declaration."):format(fullname))
            end
            log.debug("Register component", fullname)
            r = {}
            w._class.component[fullname] = r
        end
        return r
    end
    function ecs.require(fullname)
        local pkg, file = fullname:match "^([^|]*)|(.*)$"
        if not pkg then
            pkg = package
            file = fullname
        end
        return w:_package_require(pkg, file)
    end
    return ecs
end

local function init(w, config)
	w._initializing = true
	w._class = {
		system = {},
		component = {},
	}
	w._decl = interface.new(function(_, packname, filename)
		local file = "/pkg/"..packname.."/"..filename
		log.debug(("Import decl %q"):format(file))
		return assert(pm.loadenv(packname).loadfile(file))
	end)
	local tasks = config.ecs
	tasks.system = tasks.system or {}
	setmetatable(w._packages, {__index = function (self, package)
		local v = {
			_LOADED = {},
			ecs = create_ecs(w, package, tasks)
		}
		self[package] = v
		return v
	end})
	import_ecs(w, tasks)
	slove_component(w)
	create_context(w)
	for name, v in sortpairs(w._decl.system) do
		if v.implement and v.implement[1] and not v.imported then
			log.warn(string.format("system `%s` is not imported.", name))
		end
	end
	w._initializing = nil
end

return {
	init = init,
}
