module kraken::utils {

    // === vector ===
use std::debug::print;
    public fun contains_any<Element: drop>(
        v: &vector<Element>, 
        mut e: vector<Element>
    ): bool {
        print(v);
        print(&e);
        if (v.is_empty()) return false;
        while (!e.is_empty()) {
            if (v.contains(&e.pop_back())) return true;
        };
        false
    }

    // === VecMap ===

    use sui::vec_map::{Self, VecMap};

    public fun map_from_keys<K: copy + drop, V: copy + drop>(
        keys: vector<K>,
        value: V,
    ): VecMap<K, V> {
        let mut map = vec_map::empty<K, V>();
        keys.do!(|key| {
            map.insert(key, value);
        });
        map
    }

    public fun map_append<K: copy, V>(
        map: &mut VecMap<K, V>, 
        mut other: VecMap<K, V>,
    ) {
        while (!other.is_empty()) {
            let (key, value) = other.remove_entry_by_idx(0);
            map.insert(key, value);
        };
        other.destroy_empty();
    }

    public fun map_remove_keys<K: copy + drop, V: drop>(
        map: &mut VecMap<K, V>, 
        mut keys: vector<K>,
    ) {
        while (!keys.is_empty()) {
            let key = keys.pop_back();
            map.remove(&key);
        };
    }

    public macro fun map_set_or<$K, $V>(
        $map: &mut VecMap<$K, $V>, 
        $key: $K,
        $value: $V,
        $f: |&mut $V|
    ) {
        let map = $map;
        let key = $key;
        if (map.contains(&key)) {
            $f(map.get_mut(&key));
        } else {
            map.insert($key, $value);
        };
    }

    public macro fun map_do_mut<$K, $V>(
        $map: &mut VecMap<$K, $V>, 
        $f: |$K, $V|,
    ) {
        let map = $map;
        let mut i = 0;
        while (i < map.size()) {
            let (key, value) = map.get_entry_by_idx_mut(i);
            $f(key, value);
            i = i + 1;
        };
    }
}