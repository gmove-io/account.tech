/// This mmodule hanldes the version of the package

module account_protocol::version;

// === Constants ===

const VERSION: u64 = 1;

// === Structs ===

public struct V1() has copy, drop, store;

public struct Version has drop, store {
    current: u64
}

// === Public functions ===

public fun get(): u64 {
    VERSION
}

public macro fun get_type(): _ {
    get_v1()
}

public fun get_v1(): V1 {
    V1()
}