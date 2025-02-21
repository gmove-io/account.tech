/// This module manages the metadata field of Account.
/// It provides the interface to create and get the fields of a Metadata struct.

module account_protocol::metadata;

// === Imports ===

use std::string::String;
use sui::vec_map::{Self, VecMap};

// === Errors ===

const EMetadataNotSameLength: u64 = 0;

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

/// Creates a new Metadata struct from keys and values.
public fun from_keys_values(keys: vector<String>, values: vector<String>): Metadata {
    assert!(keys.length() == values.length(), EMetadataNotSameLength);
    Metadata {
        inner: vec_map::from_keys_values(keys, values)
    }
}

/// Gets the value for the key.
public fun get(metadata: &Metadata, key: String): String {
    *metadata.inner.get(&key)
}

/// Gets the entry at the index.
public fun get_entry_by_idx(metadata: &Metadata, idx: u64): (String, String) {
    let (key, value) = metadata.inner.get_entry_by_idx(idx);
    (*key, *value)
}

/// Returns the number of entries.
public fun size(metadata: &Metadata): u64 {
    metadata.inner.size()
}
