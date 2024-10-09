module account_extensions::extensions;

use std::string::String;

// === Errors ===

const EExtensionNotFound: u64 = 0;
const ENotCoreDep: u64 = 1;

// === Structs ===

// shared object
public struct Extensions has key {
    id: UID,
    inner: vector<Extension>,
}

public struct Extension has copy, drop, store {
    name: String,
    history: vector<History>,
}

public struct History has copy, drop, store {
    addr: address,
    version: u64,
}

public struct AdminCap has key {
    id: UID,
}

// === Public functions ===

fun init(ctx: &mut TxContext) {
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
    transfer::share_object(Extensions { 
        id: object::new(ctx),
        inner: vector::empty()  
    });
}

// === View functions ===

/// Returns the latest package addresses and versions for core dependencies
public fun get_latest_core_deps(
    extensions: &Extensions
): (vector<address>, vector<u64>) {
    let mut addresses = vector[];
    let mut versions = vector[];

    let account_history = extensions.inner[0].history;
    addresses.push_back(account_history[0].addr);
    versions.push_back(account_history[0].version);

    let config_history = extensions.inner[1].history;
    addresses.push_back(config_history[1].addr);
    versions.push_back(config_history[1].version);

    let actions_history = extensions.inner[2].history;
    addresses.push_back(actions_history[2].addr);
    versions.push_back(actions_history[2].version);

    // packages[0] & versions[0] are AccountProtocol
    // packages[1] & versions[1] are AccountConfig
    // packages[2] & versions[2] are AccountActions
    (addresses, versions)
}

/// Returns the package addresses for core dependencies
public fun get_core_deps_addresses(
    extensions: &Extensions
): (vector<address>) {
    let account_packages = extensions.inner[0].history.map!(|entry| entry.addr);
    let config_packages = extensions.inner[1].history.map!(|entry| entry.addr);
    let actions_packages = extensions.inner[2].history.map!(|entry| entry.addr);

    let mut addresses = vector[];
    addresses.append(account_packages);
    addresses.append(config_packages);
    addresses.append(actions_packages);
    
    addresses
}

public fun assert_is_extension(
    extensions: &Extensions, 
    name: String,
    addr: address,
    version: u64,
) {
    let idx = extensions.get_idx_for_name(name); // throws if not found
    assert!(
        extensions.inner[idx].history.any!(|extension| extension.addr == addr) &&
        extensions.inner[idx].history.any!(|extension| extension.version == version),
        EExtensionNotFound
    );
}

public fun assert_is_core_extension(extensions: &Extensions, addr: address) {
    let addresses = get_core_deps_addresses(extensions);
    assert!(addresses.contains(&addr), ENotCoreDep);
}

public fun get_idx_for_name(extensions: &Extensions, name: String): u64 {
    let opt = extensions.inner.find_index!(|extension| extension.name == name);
    assert!(opt.is_some(), EExtensionNotFound);
    opt.destroy_some()
}

// public fun get_from_name(extensions: &Extensions, name: String): &Extension {
//     let opt = extensions.inner.find_index!(|extension| extension.name == name);
//     assert!(opt.is_some(), EExtensionNotFound);
//     let idx = opt.destroy_some();

//     &extensions.inner[idx]
// }

// public fun get_from_addr(extensions: &Extensions, package: address): &Extension {
//     let opt = extensions.inner.find_index!(|extension| extension.package == package);
//     assert!(opt.is_some(), EExtensionNotFound);
//     let idx = opt.destroy_some();
    
//     &extensions.inner[idx]
// }

// /// Find if a package address exists in the whole Extensions object
// public fun addr_exists(extensions: &Extensions, addr: ascii::String): bool {
//     extensions.inner.any!(|ext| ext.history.any!(|h| h.package.to_ascii_string() == addr))
// }

// /// Find if a package name exists 
// public fun name_exists(extensions: &Extensions, name: String): bool {
//     extensions.inner.any!(|ext| ext.name == name)
// }

// /// Find if an address exists for a package name
// public fun package_exists(extensions: &Extensions, name: String, package: address): bool {
//     let history = get_history(extensions, name);
//     history.any!(|extension| extension.package == package)
// }

// /// Find if a version exists for a package name
// public fun version_exists(extensions: &Extensions, name: String, version: u64): bool {
//     let history = get_history(extensions, name);
//     history.any!(|extension| extension.version == version)
// }

// public fun assert_addr_exists(extensions: &Extensions, addr: ascii::String) {
//     assert!(addr_exists(extensions, addr), EPackageNotFound);
// }

// public fun assert_name_exists(extensions: &Extensions, name: String) {
//     assert!(name_exists(extensions, name), EExtensionNotFound);
// }

// public fun assert_package_exists(extensions: &Extensions, name: String, package: address) {
//     assert!(package_exists(extensions, name, package), EPackageNotFound);
// }

// public fun assert_version_exists(extensions: &Extensions, name: String, version: u64) {
//     assert!(version_exists(extensions, name, version), EWrongVersion);
// }

// public fun get_history(extensions: &Extensions, name: String): vector<History> {
//     let idx = extensions.get_idx_for_name(name);
//     extensions.inner[idx].history
// }

// public fun get_version(history: vector<History>, package: address): u64 {
//     let idx = get_idx_for_package(history, package);
//     history[idx].version
// }

// public fun get_idx_for_package(extensions: &Extensions, name: String, package: address): u64 {
//     let history = extensions.get_history(name);
//     let opt = history.find_index!(|extension| extension.package == package);
//     assert!(opt.is_some(), EPackageNotFound);
//     opt.destroy_some()
// }

// === Admin functions ===

public fun add(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {
    let extension = Extension { name, history: vector[History { addr, version }] };
    extensions.inner.push_back(extension);
}

public fun remove(extensions: &mut Extensions, _: &AdminCap, name: String) {
    let idx = extensions.get_idx_for_name(name);
    extensions.inner.remove(idx);
}

public fun update(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {
    let idx = extensions.get_idx_for_name(name);
    extensions.inner[idx].history.push_back(History { addr, version });
}

// === Test functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}