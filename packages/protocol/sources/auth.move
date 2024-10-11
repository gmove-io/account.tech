/// 

module account_protocol::auth;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use sui::address;
use account_extensions::extensions::Extensions;

// === Errors ===

const EWrongWitness: u64 = 0;
const EWrongAccount: u64 = 1;
const EWrongRole: u64 = 2;

// === Structs ===

/// Protected type ensuring provenance
public struct Auth {
    // type_name (+ opt name) of the witness that instantiated the auth
    role: String,
    // address of the account that created the auth
    account_addr: address,
}

// === Public Functions ===

// === View Functions ===

public fun role(auth: &Auth): String {
    auth.role
}

public fun account_addr(auth: &Auth): address {
    auth.account_addr
}

// === Core extensions functions ===

public fun new<W: drop>(
    extensions: &Extensions,
    role: String, 
    account_addr: address,
    _: W,
): Auth {
    let addr = address::from_bytes(type_name::get<W>().get_address().into_bytes());
    extensions.assert_is_core_extension(addr);

    Auth { role, account_addr }
}

public fun verify(
    auth: Auth,
    addr: address,
) {
    let Auth { account_addr, .. } = auth;

    assert!(addr == account_addr, EWrongAccount);
}

public fun verify_with_role<Role>(
    auth: Auth,
    addr: address,
    name: String,
) {
    let r = type_name::get<Role>().into_string().to_string();  
    r.append(name);
    
    let Auth { role, account_addr } = auth;

    assert!(addr == account_addr, EWrongAccount);
    assert!(role == r, EWrongRole);
}