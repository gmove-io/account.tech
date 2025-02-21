/// This is a protected type ensuring provenance of the intent.
/// The underlying data is used to identify the intent when executing it.
/// The Issuer is instantiated when the intent is created and is copied to an Executable when executed.

module account_protocol::issuer;

// === Imports ===

use std::{
    type_name::{Self, TypeName},
    string::String,
};

// === Errors ===

const EWrongAccount: u64 = 0;
const EWrongWitness: u64 = 1;

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

/// Verifies that the action is executed for the account that created and validated it
public fun assert_is_account(issuer: &Issuer, account_addr: address) {
    assert!(issuer.account_addr == account_addr, EWrongAccount);
}

/// Checks the witness passed is the same as the one used for creating the intent
public fun assert_is_intent<IW: drop>(issuer: &Issuer, _: IW) {
    assert!(issuer.intent_type == type_name::get<IW>(), EWrongWitness);
}

// === View Functions ===

/// Returns the address of the account that created the intent
public fun account_addr(issuer: &Issuer): address {
    issuer.account_addr
}

/// Returns the type of the intent
public fun intent_type(issuer: &Issuer): TypeName {
    issuer.intent_type
}

/// Returns the key of the intent
public fun intent_key(issuer: &Issuer): String {
    issuer.intent_key
}

// === Package functions ===

/// Constructs an issuer from an account address, an intent key and a witness
public(package) fun new<IW: drop>(
    account_addr: address,
    intent_key: String,
    _intent_witness: IW,
): Issuer {
    let intent_type = type_name::get<IW>();
    Issuer { account_addr, intent_type, intent_key }
}