/// This module tracks the version of the package

module account_actions::version;

// === Imports ===

use std::type_name::{Self, TypeName};

// === Constants ===

const VERSION: u64 = 1;

// === Structs ===

public struct V1() has copy, drop;

// === Public functions ===

public fun get(): u64 {
    VERSION
}

public fun current(): TypeName {
    type_name::get<V1>()
}