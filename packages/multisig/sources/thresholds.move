module kraken_multisig::thresholds;
use std::string::String;
use kraken_multisig::proposals::Proposal;

// === Errors ===

const ERoleNotFound: u64 = 0;
const EThresholdNotReached: u64 = 1;

// === Structs ===

// map roles to their threshold
public struct Thresholds has store, drop {
    global: u64,
    roles: vector<Role>,
}

public struct Role has copy, drop, store {
    name: String,
    threshold: u64,
}

// === Public functions ===

public fun new(global: u64): Thresholds {
    Thresholds { global, roles: vector[] }
}

public fun add(roles: &mut Thresholds, name: String, threshold: u64) {
    roles.roles.push_back(Role { name, threshold });
}

// protected because &mut Deps accessible only from KrakenMultisig and KrakenActions
// public fun set_global(roles: &mut Thresholds, global: u64) {
//     roles.global = global;
// }

// public fun set_role(roles: &mut Thresholds, name: String, threshold: u64) {
//     let idx = roles.get_idx(name);
//     roles.roles[idx].threshold = threshold;
// }

// public fun remove(roles: &mut Thresholds, name: String) {
//     let idx = roles.get_idx(name);
//     roles.roles.remove(idx);
// }

// === View functions ===

public fun roles_to_vec(roles: &Thresholds): vector<Role> {
    roles.roles
}

public fun get_global_threshold(roles: &Thresholds): u64 {
    roles.global
}

public fun get_role_threshold(roles: &Thresholds, name: String): u64 {
    let idx = roles.get_idx(name);
    roles.roles[idx].threshold
}

public fun get_idx(roles: &Thresholds, name: String): u64 {
    let opt = roles.roles.find_index!(|role| role.name == name);
    assert!(opt.is_some(), ERoleNotFound);
    opt.destroy_some()
}

public fun exists(roles: &Thresholds, name: String): bool {
    roles.roles.any!(|role| role.name == name)
}

public fun assert_reached(thresholds: &Thresholds, proposal: &Proposal) {
    let role = proposal.auth().into_role();
    assert!(
        proposal.total_weight() >= thresholds.get_global_threshold() ||
        (thresholds.exists(role) && proposal.role_weight() >= thresholds.get_role_threshold(role)), 
        EThresholdNotReached
    );
}