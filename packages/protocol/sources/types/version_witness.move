/// This module defines the VersionWitness type used to track the version of the protocol.
/// This type is used as a regular witness, but for an entire package instead of a single module.

module account_protocol::version_witness;

// === Imports ===

use std::type_name;
use sui::{
    address, 
    hex,
};

// === Structs ===

/// Witness to check the version of a package.
public struct VersionWitness has copy, drop {
    // package id where the witness has been created
    package_addr: address,
}

/// Creates a new VersionWitness for the package where the Witness is instianted.
public fun new<PW: drop>(_package_witness: PW): VersionWitness {
    let package_type = type_name::get<PW>();
    let package_addr = address::from_bytes(hex::decode(package_type.get_address().into_bytes()));

    VersionWitness { package_addr }
}

// === Public Functions ===

/// Returns the address of the package where the witness has been created.
public fun package_addr(witness: &VersionWitness): address {
    witness.package_addr
}

// === Test functions ===

#[test_only]
public fun new_for_testing(package_addr: address): VersionWitness {
    VersionWitness { package_addr }
}
