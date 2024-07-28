/// This module handles the authentication:
/// - for proposal and actions execution
/// - for roles and associated approval & threshold 
/// - for objects managing assets (treasuries, kiosks, etc)
/// 
/// A role is defined as a TypeName + an optional name
/// -> package_id::module_name::struct_name::name or package_id::module_name::struct_name

module kraken::auth;

// === Imports ===

use std::{
    string::String,
    type_name,
};

// === Errors ===

const EWrongIssuer: u64 = 0;
const EWrongRole: u64 = 1;

// === Structs ===

// protected type ensuring provenance
public struct Auth has store, drop {
    // type_name of the witness that instantiated the auth
    issuer: String,
    // name of the auth (can be empty)
    name: String,
}

// === Public Functions ===

// construct an auth from an Issuer and an (optional) name
public fun construct<I: drop>(_: I, name: String): Auth {
    let issuer = type_name::get<I>().into_string().to_string();
    Auth { issuer, name }
}

// to be used by modules to execute an action
public fun authenticate_module<I: drop>(auth: &Auth, _: I) {
    let issuer = type_name::get<I>().into_string().to_string();
    assert!(auth.issuer == issuer, EWrongIssuer);
}

// to be used by roles to approve a proposal
public fun authenticate_role(auth: &Auth, role: String) {
    assert!(auth.into_role() == role, EWrongRole);
}

// role is package::module::struct::name or package::module::struct
public fun into_role(auth: &Auth): String {
    let mut auth_to_role = auth.issuer;
    if (!auth.name.is_empty()) {
        auth_to_role.append_utf8(b"::");  
        auth_to_role.append(auth.name);
    };
    auth_to_role
}