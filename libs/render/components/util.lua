local util = {}
util.__index = util

local asset = require "asset"
local common_util = require "common.util"
local mu = require "math.util"
local bgfxutil = require "bgfx.util"

function util.load_mesh(entity, meshpath, param)
	local mesh_comp = entity.mesh
	if meshpath then
		mesh_comp.path = meshpath
	end

	local assetinfo = asset.load(mesh_comp.path, param)
	mesh_comp.assetinfo = assetinfo
end

local function load_texture(tex)
	local texpath = tex.default
	assert(type(texpath) == "string", "texture type's default value should be path to texture file")
	local assetinfo = asset.load(texpath)
	return {name=tex.name, type=tex.type, stage=tex.stage, value=assetinfo.handle}
end

function util.load_material(entity, material_filenames)
	if material_filenames then
		for idx, f in ipairs(material_filenames) do
			entity.material.content[idx] = {path = f, properties = {}}
		end
	end

	local material_comp = entity.material

	local content = material_comp.content
	for _, m in ipairs(content) do
		local filename = m.path		
		local materialinfo = asset.load(filename)
		m.materialinfo = materialinfo
	
		--
		local properties = assert(m.properties)	
		local asset_properties = materialinfo.properties
		if asset_properties then
			for k, v in pairs(asset_properties) do
				if v.type == "texture" then
					properties[k] = load_texture(v)
				else
					properties[k] = {name=v.name, type=v.type, value=common_util.deep_copy(v.default)}
				end
				
			end
		end
	end
end

function util.create_render_entity(ms, world, name, meshfile, materialfile)
	local eid = world:new_entity("scale", "rotation", "position",
	"mesh", "material",
	"name",
	"can_select", "can_render")

	local obj = world[eid]
	mu.identify_transform(ms, obj)
	
	obj.name.n = name

	obj.mesh.path = meshfile
	util.load_mesh(obj)		

	obj.material.content[1] = {path=materialfile, properties={}}
	util.load_material(obj)
	return eid
end

function util.create_hierarchy_entity(ms, world, name)
	local h_eid = world:new_entity("scale", "rotation", "position",
	"editable_hierarchy", "hierarchy_name_mapper", 
	"name")

	local obj = world[h_eid]
	obj.name.n = name

	mu.identify_transform(ms, obj)
	return h_eid
end

function util.is_entity_visible(entity)
	local can_render = entity.can_render
	if can_render then
		if can_render.visible then
			return entity.mesh ~= nil
		end		
	end

	return false
end

return util