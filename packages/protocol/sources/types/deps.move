/// Dependencies are all the packages that an Account object can use.
/// They are stored in a vector and can be updated only upon approval by members.
/// AccountProtocol and AccountActions can be found at index 0 and 1.
/// 
/// Not all packages are allowed to be used by a Account.
/// The list of whitelisted packages is stored in the AccountExtensions package.

module account_protocol::deps;

// === Imports ===

use std::string::String;
use account_extensions::extensions::Extensions;
use account_protocol::version_witness::VersionWitness;

// === Errors ===

#[error]
const EDepNotFound: vector<u8> = b"Dependency not found in the account";
#[error]
const EDepAlreadyExists: vector<u8> = b"Dependency already exists in the account";
#[error]
const ENotDep: vector<u8> = b"Version package is not a dependency";
#[error]
const ENotExtension: vector<u8> = b"Package is not an extension";
#[error]
const EAccountProtocolMissing: vector<u8> = b"AccountProtocol is missing";
#[error]
const EDepsNotSameLength: vector<u8> = b"Invalid dependencies";

// === Structs ===

/// Parent struct protecting the deps
public struct Deps has copy, drop, store {
    inner: vector<Dep>,
    // can community extensions be added
    unverified_allowed: bool,
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
public fun new(
    extensions: &Extensions,
    unverified_allowed: bool,
    names: vector<String>,
    addresses: vector<address>,
    mut versions: vector<u64>,
): Deps {
    let (addr, version) = extensions.get_latest_for_name(b"AccountProtocol".to_string());
    assert!(extensions.is_extension(b"AccountProtocol".to_string(), addr, version), EAccountProtocolMissing);
    assert!(names.length() == addresses.length() && addresses.length() == versions.length(), EDepsNotSameLength);

    let mut inner = vector<Dep>[];

    names.zip_do!(addresses, |name, addr| {
        let version = versions.remove(0);
        
        assert!(!inner.any!(|dep| dep.name == name), EDepAlreadyExists);
        assert!(!inner.any!(|dep| dep.addr == addr), EDepAlreadyExists);
        if (!unverified_allowed) 
            assert!(extensions.is_extension(name, addr, version), ENotExtension);

        inner.push_back(Dep { name, addr, version });
    });

    Deps { inner, unverified_allowed }
}

public fun toggle_unverified_allowed(deps: &mut Deps) {
    deps.unverified_allowed = !deps.unverified_allowed;
}

// === View functions ===

public fun check(deps: &Deps, version_witness: VersionWitness) {
    assert!(deps.contains_addr(version_witness.package_addr()), ENotDep);
}

public fun unverified_allowed(deps: &Deps): bool {
    deps.unverified_allowed
}

public fun get_by_idx(deps: &Deps, idx: u64): &Dep {
    &deps.inner[idx]
}

public fun get_by_name(deps: &Deps, name: String): &Dep {
    let opt = deps.inner.find_index!(|dep| dep.name == name);
    assert!(opt.is_some(), EDepNotFound);
    let idx = opt.destroy_some();

    &deps.inner[idx]
}

public fun get_by_addr(deps: &Deps, addr: address): &Dep {
    let opt = deps.inner.find_index!(|dep| dep.addr == addr);
    assert!(opt.is_some(), EDepNotFound);
    let idx = opt.destroy_some();
    
    &deps.inner[idx]
}

// public fun get_idx_for_addr(deps: &Deps, addr: address): u64 {
//     let opt = deps.inner.find_index!(|dep| dep.addr == addr);
//     assert!(opt.is_some(), EDepNotFound);
//     opt.destroy_some()
// }

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

#[test_only]
public fun add_for_testing(deps: &mut Deps, extensions: &Extensions, name: String, addr: address, version: u64) {
    assert!(!deps.inner.any!(|dep| dep.name == name), EDepAlreadyExists);
    assert!(!deps.inner.any!(|dep| dep.addr == addr), EDepAlreadyExists);
    if (!deps.unverified_allowed) 
        assert!(extensions.is_extension(name, addr, version), ENotExtension);

    deps.inner.push_back(Dep { name, addr, version });
}
