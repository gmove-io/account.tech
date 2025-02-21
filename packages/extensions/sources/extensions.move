/// The Extensions shared object tracks a list of verified and whitelisted packages.
/// These are the only packages that can be added as dependencies to an account if it disallows unverified packages.

module account_extensions::extensions;

// === Imports ===

use std::string::String;

// === Errors ===

const EExtensionNotFound: u64 = 0;
const EExtensionAlreadyExists: u64 = 1;
const ECannotRemoveAccountProtocol: u64 = 2;

// === Structs ===

/// A list of verified and whitelisted packages
public struct Extensions has key {
    id: UID,
    inner: vector<Extension>,
}

/// A package with a name and all authorized versions
public struct Extension has copy, drop, store {
    name: String,
    history: vector<History>,
}

/// The address and version of a package
public struct History has copy, drop, store {
    addr: address,
    version: u64,
}

/// A capability to add and remove extensions
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

/// Returns the number of extensions in the list
public fun length(extensions: &Extensions): u64 {
    extensions.inner.length()
}

/// Returns the extension at the given index
public fun get_by_idx(extensions: &Extensions, idx: u64): &Extension {
    &extensions.inner[idx]
}

/// Returns the name of the extension
public fun name(extension: &Extension): String {
    extension.name
}

/// Returns the history of the extension
public fun history(extension: &Extension): vector<History> {
    extension.history
}

/// Returns the address of the history
public fun addr(history: &History): address {
    history.addr
}

/// Returns the version of the history
public fun version(history: &History): u64 {
    history.version
}

/// Returns the latest address and version for a given name
public fun get_latest_for_name(
    extensions: &Extensions, 
    name: String, 
): (address, u64) {
    let idx = get_idx_for_name(extensions, name);
    let history = extensions.inner[idx].history;
    let last_idx = history.length() - 1;

    (history[last_idx].addr, history[last_idx].version)
}

/// Returns true if the package (name, addr, version) is in the list
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

// === Admin functions ===

/// Adds a package to the list
public fun add(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {    
    assert!(!extensions.inner.any!(|extension| extension.name == name), EExtensionAlreadyExists);
    assert!(!extensions.inner.any!(|extension| extension.history.any!(|h| h.addr == addr)), EExtensionAlreadyExists);
    let extension = Extension { name, history: vector[History { addr, version }] };
    extensions.inner.push_back(extension);
}

/// Removes a package from the list
public fun remove(extensions: &mut Extensions, _: &AdminCap, name: String) {
    let idx = extensions.get_idx_for_name(name);
    assert!(idx > 0, ECannotRemoveAccountProtocol);
    extensions.inner.remove(idx);
}

/// Adds a new version to the history of a package
public fun update(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {
    let idx = extensions.get_idx_for_name(name);
    extensions.inner[idx].history.push_back(History { addr, version });
}

// === Private functions ===

fun get_idx_for_name(extensions: &Extensions, name: String): u64 {
    let opt = extensions.inner.find_index!(|extension| extension.name == name);
    assert!(opt.is_some(), EExtensionNotFound);
    opt.destroy_some()
}

// === Test functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}