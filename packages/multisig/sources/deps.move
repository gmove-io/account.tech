module kraken_multisig::deps;
use std::string::String;

public use fun kraken_multisig::auth::assert_core_dep as Deps.assert_core_dep;
public use fun kraken_multisig::auth::assert_dep as Deps.assert_dep;
public use fun kraken_multisig::auth::assert_version as Deps.assert_version;

// === Errors ===

const EDepNotFound: u64 = 0;
const EInvalidDeps: u64 = 1;
const ENotCoreDeps: u64 = 2;
const ENotKrakenMultisig: u64 = 3;

// === Structs ===

public struct Deps has store, drop {
    inner: vector<Dep>,
}

public struct Dep has copy, store, drop {
    package: address,
    version: u64,
    name: String,
}

// === Public functions ===

public fun from_vecs(
    packages: vector<address>, 
    mut versions: vector<u64>,
    mut names: vector<String>
): Deps {
    assert!(
        packages.length() == versions.length() && 
        packages.length() == names.length(), 
        EInvalidDeps
    );
    assert!(
        names[0] == b"KrakenMultisig".to_string() && 
        names[1] == b"KrakenActions".to_string(),
        ENotCoreDeps
    );
    assert!(
        packages[0] == @kraken_multisig,
        ENotKrakenMultisig
    );

    let inner = packages.map!(|package| {
        Dep { package, version: versions.remove(0), name: names.remove(0) }
    });

    Deps { inner }
}

// protected because &mut Deps accessible only from KrakenMultisig and KrakenActions
public fun new_dep(package: address, version: u64, name: String): Dep {
    Dep { package, version, name }
}

public fun add(deps: &mut Deps, dep: Dep) {
    deps.inner.push_back(dep);
}

// === View functions ===

public fun get_version(deps: &Deps, package: address): u64 {
    let idx = deps.get_idx(package);
    deps.inner[idx].version
}

public fun get_idx(deps: &Deps, package: address): u64 {
    let opt = deps.inner.find_index!(|dep| dep.package == package);
    assert!(opt.is_some(), EDepNotFound);
    opt.destroy_some()
}

public fun contains(deps: &Deps, package: String): bool {
    deps.inner.any!(|dep| dep.package.to_string() == package)
}

// === Package functions ===

public(package) fun get_package_version_from_string(deps: &Deps, package: String): u64 {
    let idx = deps.get_package_idx_from_string(package);
    deps.inner[idx].version
}

public(package) fun get_package_idx_from_string(deps: &Deps, package: String): u64 {
    deps.inner.find_index!(|dep| dep.package.to_string() == package).destroy_some()
}

// === Test functions ===

#[test_only]
public fun update(deps: &mut Deps, package: address, version: u64) {
    let idx = deps.get_idx(package);
    deps.inner[idx].version = version;
}

#[test_only]
public fun remove(deps: &mut Deps, package: address) {
    let idx = deps.get_idx(package);
    deps.inner.remove(idx);
}