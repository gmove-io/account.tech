module kraken_multisig::deps {
    use std::string::String;

    public use fun kraken_multisig::auth::assert_core_dep as Deps.assert_core_dep;

    // === Errors ===

    const EInvalidDeps: u64 = 1;

    // === Structs ===

    public struct Deps has store {
        contents: vector<Dep>,
    }

    public struct Dep has store, drop {
        package: String,
        version: u64,
    }

    // === Public functions ===

    public fun version(deps: &Deps, package: String): u64 {
        let idx = deps.get_idx(package);
        deps.contents[idx].version
    }

    public fun get_idx(deps: &Deps, package: String): u64 {
        let mut i = 0;
        deps.contents.do_ref!(|dep| {
            if (dep.package == package) return;
            i = i + 1;
        });
        
        i
    }

    // === Package functions ===

    public(package) fun from_keys_values(
        mut packages: vector<String>, 
        mut versions: vector<u64>
    ): Deps {
        assert!(packages.length() == versions.length(), EInvalidDeps);
        versions.reverse();
        let contents = packages.map!(|package| {
            Dep { package, version: versions.pop_back() }
        });

        Deps { contents }
    }

    public(package) fun add(deps: &mut Deps, package: String, version: u64) {
        deps.contents.push_back(Dep { package, version });
    }

    public(package) fun edit(deps: &mut Deps, package: String, version: u64) {
        let idx = deps.get_idx(package);
        deps.contents[idx].version = version;
    }

    public(package) fun remove(deps: &mut Deps, package: String) {
        let idx = deps.get_idx(package);
        deps.contents.remove(idx);
    }
}
