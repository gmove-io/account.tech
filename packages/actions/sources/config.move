/// This module allows to manage Multisig settings.
/// The action can be to add or remove members, to change the threshold or the name.
/// If one wants to update the weights of members, they must remove the members and add them back with new weights in the same proposal.
/// The new total weight must be lower than the threshold.
/// Teams can choose to use any version of the package and must explicitly migrate to the new version.

module kraken_actions::config;

// === Imports ===

use std::string::String;
use sui::{
    vec_map::{Self, VecMap},
};
use kraken_multisig::{
    multisig::Multisig,
    proposals::Proposal,
    executable::Executable,
    deps,
    members,
    thresholds::{Self, Thresholds},
};

// === Errors ===

const EThresholdTooHigh: u64 = 0;
const EThresholdNull: u64 = 1;
const EMembersNotSameLength: u64 = 2;
const ERolesNotSameLength: u64 = 3;
const EThresholdNotLastAction: u64 = 4;
const ERoleDoesntExist: u64 = 5;

// === Structs ===

// delegated issuer verifying a proposal is destroyed in the module where it was created
public struct Issuer has copy, drop {}

// [ACTION] wrap a multisig field into a generic action
public struct Config<T> has store {
    inner: T,
}

// === [PROPOSAL] Public functions ===

// step 1: propose to change the name
public fun propose_name(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    name: String,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_config_name(proposal_mut, name);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)

// step 3: execute the action and modify Multisig object
public fun execute_name(
    mut executable: Executable,
    multisig: &mut Multisig, 
) {
    config_name(&mut executable, multisig, Issuer {});
    executable.destroy(Issuer {});
}

// step 1: propose to modify multisig rules (everything touching weights)
// threshold has to be valid (reachable and different from 0 for global)
public fun propose_modify_rules(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    // members 
    addresses: vector<address>,
    weights: vector<u64>,
    roles: vector<vector<String>>,
    // thresholds 
    global: u64,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
    ctx: &mut TxContext
) {
    verify_new_rules(weights, roles, global, role_names, role_thresholds);
    // verify new rules are valid
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    // must modify members before modifying thresholds to ensure they are reachable
    new_config_members(proposal_mut, addresses, weights, roles);
    new_config_thresholds(proposal_mut, global, role_names, role_thresholds);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)

// step 3: execute the action and modify Multisig object
public fun execute_modify_rules(
    mut executable: Executable,
    multisig: &mut Multisig, 
) {
    config_members(&mut executable, multisig, Issuer {});
    config_thresholds(&mut executable, multisig, Issuer {});
    executable.destroy(Issuer {});
}

// step 1: propose to update the version
public fun propose_deps(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    packages: vector<address>,
    versions: vector<u64>,
    names: vector<String>,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_config_deps(proposal_mut, packages, versions, names);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: execute the action and modify Multisig object
public fun execute_deps(
    mut executable: Executable,
    multisig: &mut Multisig, 
) {
    config_deps(&mut executable, multisig, Issuer {});
    executable.destroy(Issuer {});
}

// === [ACTION] Public functions ===

public fun new_config_name(proposal: &mut Proposal, name: String) {
    proposal.add_action(Config { inner: name });
}

public fun config_name<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    issuer: I,
) {
    let Config { inner } = executable.remove_action(issuer);
    *multisig.name_mut(executable, issuer) = inner;
}

public fun new_config_members(
    proposal: &mut Proposal,
    mut addresses: vector<address>,
    mut weights: vector<u64>, 
    mut roles: vector<vector<String>>, 
) { 
    assert!(
        addresses.length() == weights.length() && 
        addresses.length() == roles.length(), 
        EMembersNotSameLength
    );

    let mut members = members::new();
    addresses.zip_do!(weights, |addr, weight| {
        members.add(members::new_member(addr, weight, option::none(), roles.remove(0)));
    });
    
    proposal.add_action(Config { inner: members });
}    

public fun config_members<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    issuer: I,
) {
    let Config { inner } = executable.remove_action(issuer);
    *multisig.members_mut(executable, issuer) = inner;
}

public fun new_config_thresholds(
    proposal: &mut Proposal,
    global: u64,
    mut role_names: vector<String>,
    mut role_thresholds: vector<u64>, 
) { 
    assert!(role_names.length() == role_thresholds.length(), ERolesNotSameLength);
    assert!(global != 0, EThresholdNull);

    let mut thresholds = thresholds::new(global);
    role_names.zip_do!(role_thresholds, |role, threshold| {
        thresholds.add(role, threshold);
    });

    proposal.add_action(Config { inner: thresholds });
}    

public fun config_thresholds<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    issuer: I,
) {
    // threshold modification must be the latest action to be executed to ensure it is reachable
    assert!(executable.action_index<Config<Thresholds>>() + 1 == executable.actions_length(), EThresholdNotLastAction);
    
    let Config { inner } = executable.remove_action(issuer);
    *multisig.thresholds_mut(executable, issuer) = inner;
}

public fun new_config_deps(
    proposal: &mut Proposal,
    packages: vector<address>,
    versions: vector<u64>,
    names: vector<String>,
) {
    let deps = deps::from_vecs(packages, versions, names);
    proposal.add_action(Config { inner: deps });
}

public fun config_deps<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    issuer: I,
) {
    let Config { inner } = executable.remove_action(issuer);
    *multisig.deps_mut(executable, issuer) = inner;
}

// === Private functions ===

fun verify_new_rules(
    // members 
    mut weights: vector<u64>,
    mut roles: vector<vector<String>>,
    // thresholds 
    global: u64,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
) {
    let total_weight = weights.fold!(0, |acc, weight| acc + weight);
    assert!(total_weight >= global, EThresholdTooHigh);

    let mut weights_for_role: VecMap<String, u64> = vec_map::empty();
    weights.zip_do!(roles, |weight, roles_for_addr| {
        roles_for_addr.do!(|role| {
            if (weights_for_role.contains(&role)) {
                weights_for_role.insert(role, weight);
            } else {
                *weights_for_role.get_mut(&role) = weight;
            }
        });
    });

    while (!weights_for_role.is_empty()) {
        let (role, weight) = weights_for_role.pop();
        let (role_exists, idx) = role_names.index_of(&role);
        assert!(role_exists, ERoleDoesntExist);
        assert!(weight >= role_thresholds[idx], EThresholdTooHigh);
    };
}