module kraken_multisig::deps;

use std::string::String;
use kraken_extensions::extensions::Extensions;

public use fun kraken_multisig::auth::assert_core_dep as Deps.assert_core_dep;
public use fun kraken_multisig::auth::assert_dep as Deps.assert_dep;
public use fun kraken_multisig::auth::assert_version as Deps.assert_version;

// === Errors ===

const EDepNotFound: u64 = 0;

// === Structs ===

public struct Deps has store, drop {
    inner: vector<Dep>,
}

public struct Dep has copy, store, drop {
    name: String,
    package: address,
    version: u64,
}

// === Public functions ===

public fun new(extensions: &Extensions): Deps {
    let (packages, versions) = extensions.get_latest_core_deps();
    let mut inner = vector[];

    inner.push_back(new_dep(extensions, b"KrakenMultisig".to_string(), packages[0], versions[0]));
    inner.push_back(new_dep(extensions, b"KrakenActions".to_string(), packages[1], versions[1]));

    Deps { inner }
}

// protected because &mut Deps accessible only from KrakenMultisig and KrakenActions
public fun new_dep(
    extensions: &Extensions,
    name: String,
    package: address, 
    version: u64, 
): Dep {
    extensions.assert_extension_exists(name, package, version);
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
    let opt = deps.inner.find_index!(|dep| dep.package.to_string() == package);
    assert!(opt.is_some(), EDepNotFound);
    opt.destroy_some()
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