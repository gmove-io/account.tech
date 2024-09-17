module kraken_extensions::extensions;
use std::string::String;

// === Errors ===

const EExtensionNotFound: u64 = 0;
const EInvalidDeps: u64 = 1;
const EPackageNotFound: u64 = 2;
const EWrongVersion: u64 = 3;

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
    package: address,
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

public fun init_core_deps(
    _: &AdminCap,
    extensions: &mut Extensions,
    packages: vector<address>, 
) {
    assert!(packages.length() == 2, EInvalidDeps);

    extensions.add(b"KrakenMultisig".to_string(), packages[0], 1);
    extensions.add(b"KrakenActions".to_string(), packages[1], 1);
}

public fun add(extensions: &mut Extensions, name: String, package: address, version: u64) {
    let extension = Extension { name, history: vector[History { package, version }] };
    extensions.inner.push_back(extension);
}

// === View functions ===

public fun get_latest_core_deps(
    extensions: &Extensions
): (vector<address>, vector<u64>) {
    let mut packages = vector[];
    let mut versions = vector[];

    let multisig_history = get_history(extensions, b"KrakenMultisig".to_string());
    packages.push_back(multisig_history[0].package);
    versions.push_back(multisig_history[0].version);

    let actions_history = get_history(extensions, b"KrakenActions".to_string());
    packages.push_back(actions_history[0].package);
    versions.push_back(actions_history[0].version);

    (packages, versions)
}

public fun get_history(extensions: &Extensions, name: String): vector<History> {
    let idx = extensions.get_idx_for_history(name);
    extensions.inner[idx].history
}

public fun get_version(history: vector<History>, package: address): u64 {
    let idx = get_idx_for_package(history, package);
    history[idx].version
}

public fun get_idx_for_history(extensions: &Extensions, name: String): u64 {
    let opt = extensions.inner.find_index!(|dep| dep.name == name);
    assert!(opt.is_some(), EExtensionNotFound);
    opt.destroy_some()
}

public fun get_idx_for_package(history: vector<History>, package: address): u64 {
    let opt = history.find_index!(|dep| dep.package == package);
    assert!(opt.is_some(), EPackageNotFound);
    opt.destroy_some()
}

public fun contains_history(extensions: &Extensions, name: String): bool {
    extensions.inner.any!(|ext| ext.name == name)
}

public fun contains_version(history: vector<History>, package: address): bool {
    history.any!(|dep| dep.package == package)
}

public fun assert_extension_exists(
    extensions: &Extensions, 
    name: String,
    package: address,
    version: u64,
) {
    assert!(contains_history(extensions, name), EExtensionNotFound);
    assert!(contains_version(get_history(extensions, name), package), EPackageNotFound);
    assert!(get_version(get_history(extensions, name), package) == version, EWrongVersion);
}

// === Test functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}