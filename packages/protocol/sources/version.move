/// This module tracks the version of the package

module account_protocol::version;

// === Imports ===

use account_protocol::version_witness::{Self, VersionWitness};

// === Constants ===

const VERSION: u64 = 1;

// === Structs ===

public struct V1() has drop;

public(package) fun current(): VersionWitness {
    version_witness::new(V1())
}

// === Public functions ===

public fun get(): u64 {
    VERSION
}
