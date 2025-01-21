module account_extensions::extensions;

use std::string::String;

// === Errors ===

#[error]
const EExtensionNotFound: vector<u8> = b"Extension not found";
#[error]
const EExtensionAlreadyExists: vector<u8> = b"Extension already exists";
#[error]
const ECannotRemoveCoreDep: vector<u8> = b"Cannot remove core dependency";

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
    let account_last_idx = account_history.length() - 1;
    addresses.push_back(account_history[account_last_idx].addr);
    versions.push_back(account_history[account_last_idx].version);

    let config_history = extensions.inner[1].history;
    let config_last_idx = config_history.length() - 1;
    addresses.push_back(config_history[config_last_idx].addr);
    versions.push_back(config_history[config_last_idx].version);

    // packages[0] & versions[0] are AccountProtocol
    // packages[1] & versions[1] are AccountConfig
    (addresses, versions)
}

/// Returns the package addresses for core dependencies
public fun get_core_deps_addresses(
    extensions: &Extensions
): (vector<address>) {
    let account_packages = extensions.inner[0].history.map!(|entry| entry.addr);
    let config_packages = extensions.inner[1].history.map!(|entry| entry.addr);

    let mut addresses = vector[];
    addresses.append(account_packages);
    addresses.append(config_packages);
    
    addresses
}

public fun is_extension(
    extensions: &Extensions, 
    name: String,
    addr: address,
    version: u64,
): bool {
    let opt_idx = extensions.inner.find_index!(|extension| extension.name == name);
    if (opt_idx.is_none()) return false;

    let idx = opt_idx.destroy_some();
    extensions.inner[idx].history.any!(|extension| extension.addr == addr) &&
    extensions.inner[idx].history.any!(|extension| extension.version == version)
}

public fun get_idx_for_name(extensions: &Extensions, name: String): u64 {
    let opt = extensions.inner.find_index!(|extension| extension.name == name);
    assert!(opt.is_some(), EExtensionNotFound);
    opt.destroy_some()
}

// === Admin functions ===

public fun add(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {    
    assert!(!extensions.inner.any!(|extension| extension.name == name), EExtensionAlreadyExists);
    assert!(!extensions.inner.any!(|extension| extension.history.any!(|h| h.addr == addr)), EExtensionAlreadyExists);
    let extension = Extension { name, history: vector[History { addr, version }] };
    extensions.inner.push_back(extension);
}

public fun remove(extensions: &mut Extensions, _: &AdminCap, name: String) {
    let idx = extensions.get_idx_for_name(name);
    assert!(idx > 1, ECannotRemoveCoreDep);
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