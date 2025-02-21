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
    type_name::{Self, TypeName},
    string::String,
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
    // intent key 
    intent_key: String,
    // intent witness used to create the intent 
    intent_type: TypeName,
}

/// Verifies that the action is executed for the account that approved it
public fun assert_is_account(issuer: &Issuer, account_addr: address) {
    assert!(issuer.account_addr == account_addr, EWrongAccount);
}

/// Used by modules to execute an action
public fun assert_is_intent<IW: drop>(issuer: &Issuer, _: IW) {
    assert!(issuer.intent_type == type_name::get<IW>(), EWrongWitness);
}

// === View Functions ===

public fun account_addr(issuer: &Issuer): address {
    issuer.account_addr
}

public fun intent_type(issuer: &Issuer): TypeName {
    issuer.intent_type
}

public fun intent_key(issuer: &Issuer): String {
    issuer.intent_key
}

// === Package functions ===

/// Constructs an issuer from a Witness, an (optional) name and a account id
public(package) fun new<IW: drop>(
    account_addr: address,
    intent_key: String,
    _intent_witness: IW,
): Issuer {
    let intent_type = type_name::get<IW>();
    Issuer { account_addr, intent_type, intent_key }
}