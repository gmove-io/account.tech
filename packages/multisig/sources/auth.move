/// This module handles the authentication:
/// - for proposal and actions execution
/// - for roles and associated approval & threshold 
/// - for objects managing assets (treasuries, kiosks, etc)
/// as well as the verification of 
/// 
/// A role is defined as a TypeName + an optional name
/// -> package_id::module_name::struct_name::name or package_id::module_name::struct_name

module kraken_multisig::auth;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};
use kraken_multisig::{
    deps::Deps,
};

// === Errors ===

const EWrongIssuer: u64 = 0;
const EWrongMultisig: u64 = 1;
const EWrongVersion: u64 = 2;
const ENotCoreDep: u64 = 3;

// === Structs ===

// protected type ensuring provenance
public struct Auth has store, drop {
    // type_name of the witness that instantiated the auth
    issuer: TypeName,
    // name of the auth (can be empty)
    name: String,
    // address of the multisig that created the auth
    multisig_addr: address,
}

// === Public Functions ===

// construct an auth from an Issuer, an (optional) name and a multisig id
public fun construct<I: drop>(_: I, name: String, multisig_addr: address): Auth {
    let issuer = type_name::get<I>();
    Auth { issuer, name, multisig_addr }
}

// to be used by modules to execute an action
public fun assert_is_issuer<I: drop>(auth: &Auth, _: I) {
    let issuer = type_name::get<I>();
    assert!(auth.issuer == issuer, EWrongIssuer);
}

public fun assert_version(deps: &Deps, auth: &Auth, version: u64) {
    let issuer_package = auth.issuer.get_address().to_string();
    assert!(deps.get_package_version_from_string(issuer_package) == version, EWrongVersion);
}

/// Assert that the auth has been issued from kraken (multisig or actions) packages
public fun assert_core_dep<I: copy + drop>(deps: &Deps, _: I) {
    let issuer_package = type_name::get<I>().get_address().to_string();
    assert!(
        deps.get_package_idx_from_string(issuer_package) == 0 ||
        deps.get_package_idx_from_string(issuer_package) == 1, 
        ENotCoreDep
    );
}

// verify that the action is executed for the multisig that approved it
public fun assert_is_multisig(auth: &Auth, multisig_addr: address) {
    assert!(auth.multisig_addr == multisig_addr, EWrongMultisig);
}

// role is package::module::struct::name or package::module::struct
public fun into_role(auth: &Auth): String {
    let mut auth_to_role = auth.issuer.into_string().to_string();
    if (!auth.name.is_empty()) {
        auth_to_role.append_utf8(b"::");  
        auth_to_role.append(auth.name);
    };
    auth_to_role
}

// === View Functions ===

public fun issuer(auth: &Auth): TypeName {
    auth.issuer
}

public fun name(auth: &Auth): String {
    auth.name
}

public fun multisig_addr(auth: &Auth): address {
    auth.multisig_addr
}