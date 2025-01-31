/// This is the module managing the metadata field of Account.
/// It provides the interface to create a new Metadata struct.
/// This is possible only in a proposal.

module account_protocol::metadata;

// === Imports ===

use std::string::String;
use sui::vec_map::{Self, VecMap};

// === Structs ===

/// Parent struct protecting the metadata
public struct Metadata has copy, drop, store {
    inner: VecMap<String, String>
}

// === Public functions ===

/// Creates an empty Metadata struct
public fun empty(): Metadata {
    Metadata { inner: vec_map::empty() }
}

/// Adds a key-value pair to the metadata
public fun from_keys_values(keys: vector<String>, values: vector<String>): Metadata {
    Metadata {
        inner: vec_map::from_keys_values(keys, values)
    }
}

/// Gets the value for the key
public fun get(metadata: &Metadata, key: String): String {
    *metadata.inner.get(&key)
}

public fun get_entry_by_idx(metadata: &Metadata, idx: u64): (String, String) {
    let (key, value) = metadata.inner.get_entry_by_idx(idx);
    (*key, *value)
}

public fun size(metadata: &Metadata): u64 {
    metadata.inner.size()
}
