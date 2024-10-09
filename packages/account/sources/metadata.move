/// This is the module managing the metadata field of Account.
/// It provides the interface to create a new Metadata struct.
/// This is possible only in a proposal.

module account_protocol::metadata;

// === Imports ===

use std::string::String;
use sui::vec_map::{Self, VecMap};

// === Structs ===

/// Parent struct protecting the metadata
public struct Metadata has store, drop {
    inner: VecMap<String, String>
}

// === Public functions ===

/// Creates a new Metadata struct with a name
public fun new(name: String): Metadata {
    Metadata { 
        inner: vec_map::from_keys_values(
            vector[b"name".to_string()], 
            vector[name])
    }
}

/// Adds a key-value pair to the metadata
public fun from_keys_values(keys: vector<String>, values: vector<String>): Metadata {
    Metadata {
        inner: vec_map::from_keys_values(keys, values)
    }
}