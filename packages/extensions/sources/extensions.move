module account_extensions::extensions;

use std::string::String;

// === Errors ===

#[error]
const EExtensionNotFound: vector<u8> = b"Extension not found";
#[error]
const EExtensionAlreadyExists: vector<u8> = b"Extension already exists";
#[error]
const ECannotRemoveAccountProtocol: vector<u8> = b"Cannot remove AccountProtocol";

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

public fun length(extensions: &Extensions): u64 {
    extensions.inner.length()
}

public fun get_by_idx(extensions: &Extensions, idx: u64): &Extension {
    &extensions.inner[idx]
}

public fun name(extension: &Extension): String {
    extension.name
}

public fun history(extension: &Extension): vector<History> {
    extension.history
}

public fun addr(history: &History): address {
    history.addr
}

public fun version(history: &History): u64 {
    history.version
}

public fun get_latest_for_name(
    extensions: &Extensions, 
    name: String, 
): (address, u64) {
    let idx = get_idx_for_name(extensions, name);
    let history = extensions.inner[idx].history;
    let last_idx = history.length() - 1;

    (history[last_idx].addr, history[last_idx].version)
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

// === Admin functions ===

public fun add(extensions: &mut Extensions, _: &AdminCap, name: String, addr: address, version: u64) {    
    assert!(!extensions.inner.any!(|extension| extension.name == name), EExtensionAlreadyExists);
    assert!(!extensions.inner.any!(|extension| extension.history.any!(|h| h.addr == addr)), EExtensionAlreadyExists);
    let extension = Extension { name, history: vector[History { addr, version }] };
    extensions.inner.push_back(extension);
}

public fun remove(extensions: &mut Extensions, _: &AdminCap, name: String) {
    let idx = extensions.get_idx_for_name(name);
    assert!(idx > 0, ECannotRemoveAccountProtocol);
    extensions.inner.remove(idx);
}

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