module account_protocol::version_witness;

// === Imports ===

use std::type_name;
use sui::{
    address, 
    hex,
};

// === Structs ===

public struct VersionWitness has copy, drop {
    // package id where the proof has been created
    package_addr: address,
}

public fun new<PW: drop>(_package_witness: PW): VersionWitness {
    let package_type = type_name::get<PW>();
    let package_addr = address::from_bytes(hex::decode(package_type.get_address().into_bytes()));

    VersionWitness { package_addr }
}

// === Public Functions ===

public fun package_addr(witness: &VersionWitness): address {
    witness.package_addr
}

// === Test functions ===

#[test_only]
public fun new_for_testing(package_addr: address): VersionWitness {
    VersionWitness { package_addr }
}
