#pragma once

#include <core/ID.h>
#include <css/PropertyIdSet.h>
#include <css/Property.h>
#include <span>
#include <functional>

struct style_cache;

namespace Rml::Style {
    struct TableValue { int idx; };
    struct TableCombination { int idx; };
    struct TableValueOrCombination {
        TableValueOrCombination(TableValue o): idx(o.idx) {}
        TableValueOrCombination(TableCombination o): idx(o.idx) {}
        int idx;
    };

    class Cache {
    public:
        Cache(const PropertyIdSet& inherit);
        ~Cache();
        TableValue                 Create();
        TableValue                 Create(const PropertyVector& vec);
        TableCombination           Merge(const std::span<TableValue>& maps);
        TableCombination           Merge(TableValue A, TableValue B, TableValue C);
        TableCombination           Inherit(TableCombination child, TableCombination parent);
        TableCombination           Inherit(TableCombination child);
        void                       Release(TableValueOrCombination s);
        bool                       Assgin(TableValue to, TableCombination from);
        bool                       Compare(TableValue a, TableCombination b);
        void                       Clone(TableValue to, TableValue from);
        bool                       SetProperty(TableValue s, PropertyId id, const Property& value);
        bool                       DelProperty(TableValue s, PropertyId id);
        PropertyIdSet              SetProperty(TableValue s, const PropertyVector& vec);
        PropertyIdSet              DelProperty(TableValue s, const PropertyIdSet& set);
        Property                   Find(TableValueOrCombination s, PropertyId id);
        bool                       Has(TableValueOrCombination s, PropertyId id);
        void                       Foreach(TableValueOrCombination s, PropertyIdSet& set);
        void                       Foreach(TableValueOrCombination s, PropertyUnit unit, PropertyIdSet& set);
        PropertyIdSet              Diff(TableValueOrCombination a, TableValueOrCombination b);
        void                       Flush();
        Property                   CreateProperty(PropertyId id, std::span<uint8_t> value);
        PropertyId                 GetPropertyId(Property prop);
        std::span<const std::byte> GetPropertyData(Property prop);
        void                       PropertyAddRef(Property prop);
        void                       PropertyRelease(Property prop);

    private:
        style_cache* c;
    };

    void Initialise(const PropertyIdSet& inherit);
    void Shutdown();
    Cache& Instance();
}
