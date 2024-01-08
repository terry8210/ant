#pragma once

#include <core/ID.h>
#include <css/PropertyVector.h>
#include <css/StyleCache.h>
#include <unordered_map>
#include <vector>

namespace Rml {

class Element;
class StyleSheetNode;

struct AnimationKey {
	AnimationKey(float time, PropertyId id, const Property& value)
		: time(time)
		, prop { PropertyView { id, value } } {
		prop.AddRef();
	}
	float time;
	PropertyRef prop;
};

using Keyframe = std::vector<AnimationKey>;
using Keyframes = std::map<PropertyId, Keyframe>;

class StyleSheet {
public:
	StyleSheet();
	~StyleSheet();
	StyleSheet(const StyleSheet&) = delete;
	StyleSheet& operator=(const StyleSheet&) = delete;
	void Merge(const StyleSheet& sheet);
	void AddNode(StyleSheetNode && node);
	void AddKeyframe(const std::string& identifier, const std::vector<float>& rule_values, const PropertyVector& properties);
	void Sort();
	const Keyframes* GetKeyframes(const std::string& name) const;
	Style::TableCombination GetElementDefinition(const Element* element) const;

private:
	std::vector<StyleSheetNode> stylenode;
	std::unordered_map<std::string, Keyframes> keyframes;
};

}
