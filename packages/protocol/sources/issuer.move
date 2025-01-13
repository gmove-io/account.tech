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
    type_name,
};

// === Errors ===

#[error]
const EWrongWitness: vector<u8> = b"Witness is not the one used for creating the proposal";
#[error]
const EWrongAccount: vector<u8> = b"Account address doesn't match the issuer";

// === Structs ===

/// Protected type ensuring provenance
public struct Issuer has copy, drop, store {
    // address of the account that created the issuer
    account_addr: address,
    // package id where the issuer has been created
    package_id: String,
    // module name where the issuer has been created
    module_name: String,
    // name of the issuer (can be empty)
    opt_name: String,
}

// === Public Functions ===

/// Verifies that the action is executed for the account that approved it
public fun assert_is_account(issuer: &Issuer, account_addr: address) {
    assert!(issuer.account_addr == account_addr, EWrongAccount);
}

/// Used by modules to execute an action
public fun assert_is_constructor<W: drop>(issuer: &Issuer, _: W) {
    let w_type = type_name::get<W>();
    assert!(issuer.package_id == w_type.get_address().to_string(), EWrongWitness);
    assert!(issuer.module_name == w_type.get_module().to_string(), EWrongWitness);
}

/// Converts a issuer into a role
/// role is package::module::struct::name or package::module::struct
public fun full_role(issuer: &Issuer): String {
    let mut role_type = issuer.package_id;
    role_type.append_utf8(b"::");
    role_type.append(issuer.module_name);

    if (!issuer.opt_name.is_empty()) {
        role_type.append_utf8(b"::");  
        role_type.append(issuer.opt_name);
    };

    role_type
}

// === View Functions ===

public fun account_addr(issuer: &Issuer): address {
    issuer.account_addr
}

public fun package_id(issuer: &Issuer): String {
    issuer.package_id
}

public fun module_name(issuer: &Issuer): String {
    issuer.module_name
}

public fun role_name(issuer: &Issuer): String {
    issuer.opt_name
}

// === Package functions ===

/// Constructs an issuer from a Witness, an (optional) name and a account id
public(package) fun construct<W: drop>(
    account_addr: address,
    _: W, 
    opt_name: String, 
): Issuer {
    let package_id = type_name::get<W>().get_address().to_string();
    let module_name = type_name::get<W>().get_module().to_string();
    
    Issuer { account_addr, package_id, module_name, opt_name }
}