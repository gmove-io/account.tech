/// Thresholds control which Proposals can be executed.
/// There is a global threshold that any member can reach.
/// There are also role-based thresholds that can be reached by members with a certain role.
/// Roles correspond to the delegated witness of a Proposal with an optional name.

module kraken_account::thresholds;

// === Imports ===

use std::string::String;
use kraken_account::proposals::Proposal;

// === Errors ===

const ERoleNotFound: u64 = 0;
const EThresholdNotReached: u64 = 1;

// === Structs ===

/// Parent struct protecting the thresholds
public struct Thresholds has store, drop {
    global: u64,
    roles: vector<Role>,
}

/// Child struct representing a role with a name and its threshold
public struct Role has copy, drop, store {
    name: String,
    threshold: u64,
}

// === Public functions ===

/// Creates a new Thresholds struct with the global threshold set to `global` and no roles
public fun new(global: u64): Thresholds {
    Thresholds { global, roles: vector[] }
}

/// Protected because &mut Thresholds is only accessible from KrakenAccount and KrakenActions
public fun add(roles: &mut Thresholds, name: String, threshold: u64) {
    roles.roles.push_back(Role { name, threshold });
}

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
