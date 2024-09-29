/// This module handles the authentication:
/// - for proposal and actions execution (proposals should be destroyed by the module that created them)
/// - for roles and associated approval & threshold (roles are derived from the witness and an optional name)
/// - for objects managing assets (treasuries, kiosks, etc)
/// as well as the verification of the dependencies (which are whitelisted in AccountExtensions)
/// 
/// A role is defined as a TypeName + an optional name
/// -> package_id::module_name::struct_name::name or package_id::module_name::struct_name

module account_protocol::auth;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};
use account_protocol::{
    deps::Deps,
};

// === Errors ===

const EWrongWitness: u64 = 0;
const EWrongAccount: u64 = 1;
const EWrongVersion: u64 = 2;
const ENotCoreDep: u64 = 3;
const ENotDep: u64 = 4;

// === Structs ===

/// Protected type ensuring provenance
public struct Auth has store, drop {
    // type_name of the witness that instantiated the auth
    witness: TypeName,
    // name of the auth (can be empty)
    name: String,
    // address of the account that created the auth
    accout_addr: address,
}

// === Public Functions ===

/// Constructs an auth from a Witness, an (optional) name and a account id
public fun construct<W: drop>(_: W, name: String, accout_addr: address): Auth {
    let witness = type_name::get<W>();
    Auth { witness, name, accout_addr }
}

/// Used by modules to execute an action
public fun assert_is_witness<W: drop>(auth: &Auth, _: W) {
    let witness = type_name::get<W>();
    assert!(auth.witness == witness, EWrongWitness);
}

/// Asserts that the dependency is the expected version
public fun assert_version(deps: &Deps, auth: &Auth, version: u64) {
    let witness_package = auth.witness.get_address().to_string();
    assert!(deps.get_package_version_from_string(witness_package) == version, EWrongVersion);
}

/// Asserts that the auth has been issued from kraken (account or actions) packages
public fun assert_dep<W: copy + drop>(deps: &Deps, _: W) {
    let witness_package = type_name::get<W>().get_address().to_string();
    assert!(deps.contains(witness_package), ENotDep);
}

/// Asserts that the auth has been issued from kraken core (account or actions) packages
public fun assert_core_dep<W: copy + drop>(deps: &Deps, _: W) {
    let witness_package = type_name::get<W>().get_address().to_string();
    assert!(
        deps.get_package_idx_from_string(witness_package) == 0 ||
        deps.get_package_idx_from_string(witness_package) == 1, 
        ENotCoreDep
    );
}

/// Verifies that the action is executed for the account that approved it
public fun assert_is_account(auth: &Auth, accout_addr: address) {
    assert!(auth.accout_addr == accout_addr, EWrongAccount);
}

/// Converts an auth into a role
/// role is package::module::struct::name or package::module::struct
public fun into_role(auth: &Auth): String {
    let mut auth_to_role = auth.witness.into_string().to_string();
    if (!auth.name.is_empty()) {
        auth_to_role.append_utf8(b"::");  
        auth_to_role.append(auth.name);
    };
    auth_to_role
}

// === View Functions ===

public fun witness(auth: &Auth): TypeName {
    auth.witness
}

public fun name(auth: &Auth): String {
    auth.name
}

public fun accout_addr(auth: &Auth): address {
    auth.accout_addr
}