/// Dependencies are all the packages that an Account object can use.
/// They are stored in a vector and can be updated only upon approval by members.
/// AccountProtocol and AccountActions can be found at index 0 and 1.
/// 
/// Not all packages are allowed to be used by a Account.
/// The list of whitelisted packages is stored in the AccountExtensions package.

module account_protocol::deps;

// === Imports ===

use std::{
    type_name,
    string::String
};
use sui::address;
use account_extensions::extensions::Extensions;

// === Errors ===

const EDepNotFound: u64 = 0;
const EDepAlreadyExists: u64 = 1;
const ENotDep: u64 = 2;
const ENotCoreDep: u64 = 3;

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
    addr: address,
    // version of the package
    version: u64,
}

// === Public functions ===

/// Creates a new Deps struct with the core dependencies
public fun new(extensions: &Extensions): Deps {
    let (addresses, versions) = extensions.get_latest_core_deps();
    let mut inner = vector[];

    inner.push_back(Dep { 
        name: b"AccountProtocol".to_string(), 
        addr: addresses[0], 
        version: versions[0] 
    });
    inner.push_back(Dep { 
        name: b"AccountActions".to_string(), 
        addr: addresses[1], 
        version: versions[1] 
    });

    Deps { inner }
}

/// Protected because &mut Deps is only accessible from AccountProtocol and AccountActions
public fun add(
    deps: &mut Deps,
    extensions: &Extensions,
    name: String,
    addr: address, 
    version: u64
) {
    assert!(!contains_name(deps, name), EDepAlreadyExists);
    assert!(!contains_addr(deps, addr), EDepAlreadyExists);
    extensions.assert_is_extension(name, addr, version);

    deps.inner.push_back(Dep { name, addr, version });
}

// === View functions ===

/// Asserts that the auth has been issued from kraken (account or actions) packages
public fun assert_is_dep<W: drop>(deps: &Deps, _: W) {
    let witness_package = address::from_bytes(type_name::get<W>().get_address().into_bytes());
    assert!(deps.contains_addr(witness_package), ENotDep);
}

/// Asserts that the auth has been issued from kraken core (account or actions) packages
public fun assert_is_core_dep<W: drop>(deps: &Deps, _: W) {
    let witness_package = address::from_bytes(type_name::get<W>().get_address().into_bytes());
    let idx = deps.get_idx_for_addr(witness_package);
    assert!(idx == 0 || idx == 1 || idx == 2, ENotCoreDep);
}

public fun get_from_name(deps: &Deps, name: String): &Dep {
    let opt = deps.inner.find_index!(|dep| dep.name == name);
    assert!(opt.is_some(), EDepNotFound);
    let idx = opt.destroy_some();

    &deps.inner[idx]
}

public fun get_from_addr(deps: &Deps, addr: address): &Dep {
    let opt = deps.inner.find_index!(|dep| dep.addr == addr);
    assert!(opt.is_some(), EDepNotFound);
    let idx = opt.destroy_some();
    
    &deps.inner[idx]
}

public fun get_idx_for_addr(deps: &Deps, addr: address): u64 {
    let opt = deps.inner.find_index!(|dep| dep.addr == addr);
    assert!(opt.is_some(), EDepNotFound);
    opt.destroy_some()
}

public fun name(dep: &Dep): String {
    dep.name
}

public fun addr(dep: &Dep): address {
    dep.addr
}

public fun version(dep: &Dep): u64 {
    dep.version
}

public fun contains_name(deps: &Deps, name: String): bool {
    deps.inner.any!(|dep| dep.name == name)
}

public fun contains_addr(deps: &Deps, addr: address): bool {
    deps.inner.any!(|dep| dep.addr == addr)
}

// === Test functions ===

// #[test_only]
// public fun update(deps: &mut Deps, package: address, version: u64) {
//     let idx = deps.get_idx(package);
//     deps.inner[idx].version = version;
// }

// #[test_only]
// public fun remove(deps: &mut Deps, package: address) {
//     let idx = deps.get_idx(package);
//     deps.inner.remove(idx);
// }