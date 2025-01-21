/// This module tracks the version of the package

module account_config::version;

// === Imports ===

use account_protocol::version_witness::{Self, VersionWitness};

// === Constants ===

const VERSION: u64 = 1;

// === Structs ===

public struct V1() has copy, drop;

// === Public functions ===

public fun get(): u64 {
    VERSION
}

public(package) fun current(): VersionWitness {
    version_witness::new(V1())
}
