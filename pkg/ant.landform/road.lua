local ecs   = ...
local world = ecs.world
local w     = world.w

local bgfx      = require "bgfx"
local math3d    = require "math3d"

local imaterial     = ecs.require "ant.asset|material"
local idrawindirect = ecs.require "ant.render|draw_indirect.draw_indirect"
local irender       = ecs.require "ant.render|render_system.render"
local icompute      = ecs.require "ant.render|compute.compute"
local renderpkg     = import_package "ant.render"
local layoutmgr     = renderpkg.layoutmgr
local layout        = layoutmgr.get "p3|t20|c40niu"

local hwi           = import_package "ant.hwi"

local CONST<const> = require "gameplay.interface.constant"
local UNIT <const> = CONST.TILE_SIZE
local ROAD_SIZE<const> = 2
local ROAD_WIDTH, ROAD_HEIGHT = ROAD_SIZE * UNIT, ROAD_SIZE * UNIT

local ROT_TABLES = {
    N = {0,   270, 180, 0},
    E = {270, 0,   90,  0},
    S = {180, 90,  0,   0},
    W = {90,  180, 270, 0},
}

--column matrix
local MAT2_MT = {
    row = function (self, idx)
        assert(1<=idx and idx<=2)
        return {self[idx], self[idx+2]}
    end,
    transform = function (self, pt)
        local function dot2(v1, v2)
            return v1[1] * v2[1] + v1[2] * v2[2]
        end
        return {
            dot2(self:row(1), pt), dot2(self:row(2), pt)
        }
    end
}

local function create_mat2(r)
    local c, s = math.cos(r), math.sin(r)
    local t = {
        c, -s,  --[1, 2] ==> column 1
        s,  c   --[3, 4] ==> column 2
    }
    return setmetatable(t, MAT2_MT)
end

local DEBUG_MAT2 = false
if DEBUG_MAT2 then
    local m1 = create_mat2(math.pi*0.5)
    local d1 = m1:transform({1, 0})
    assert(d1[1] == 0 and d1[2] == -1)
end

local DEFAULT_QUAD_TEXCOORD<const> = {
    {1, 0}, -- quad vertex index 0
    {0, 0}, -- quad vertex index 1
    {1, 0}, -- quad vertex index 2
    {1, 1}, -- quad vertex index 3
}

local function quad_texcoord(degree)
    local m = create_mat2(math.rad(degree))
    local t = {}
    for i=1, #DEFAULT_QUAD_TEXCOORD do
        t[i] = m:transform(DEFAULT_QUAD_TEXCOORD[i])
    end
    return t
end

local QUAD_TEXCOORDS<const> = {
    [0]     = DEFAULT_QUAD_TEXCOORD,
    [90]    = quad_texcoord(90),
    [180]   = quad_texcoord(180),
    [270]   = quad_texcoord(270),
}

local SHADPE_DIRECTIONS<const> = {
    "N", "E", "S", "W",
    N = 1,
    E = 2,
    S = 3,
    W = 4,
}

local SHAPE_TYPES<const> = {
    "U", "I", "L", "T", "X", "O",
    U = {
        index = 1,
        direction = {
            N = QUAD_TEXCOORDS[0],
            E = QUAD_TEXCOORDS[270],
            S = QUAD_TEXCOORDS[180],
            W = QUAD_TEXCOORDS[90],
        }
    },
    I = {
        index = 2,
        direction = {
            N = QUAD_TEXCOORDS[270],
            E = QUAD_TEXCOORDS[0],
            S = QUAD_TEXCOORDS[90],
            W = QUAD_TEXCOORDS[180],
        }
    },
    L = {
        index = 3,
        direction = {
            N = QUAD_TEXCOORDS[180],
            E = QUAD_TEXCOORDS[90],
            S = QUAD_TEXCOORDS[0],
            W = QUAD_TEXCOORDS[270],
        }
    },
    T = {
        index = 4,
        direction = {
            N = QUAD_TEXCOORDS[0],
            E = QUAD_TEXCOORDS[270],
            S = QUAD_TEXCOORDS[180],
            W = QUAD_TEXCOORDS[90],
        },
    },
    X = {
        index = 5,
        direction = {
            N = QUAD_TEXCOORDS[0],
            E = QUAD_TEXCOORDS[0],
            S = QUAD_TEXCOORDS[0],
            W = QUAD_TEXCOORDS[0],
        }
    },
    O = {
        index = 6,
        direction = {
            N = QUAD_TEXCOORDS[0],
            E = QUAD_TEXCOORDS[0],
            S = QUAD_TEXCOORDS[0],
            W = QUAD_TEXCOORDS[0],
        }
    },
}

local STATES_MAPPER<const> = {
    --indicator state
    normal = {
        index = 1,
        color = 0xfffffff,
    },
    remove = {
        index = 2,
        color = 0xff2020ff,
    },
    modify = {
        index = 3,
        color = 0xffe4e4e4,
    },

    --road state
    invalid = {
        index = 1,
        color = 0xff0000b6,
    },
    valid   = {
        index = 2,
        color = 0xffffffff,
    }
}

local NUM_QUAD_VERTICES<const> = 4

local function to_mesh_buffer(vb, ib_handle)
    local vbbin = table.concat(vb, "")
    local numv = #vbbin // layout.stride
    local numi = (numv // NUM_QUAD_VERTICES) * 6 --6 for one quad 2 triangles and 1 triangle for 3 indices

    return {
        bounding = nil,
        vb = {
            start = 0,
            num = numv,
            handle = bgfx.create_vertex_buffer(bgfx.memory_buffer(vbbin), layout.handle),
        },
        ib = {
            start = 0,
            num = numi,
            handle = ib_handle,
        }
    }
end

local ROAD_MESH

-- local function build_ib(num_quad)
--     local b = {}
--     for ii=1, num_quad do
--         local offset = (ii-1) * 4
--         b[#b+1] = offset + 0
--         b[#b+1] = offset + 1
--         b[#b+1] = offset + 2

--         b[#b+1] = offset + 2
--         b[#b+1] = offset + 3
--         b[#b+1] = offset + 0
--     end
--     return bgfx.create_index_buffer(bgfx.memory_buffer("w", b))
-- end

local VBFMT<const> = "fffffI"
local function build_vb(ox, oz, ww, hh, texcoords, vb)
    local nx, nz = ox+ww, oz+hh
    local uv
    uv = texcoords[1]; vb[#vb+1] = VBFMT:pack(ox, 0, oz, uv[1], uv[2])
    uv = texcoords[2]; vb[#vb+1] = VBFMT:pack(ox, 0, nz, uv[1], uv[2])
    uv = texcoords[3]; vb[#vb+1] = VBFMT:pack(nx, 0, nz, uv[1], uv[2])
    uv = texcoords[4]; vb[#vb+1] = VBFMT:pack(nx, 0, oz, uv[1], uv[2])
end

local road_sys   = ecs.system "road_system"

function road_sys:entity_remove()
    for e in w:select "REMOVED road:in" do
        
    end
end

local function to_dispath_num(indirectnum)
    return (indirectnum+63) // 64
end

local main_viewid<const> = hwi.viewid_get "main_view"

local function dispath_road_indirect_buffer(e, dieid)
    local die = world:entity(dieid, "draw_indirect:in road:in")
    local di = die.draw_indirect
    local dis = e.dispatch
    local m = dis.material

    local instancenum = di.instance_buffer.num
    dis.size[1] = to_dispath_num(instancenum)

    local ibnum<const> = 6
    m.u_mesh_param = math3d.vector(ibnum, instancenum, 0, 0)
    m.b_mesh_buffer = {
        type = "b",
        access = "r",
        value = die.road.handle,
        stage = 0,
    }
    m.b_indirect_buffer = {
        type = "b",
        access = "w",
        value = di.handle,
        stage = 1,
    }

    icompute.dispatch(main_viewid, dis)
end

local INSTANCEBUFFER_FMT<const> = 'ffIf'
local MESHBUFFER_FMT<const> = 'HH'

local function build_instance_buffers(infos)
    local roadbuffer, indicatorbuffer = {}, {}
    local roadmeshbuffer, indicatormeshbuffer = {}, {}
    for _, i in ipairs(infos) do
        local p = i.pos

        local function add_buffer(t, ib, mb)
            ib[#ib+1] = INSTANCEBUFFER_FMT:pack(p[1], p[2], STATES_MAPPER[t.state].color, 0)
            mb[#mb+1] = MESHBUFFER_FMT:pack(SHAPE_TYPES[t.shape].index, SHADPE_DIRECTIONS[t.dir])
        end

        local r = i.road
        if r then
            add_buffer(r, roadbuffer, roadmeshbuffer)
        end

        local indicator = i.indicator
        if indicator then
            add_buffer(indicator, indicator, indicatormeshbuffer)
        end
    end

    return {
        road = {
            instancebuffer = roadbuffer,
            meshbuffer = roadmeshbuffer,
        },
        indicaotr = {
            instancebuffer = indicatorbuffer,
            meshbuffer = indicatormeshbuffer,
        }
    }
end

local function update_di_buffers(dieid, buffer)
    local die = world:entity(dieid, "draw_indirect:update road:update")
    bgfx.update(die.road.handle, 0, table.concat(buffer.meshbuffer))

    local di = die.draw_indirect
    di.num = #buffer.instancebuffer
    bgfx.update(di.instance_buffer.handle, 0, buffer.instancebuffer)
end

local function create_mesh_buffer(b)
    return bgfx.create_dynamic_index_buffer(table.concat(b, ""), "dr")  -- d for uint32, r for compute read
end

local function create_road_entities(gid, render_layer, road, indicator)
    --road
    local road_instancenum = #road.instancebuffer
    local road_dieid = world:create_entity {
        group = gid,
        policy = {
            "ant.render|simplerender",
            "ant.render|draw_indirect",
            "ant.landform|road",
        },
        data = {
            scene = {},
            simplemesh  = assert(ROAD_MESH),
            material    = "/pkg/ant.landform/assets/materials/road.material",
            visible_state = "main_view|selectable",
            road = {
                handle = create_mesh_buffer(road.meshbuffer),
            },
            render_layer = render_layer,
            draw_indirect = {
                instance_buffer = {
                    memory  = table.concat(road.instancebuffer, ""),
                    flag    = "r",
                    layout  = "t45NIf",
                    num     = road_instancenum,
                },
            },
        },
    }

    local road_computeeid = world:create_entity{
        policy = {
            "ant.render|compute",
        },
        data = {
            material = "/pkg/ant.landform/materials/road_compute.material",
            dispatch = {
                size = {0, 1, 1},
            },
            on_ready = function (e)
                dispath_road_indirect_buffer(e, road_dieid)
            end
        }
    }

    -- indicator
    local indicator_instancenum = #indicator.instancebuffer
    local indicator_dieid = world:create_entity{
        group = gid,
        policy = {
            "ant.render|simplerender",
            "ant.render|draw_indirect",
            "ant.landform|road",
        },
        data = {
            scene = {},
            render_layer = render_layer,
            simplemesh = ROAD_MESH,
            draw_indirect = {
                instance_buffer = {
                    dynamic = true,
                    memory  = table.concat(indicator.instancebuffer, ""),
                    flag    = "r",
                    layout  = "t45NIf",
                    num     = indicator_instancenum,
                },
            },
            road = {
                handle = create_mesh_buffer(indicator.meshbuffer),
            },
            material = "/pkg/ant.landform/assets/materials/indicator.material",
        }
    }

    local indicator_computeeid = world:create_entity {
        group = gid,
        policy = {
            "ant.render|compute",
        },
        data = {
            material = "/pkg/ant.landform/materials/road_compute.material",
            dispatch = {
                size = {0, 1, 1},
            },
            on_ready = function (e)
                dispath_road_indirect_buffer(e, road_dieid)
            end
        }
    }

    return {
        road = {
            drawindirect = road_dieid,
            compute = road_computeeid,
        },
        indicator = {
            drawindirect = indicator_dieid,
            compute = indicator_computeeid,
        },
    }
end

local ROAD_ENTITIES = {}

local iroad         = {}
local function build_road_mesh(rw, rh)
    local road_vb = {}
    for _, s in ipairs(SHAPE_TYPES) do
        local st = SHAPE_TYPES[s]
        for _, dn in ipairs(SHADPE_DIRECTIONS) do
            local texcoords = st.direction[dn]
            build_vb(0, 0, rw, rh, texcoords, road_vb)
        end
    end

    assert(#road_vb == 4 * #SHAPE_TYPES * #SHADPE_DIRECTIONS)
    return to_mesh_buffer(road_vb, irender.quad_ib())
end

function iroad.create(roadwidth, roadheight)
    ROAD_MESH = build_road_mesh(roadwidth, roadheight)
end

function iroad.update_roadnet(groups, render_layer)
    for gid, infos in pairs(groups) do
        local entities = ROAD_ENTITIES[gid]
        local buffers = build_instance_buffers(infos)
        if nil == entities then
            entities = create_road_entities(gid, render_layer, buffers.road, buffers.indicaotr)
            ROAD_ENTITIES[gid] = entities
        else
            local function update_buffer_and_dispatch(buffer, eids)
                update_di_buffers(buffer, eids.drawindirect)
                dispath_road_indirect_buffer(world:entity(eids.compute, "dispatch:in"), eids.drawindirect)
            end

            update_buffer_and_dispatch(buffers.road,        entities.road)
            update_buffer_and_dispatch(buffers.indicaotr,   entities.indicaotr)
        end
    end
end

function iroad.get_road_size()
    return ROAD_WIDTH, ROAD_HEIGHT
end

return iroad
