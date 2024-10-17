/// Dependencies are all the packages that an Account object can use.
/// They are stored in a vector and can be updated only upon approval by members.
/// AccountProtocol and AccountActions can be found at index 0 and 1.
/// 
/// Not all packages are allowed to be used by a Account.
/// The list of whitelisted packages is stored in the AccountExtensions package.

module account_protocol::deps;

// === Imports ===

use std::{
    type_name::TypeName,
    string::String
};
use sui::{
    address,
    package::UpgradeCap,
    hex,
};
use account_extensions::extensions::Extensions;

// === Errors ===

#[error]
const EDepNotFound: vector<u8> = b"Dependency not found in the account";
#[error]
const EDepAlreadyExists: vector<u8> = b"Dependency already exists in the account";
#[error]
const ENotDep: vector<u8> = b"Version package is not a dependency";
#[error]
const ENotCoreDep: vector<u8> = b"Version package is not a core dependency";
#[error]
const EWrongUpgradeCap: vector<u8> = b"Upgrade cap is not the same as the package";

// === Structs ===

/// Parent struct protecting the deps
public struct Deps has copy, drop, store {
    inner: vector<Dep>,
}

/// Child struct storing the name, package and version of a dependency
public struct Dep has copy, drop, store {
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
        name: b"AccountConfig".to_string(), 
        addr: addresses[1], 
        version: versions[1] 
    });
    inner.push_back(Dep { 
        name: b"AccountActions".to_string(), 
        addr: addresses[2], 
        version: versions[2] 
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

/// Adds a dependency which is a package owned by a member
public fun add_with_upgrade_cap(
    deps: &mut Deps,
    upgrade_cap: &UpgradeCap,
    name: String,
    addr: address, 
    version: u64
) {
    assert!(!contains_name(deps, name), EDepAlreadyExists);
    assert!(!contains_addr(deps, addr), EDepAlreadyExists);
    assert!(upgrade_cap.package() == addr.to_id(), EWrongUpgradeCap);

    deps.inner.push_back(Dep { name, addr, version });
}

// === View functions ===

/// Asserts that the Version witness type has been issued from one of the Account dependencies
public fun assert_is_dep(deps: &Deps, version_type: TypeName) {
    let package = address::from_bytes(hex::decode(version_type.get_address().into_bytes()));
    assert!(deps.contains_addr(package), ENotDep);
}

/// Asserts that the Version witness type is instantiated from AccountProtocol AccountConfig or AccountActions
public fun assert_is_core_dep(deps: &Deps, version_type: TypeName) {
    let package = address::from_bytes(hex::decode(version_type.get_address().into_bytes()));
    let idx = deps.get_idx_for_addr(package);
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

public fun length(deps: &Deps): u64 {
    deps.inner.length()
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