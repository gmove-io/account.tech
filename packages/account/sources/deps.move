/// Dependencies are all the packages that an Account object can use.
/// They are stored in a vector and can be updated only upon approval by members.
/// KrakenMultisig and KrakenActions can be found at index 0 and 1.
/// 
/// Not all packages are allowed to be used by a Account.
/// The list of whitelisted packages is stored in the KrakenExtensions package.

module kraken_account::deps;

// === Imports ===

use std::string::String;
use kraken_extensions::extensions::Extensions;

// === Aliases ===

public use fun kraken_account::auth::assert_core_dep as Deps.assert_core_dep;
public use fun kraken_account::auth::assert_dep as Deps.assert_dep;
public use fun kraken_account::auth::assert_version as Deps.assert_version;

// === Errors ===

const EDepNotFound: u64 = 0;

// === Structs ===

/// Parent struct protecting the deps
public struct Deps has store, drop {
    inner: vector<Dep>,
}

/// Child struct storing the name, package and version of a dependency
public struct Dep has copy, store, drop {
    // name of the package
    name: String,
    // id of the package
    package: address,
    // version of the package
    version: u64,
}

// === Public functions ===

/// Creates a new Deps struct with the core dependencies
public fun new(extensions: &Extensions): Deps {
    let (packages, versions) = extensions.get_latest_core_deps();
    let mut inner = vector[];

    inner.push_back(Dep { 
        name: b"KrakenAccount".to_string(), 
        package: packages[0], 
        version: versions[0] 
    });
    inner.push_back(Dep { 
        name: b"KrakenActions".to_string(), 
        package: packages[1], 
        version: versions[1] 
    });

    Deps { inner }
}

/// Protected because &mut Deps is only accessible from KrakenAccount and KrakenActions
public fun add(
    deps: &mut Deps,
    extensions: &Extensions,
    name: String,
    package: address, 
    version: u64
) {
    extensions.assert_extension_exists(name, package, version);
    deps.inner.push_back(Dep { name, package, version });
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