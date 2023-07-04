#include "ecs/world.h"
#include "ecs/select.h"
#include "ecs/component.hpp"
#include "flatmap.h"
#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>
#include <cstdio>

extern "C" {
	#include "math3d.h"
	#include "math3dfunc.h"
}

struct math3d_checkpoint {
	math3d_checkpoint(struct math_context* math3d)
		: math3d(math3d) {
		cp = math_checkpoint(math3d);
	}
	~math3d_checkpoint() {
		math_recover(math3d, cp);
	}
	struct math_context* math3d;
	int cp;
};

static void
math3d_update(struct math_context* math3d, math_t& id, math_t const& m) {
	math_unmark(math3d, id);
	id = math_mark(math3d, m);
}

static bool
worldmat_update(flatmap<ecs::eid, math_t>& worldmats, struct math_context* math3d, ecs::scene& s, ecs::eid& id, struct ecs_world *w) {
	math_t mat = math3d_make_srt(math3d, s.s, s.r, s.t);
	if (!math_isnull(s.mat)) {
		mat = math3d_mul_matrix(math3d, mat, s.mat);
	}
	if (s.parent != 0) {
		auto parentmat = worldmats.find(s.parent);
		if (!parentmat) {
			if (w) {
				if ((ecs::eid)s.parent >= id)
					return false;
				auto e = ecs_api::find_entity(w->ecs, (ecs::eid)s.parent);
				if (e.invalid()) {
					return false;
				}
				ecs::scene *ps = e.component<ecs::scene>();
				if (ps == nullptr) {
					return false;
				}
				parentmat = &ps->worldmat;
				worldmats.insert_or_assign(s.parent, ps->worldmat);
			} else {
				return false;
			}
		}
		mat = math3d_mul_matrix(math3d, *parentmat, mat);
	}
	math3d_update(math3d, s.worldmat, mat);
	worldmats.insert_or_assign(id, s.worldmat);
	return true;
}

#define MUTABLE_TICK 128

static int
entity_init(lua_State *L) {
	auto w = getworld(L);

	for (auto& e : ecs_api::select<ecs::INIT, ecs::scene>(w->ecs)) {
		if (!e.component<ecs::scene_update_once>())
			e.enable_tag<ecs::scene_needchange>();
		auto& s = e.get<ecs::scene>();
		s.movement = 0;
		e.enable_tag<ecs::scene_mutable>();
	}
	return 0;
}

static inline bool
is_constant(struct ecs_world *w, ecs::eid eid) {
	auto e = ecs_api::find_entity(w->ecs, eid);
	if (e.invalid()) {
		return false;
	}
	return !e.component<ecs::scene_mutable>();
}

static inline bool
is_changed(struct ecs_world *w, ecs::eid eid) {
	auto e = ecs_api::find_entity(w->ecs, eid);
	if (e.invalid()) {
		return false;
	}
	return e.component<ecs::scene_changed>();
}

static void
rebuild_mutable_set(struct ecs_world *w) {
	using namespace ecs_api::flags;
	for (auto& e : ecs_api::select<ecs::scene_update, ecs::scene_mutable(absent), ecs::scene>(w->ecs)) {
		auto& s = e.get<ecs::scene>();
		if (s.parent != 0 && is_changed(w, s.parent)) {
			e.enable_tag<ecs::scene_mutable>();
			e.enable_tag<ecs::scene_changed>();
		}
	}
}

static int
scene_changed(lua_State *L) {
	auto w = getworld(L);
	auto math3d = w->math3d->M;
	math3d_checkpoint cp(math3d);

	size_t UpdateOnceCount = ecs_api::count<ecs::scene_update_once>(w->ecs);
	if (UpdateOnceCount > 0) {
		flatmap<ecs::eid, math_t> worldmats;
		worldmats.reserve(UpdateOnceCount);
		for (auto& e : ecs_api::select<ecs::scene_update_once, ecs::scene, ecs::eid>(w->ecs)) {
			auto& s = e.get<ecs::scene>();
			auto id = e.get<ecs::eid>();
			e.disable_tag<ecs::scene_update>();
			e.enable_tag<ecs::scene_changed>();
			if (!worldmat_update(worldmats, math3d, s, id, nullptr)) {
				return luaL_error(L, "entity(%d)'s parent(%d) cannot be found.", id, s.parent);
			}
		}
		ecs_api::clear_type<ecs::scene_update_once>(w->ecs);
	}

	// step.1
	auto selector = ecs_api::select<ecs::scene_needchange, ecs::scene_update>(w->ecs);
	auto it = selector.begin();
	if (it == selector.end()) {
		return 0;
	}
	bool need_rebuild_mutable_set = false;
	for (; it != selector.end(); ++it) {
		auto& e = *it;
		if (!e.component<ecs::scene_mutable>()) {
			need_rebuild_mutable_set = true;
			e.enable_tag<ecs::scene_mutable>();
		}
		e.enable_tag<ecs::scene_changed>();
		// disable main key must at the end
		e.disable_tag<ecs::scene_needchange>();
	}
	if (need_rebuild_mutable_set) {
		rebuild_mutable_set(w);
	}

	// step.2
	flatmap<ecs::eid, math_t> worldmats;
	for (auto& e : ecs_api::select<ecs::scene_mutable, ecs::scene, ecs::eid>(w->ecs)) {
		auto& s = e.get<ecs::scene>();
		bool changed = false;
		ecs::eid id = e.get<ecs::eid>();
		if (e.component<ecs::scene_changed>()) {
			changed = true;
		} else if (s.parent != 0 && is_changed(w, s.parent)) {
			e.enable_tag<ecs::scene_changed>();
			changed = true;
		}
		if (changed) {
			if (!worldmat_update(worldmats, math3d, s, id, w)) {
				return luaL_error(L, "entity(%d)'s parent(%d) cannot be found.", id, s.parent);
			}
			s.movement = w->frame;
		} else if (w->frame - s.movement > MUTABLE_TICK &&
			(s.parent == 0 || is_constant(w, s.parent))) {
			e.disable_tag<ecs::scene_mutable>();
		}
	}

	++w->frame;

	return 0;
}

// TODO: change stage name
static int
prefab_remove(lua_State *L) {
	auto w = getworld(L);
	ecs_api::clear_type<ecs::scene_changed>(w->ecs);
	return 0;
}

static int
scene_remove(lua_State *L) {
	auto w = getworld(L);
	flatset<ecs::eid> removed;
	for (auto& e : ecs_api::select<ecs::REMOVED, ecs::scene, ecs::eid>(w->ecs)) {
		auto id = e.get<ecs::eid>();
		removed.insert(id);
	}
	if (removed.empty()) {
		return 0;
	}
	for (auto& e : ecs_api::select<ecs::scene>(w->ecs)) {
		auto& s = e.get<ecs::scene>();
		if (s.parent != 0 && removed.contains(s.parent)) {
			auto id = e.component<ecs::eid>();
			removed.insert(id);
			e.remove();
		}
	}
	return 0;
}

static int
bounding_update(lua_State *L){
	auto w = getworld(L);
	auto math3d = w->math3d->M;
	math3d_checkpoint cp(math3d);
	for (auto& e : ecs_api::select<ecs::scene_changed, ecs::bounding, ecs::scene>(w->ecs)){
		auto &b = e.get<ecs::bounding>();
		if (math_isnull(b.aabb))
			continue;
		const auto &s = e.get<ecs::scene>();
		const math_t aabb = math3d_aabb_transform(math3d, s.worldmat, b.aabb);
		math3d_update(math3d, b.scene_aabb, aabb);
	}
	return 0;
}

extern "C" int
luaopen_system_scene(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "entity_init", entity_init },
		{ "scene_changed", scene_changed },
		{ "prefab_remove", prefab_remove },
		{ "scene_remove", scene_remove },
		{ "bounding_update", bounding_update},
		{ NULL, NULL },
	};
	luaL_newlibtable(L,l);
	lua_pushnil(L);
	luaL_setfuncs(L,l,1);
	return 1;
}
