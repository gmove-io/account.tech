/// This module tracks the version of the package by implementing the version_witness type.
/// A new version type should be defined for each new version of the package.

module account_actions::version;

// === Imports ===

use account_protocol::version_witness::{Self, VersionWitness};

// === Constants ===

const VERSION: u64 = 1; // bump this when the package is upgraded

// === Structs ===

// define a new version struct for each new version of the package
public struct V1() has drop;

public(package) fun current(): VersionWitness {
    version_witness::new(V1()) // modify with the new version struct
}

// === Public functions ===

public fun get(): u64 {
    VERSION
}
