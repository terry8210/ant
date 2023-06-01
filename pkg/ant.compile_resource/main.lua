if not __ANT_RUNTIME__ then
    if package.loaded.math3d then
        error "need init math3d MAXPAGE"
    end
    debug.getregistry().MATH3D_MAXPAGE = 10240
end

local lfs       = require "filesystem.local"
local bgfx      = require "bgfx"
local platform  = require "bee.platform"
local vfs       = require "vfs"

local compile
local compile_file
local init_setting
local set_setting

if __ANT_RUNTIME__ then
    local function normalize(p)
        local stack = {}
        p:gsub('[^/|]*', function (w)
            if #w == 0 and #stack ~= 0 then
            elseif w == '..' and #stack ~= 0 and stack[#stack] ~= '..' then
                stack[#stack] = nil
            elseif w ~= '.' then
                stack[#stack + 1] = w
            end
        end)
        return table.concat(stack, "/")
    end

    function compile(pathstring)
        pathstring = normalize(pathstring)
        return lfs.path(vfs.realpath(pathstring))
    end
    init_setting = function ()
    end
    set_setting = vfs.resource_setting
else
    local editor = require "editor.compile"
    local config   = require "editor.config"
    compile = editor.compile
    compile_file = editor.compile_file
    init_setting = config.init
    set_setting = config.set
end

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

local function stringify(t)
    local s = {}
    for k, v in sortpairs(t) do
        s[#s+1] = k.."="..tostring(v)
    end
    return table.concat(s, "&")
end

local texture_extensions <const> = {
    noop        = platform.os == "windows" and "dds" or "ktx",
	direct3d11 	= "dds",
	direct3d12 	= "dds",
	metal 		= "ktx",
	vulkan 		= "ktx",
	opengl 		= "ktx",
}

local BgfxOS <const> = {
    macos = "osx",
}

local function init()
    local caps = bgfx.get_caps()
    local renderer = caps.rendererType:lower()
    local texture = assert(texture_extensions[renderer])
    init_setting()
    set_setting("model", stringify {})
    set_setting("glb", stringify {})
    set_setting("material", stringify {
        os = BgfxOS[platform.os] or platform.os,
        renderer = renderer,
        hd = caps.homogeneousDepth and true or nil,
        obl = caps.originBottomLeft and true or nil,
    })
    set_setting("texture", stringify {os=platform.os, ext=texture})
    set_setting("png", stringify {os=platform.os, ext=texture})
end

return {
    -- resouce service
    init         = init,
    compile      = compile,
    -- fileserver
    init_setting = init_setting,
    set_setting  = set_setting,
    compile_file = compile_file,
}
