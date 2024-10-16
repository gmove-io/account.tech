/// This module handles the authentication:
/// - for proposal and actions execution (proposals should be destroyed by the module that created them)
/// - for roles and associated approval & threshold (roles are derived from the role_type and an optional name)
/// - for objects managing assets (treasuries, kiosks, etc)
/// 
/// A role is defined as a TypeName + an optional name
/// -> package_id::module_name::struct_name::name or package_id::module_name::struct_name

module account_protocol::issuer;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};

// === Errors ===

#[error]
const EWrongWitness: vector<u8> = b"Witness is not the one used for creating the proposal";
#[error]
const EWrongAccount: vector<u8> = b"Account address doesn't match the issuer";

// === Structs ===

/// Protected type ensuring provenance
public struct Issuer has store, drop {
    // address of the account that created the issuer
    account_addr: address,
    // type_name of the role_type that instantiated the issuer (proposal witness)
    role_type: TypeName,
    // name of the issuer (can be empty)
    role_name: String,
}

// === Public Functions ===

/// Verifies that the action is executed for the account that approved it
public fun assert_is_account(issuer: &Issuer, account_addr: address) {
    assert!(issuer.account_addr == account_addr, EWrongAccount);
}

/// Used by modules to execute an action
public fun assert_is_constructor<W: drop>(issuer: &Issuer, _: W) {
    let role_type = type_name::get<W>();
    assert!(issuer.role_type == role_type, EWrongWitness);
}

/// Converts a issuer into a role
/// role is package::module::struct::name or package::module::struct
public fun full_role(issuer: &Issuer): String {
    let mut auth_to_role = issuer.role_type.into_string().to_string();
    if (!issuer.role_name.is_empty()) {
        auth_to_role.append_utf8(b"::");  
        auth_to_role.append(issuer.role_name);
    };
    auth_to_role
}

// === View Functions ===

public fun account_addr(issuer: &Issuer): address {
    issuer.account_addr
}

public fun role_type(issuer: &Issuer): TypeName {
    issuer.role_type
}

public fun role_name(issuer: &Issuer): String {
    issuer.role_name
}

// === Package functions ===

/// Constructs an issuer from a Witness, an (optional) name and a account id
public(package) fun construct<V: drop, W: drop>(
    account_addr: address,
    _version: V, 
    _role: W, 
    role_name: String, 
): Issuer {
    let role_type = type_name::get<W>();
    
    Issuer { account_addr, role_type, role_name }
}