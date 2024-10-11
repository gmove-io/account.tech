/// This module handles the authentication:
/// - for proposal and actions execution (proposals should be destroyed by the module that created them)
/// - for roles and associated approval & threshold (roles are derived from the role_type and an optional name)
/// - for objects managing assets (treasuries, kiosks, etc)
/// as well as the verification of the dependencies (which are whitelisted in AccountExtensions)
/// 
/// A role is defined as a TypeName + an optional name
/// -> package_id::module_name::struct_name::name or package_id::module_name::struct_name

module account_protocol::source;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};
use sui::address;
use account_protocol::deps::Deps;

// === Errors ===

const EWrongWitness: u64 = 0;
const EWrongAccount: u64 = 1;
const EWrongVersion: u64 = 2;

// === Structs ===

/// Protected type ensuring provenance
public struct Source has store, drop {
    // address of the account that created the source
    account_addr: address,
    /// type_name of the current package Version type
    version_type: TypeName,
    // type_name of the role_type that instantiated the source (proposal witness)
    role_type: TypeName,
    // name of the source (can be empty)
    role_name: String,
}

// === Public Functions ===

/// Verifies that the action is executed for the account that approved it
public fun assert_is_account(source: &Source, account_addr: address) {
    assert!(source.account_addr == account_addr, EWrongAccount);
}

/// Used by modules to execute an action
public fun assert_is_constructor<W: drop>(source: &Source, _: W) {
    let role_type = type_name::get<W>();
    assert!(source.role_type == role_type, EWrongWitness);
}

/// Asserts that the dependency is the expected version
public fun assert_is_dep_with_version(source: &Source, deps: &Deps, version: u64) {
    let version_package = address::from_bytes(source.version_type.get_address().into_bytes());
    assert!(deps.get_from_addr(version_package).version() == version, EWrongVersion);
}

/// Converts a source into a role
/// role is package::module::struct::name or package::module::struct
public fun full_role(source: &Source): String {
    let mut auth_to_role = source.role_type.into_string().to_string();
    if (!source.role_name.is_empty()) {
        auth_to_role.append_utf8(b"::");  
        auth_to_role.append(source.role_name);
    };
    auth_to_role
}

// === View Functions ===

public fun account_addr(source: &Source): address {
    source.account_addr
}

public fun version_type(source: &Source): TypeName {
    source.version_type
}

public fun role_type(source: &Source): TypeName {
    source.role_type
}

public fun role_name(source: &Source): String {
    source.role_name
}

// === Package functions ===

/// Constructs an source from a Witness, an (optional) name and a account id
public(package) fun construct<Version, Role>(
    account_addr: address,
    _version: Version, 
    _role: Role, 
    role_name: String, 
): Source {
    let version_type = type_name::get<Version>();
    let role_type = type_name::get<Role>();
    
    Source { account_addr, version_type, role_type, role_name }
}