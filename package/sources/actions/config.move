/// This module allows to manage Multisig settings.
/// The action can be to add or remove members, to change the threshold or the name.
/// If one wants to update the weights of members, they must remove the members and add them back with new weights in the same proposal.
/// The new total weight must be lower than the threshold.
/// Teams can choose to use any version of the package and must explicitly migrate to the new version.

module kraken::config;

// === Imports ===

use std::string::String;
use sui::vec_map::{Self, VecMap};
use kraken::{
    multisig::{Multisig, Executable, Proposal},
    auth,
    utils,
};

// === Aliases ===

use fun utils::contains_any as vector.contains_any;
use fun utils::map_append as VecMap.append;
use fun utils::map_remove_keys as VecMap.remove_keys;
use fun utils::map_set_or as VecMap.set_or;

// === Errors ===

const EThresholdTooHigh: u64 = 0;
const ENotMember: u64 = 1;
const EAlreadyMember: u64 = 2;
const EThresholdNull: u64 = 3;
const EMigrateNotExecuted: u64 = 4;
const EVersionAlreadyUpdated: u64 = 5;
const ENameAlreadySet: u64 = 6;
const ENameNotSet: u64 = 7;
const EMembersNotExecuted: u64 = 8;
const EWeightsNotExecuted: u64 = 9;
const ERolesNotExecuted: u64 = 10;
const EThresholdNotLastAction: u64 = 11;
const ERoleAlreadyAttributed: u64 = 13;
const ERoleNotAttributed: u64 = 14;
const EThresholdsNotExecuted: u64 = 15;
const EVectorLengthMismatch: u64 = 16;

// === Structs ===

// delegated issuer verifying a proposal is destroyed in the module where it was created
public struct Issuer has copy, drop {}

// [ACTION] change the name of the multisig
public struct Name has store { 
    // new name
    name: String,
}

// [ACTION] add or remove members (with weight = 1)
public struct Members has store {
    // addresses to add
    to_add: vector<address>,
    // addresses to remove
    to_remove: vector<address>,
}

// [ACTION] modify weights per member
public struct Weights has store { 
    // addresses to modify with new weights
    addresses_weights_map: VecMap<address, u64>,
}

// [ACTION] add or remove roles from chosen members
public struct Roles has store { 
    // roles to add to each address
    to_add_map: VecMap<address, vector<String>>,
    // roles to remove from each address
    to_remove_map: VecMap<address, vector<String>>,
}

// [ACTION] set the thresholds for roles
public struct Thresholds has store {
    // new thresholds for roles, has to be <= total weight (per role)
    roles_thresholds_map: VecMap<String, u64>,
}

// [ACTION] update the version of the multisig
public struct Migrate has store { 
    // the new version
    version: u64,
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
    new_name(proposal_mut, name);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)

// step 3: execute the action and modify Multisig object
public fun execute_name(
    mut executable: Executable,
    multisig: &mut Multisig, 
) {
    name(&mut executable, multisig, Issuer {}, 0);
    destroy_name(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// step 1: propose to modify multisig rules (everything touching weights)
// all vectors can be empty (if to_modify || weights are empty, the other one must be too)
// a member can be added and modified in the same proposal
// threshold has to be valid (reachable and different from 0 for global)
public fun propose_modify_rules(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    // members 
    members_to_add: vector<address>, 
    members_to_remove: vector<address>,
    // weights
    members_to_modify: vector<address>,
    weights_to_modify: vector<u64>,
    // roles 
    addresses_add_roles: vector<address>,
    roles_to_add: vector<vector<String>>,
    addresses_remove_roles: vector<address>,
    roles_to_remove: vector<vector<String>>,
    // thresholds 
    roles_for_thresholds: vector<String>, 
    thresholds_to_set: vector<u64>, 
    ctx: &mut TxContext
) {
    verify_new_rules(
        multisig, 
        members_to_add,
        members_to_remove,
        members_to_modify,
        weights_to_modify,
        addresses_add_roles,
        roles_to_add,
        addresses_remove_roles,
        roles_to_remove,
        roles_for_thresholds,
        thresholds_to_set,
    );

    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    // must execute add members before modify weights in case we add and modify the same member
    new_members(proposal_mut, members_to_add, members_to_remove);
    new_weights(proposal_mut, members_to_modify, weights_to_modify);
    // must be given after members addition
    new_roles(proposal_mut, addresses_add_roles, roles_to_add, addresses_remove_roles, roles_to_remove);
    // must always be called last or execution will fail
    new_thresholds(proposal_mut, roles_for_thresholds, thresholds_to_set); 
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)

// step 3: execute the action and modify Multisig object
public fun execute_modify_rules(
    mut executable: Executable,
    multisig: &mut Multisig, 
) {
    members(&mut executable, multisig, Issuer {}, 0);
    weights(&mut executable, multisig, Issuer {}, 1);
    roles(&mut executable, multisig, Issuer {}, 2);
    thresholds(&mut executable, multisig, Issuer {}, 3);
    
    destroy_members(&mut executable, Issuer {});
    destroy_weights(&mut executable, Issuer {});
    destroy_roles(&mut executable, Issuer {});
    destroy_thresholds(&mut executable, Issuer {});
    
    executable.destroy(Issuer {});
}

// step 1: propose to update the version
public fun propose_migrate(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    version: u64,
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
    new_migrate(proposal_mut, version);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: execute the action and modify Multisig object
public fun execute_migrate(
    mut executable: Executable,
    multisig: &mut Multisig, 
) {
    migrate(&mut executable, multisig, Issuer {}, 0);
    destroy_migrate(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// === [ACTION] Public functions ===

public fun new_name(proposal: &mut Proposal, name: String) {
    proposal.add_action(Name { name });
}

public fun name<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    issuer: I,
    idx: u64,
) {
    multisig.assert_executed(executable);
    let name_mut: &mut Name = executable.action_mut(issuer, idx);
    assert!(!name_mut.name.is_empty(), ENameAlreadySet);
    multisig.set_name(name_mut.name);
    name_mut.name = b"".to_string(); // reset to confirm execution
}
    
public fun destroy_name<I: copy + drop>(
    executable: &mut Executable,
    issuer: I,
) {
    let Name { name } = executable.remove_action(issuer);
    assert!(name.is_empty(), ENameNotSet);
}

public fun new_thresholds(
    proposal: &mut Proposal,
    roles: vector<String>,
    thresholds: vector<u64>, 
) { 
    let (exists_, idx) = roles.index_of(&b"global".to_string());
    if (exists_) assert!(thresholds[idx] != 0, EThresholdNull);
    proposal.add_action(Thresholds { roles_thresholds_map: vec_map::from_keys_values(roles, thresholds) });
}    

public fun thresholds<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    issuer: I,
    idx: u64,
) {
    // threshold modification must be the latest action to be executed to ensure it is reachable
    assert!(idx + 1 == executable.actions_length(), EThresholdNotLastAction);
    let t_mut: &mut Thresholds = executable.action_mut(issuer, idx);

    let roles_weights_map = multisig.get_weights_for_roles();

    while (!t_mut.roles_thresholds_map.is_empty()) {
        let idx = t_mut.roles_thresholds_map.size() - 1; // cheaper to pop
        let (role, threshold) = t_mut.roles_thresholds_map.remove_entry_by_idx(idx);
        assert!(*roles_weights_map.get(&role) >= threshold, EThresholdTooHigh);
        multisig.set_threshold(role, threshold);
    };
}

public fun destroy_thresholds<I: copy + drop>(
    executable: &mut Executable, 
    issuer: I
) {
    let Thresholds { roles_thresholds_map } = executable.remove_action(issuer);
    assert!(roles_thresholds_map.is_empty(), EThresholdsNotExecuted);
}

public fun new_members(
    proposal: &mut Proposal,
    to_add: vector<address>,
    to_remove: vector<address>, 
) { 
    proposal.add_action(Members { to_remove, to_add });
}    

public fun members<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    issuer: I,
    idx: u64,
) {
    multisig.assert_executed(executable);
    let members_mut: &mut Members = executable.action_mut(issuer, idx);

    multisig.remove_members(&mut members_mut.to_remove);
    multisig.add_members(&mut members_mut.to_add);
}

public fun destroy_members<I: copy + drop>(
    executable: &mut Executable, 
    issuer: I
) {
    let Members { to_add, to_remove } = executable.remove_action(issuer);
    assert!(
        to_remove.is_empty() && to_add.is_empty(),
        EMembersNotExecuted
    );
}

public fun new_weights(
    proposal: &mut Proposal,
    addresses: vector<address>, 
    weights: vector<u64>,
) { 
    proposal.add_action(Weights { addresses_weights_map: vec_map::from_keys_values(addresses, weights) });
}    

public fun weights<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    issuer: I,
    idx: u64,
) {
    multisig.assert_executed(executable);
    let w_mut: &mut Weights = executable.action_mut(issuer, idx);

    while (!w_mut.addresses_weights_map.is_empty()) {
        let idx = w_mut.addresses_weights_map.size() - 1; // cheaper to pop
        let (addr, weight) = w_mut.addresses_weights_map.remove_entry_by_idx(idx);
        multisig.modify_weight(addr, weight);
    };
    
}

public fun destroy_weights<I: copy + drop>(
    executable: &mut Executable, 
    issuer: I
) {
    let Weights { addresses_weights_map } = executable.remove_action(issuer);
    assert!(addresses_weights_map.is_empty(), EWeightsNotExecuted);
}

public fun new_roles(
    proposal: &mut Proposal,
    addr_to_add: vector<address>, 
    roles_to_add: vector<vector<String>>, 
    addr_to_remove: vector<address>,
    roles_to_remove: vector<vector<String>>,
) { 
    proposal.add_action(Roles { 
        to_add_map: vec_map::from_keys_values(addr_to_add, roles_to_add), 
        to_remove_map: vec_map::from_keys_values(addr_to_remove, roles_to_remove) 
    });
}

public fun roles<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    issuer: I,
    idx: u64,
) {
    multisig.assert_executed(executable);
    let roles_mut: &mut Roles = executable.action_mut(issuer, idx);

    while (!roles_mut.to_add_map.is_empty()) {
        let idx = roles_mut.to_add_map.size() - 1;
        let (addr, roles) = roles_mut.to_add_map.remove_entry_by_idx(idx);
        multisig.add_roles(addr, roles);
    };

    while (!roles_mut.to_remove_map.is_empty()) {
        let idx = roles_mut.to_remove_map.size() - 1;
        let (addr, roles) = roles_mut.to_remove_map.remove_entry_by_idx(idx);
        multisig.remove_roles(addr, roles);
    };
}

public fun destroy_roles<I: copy + drop>(
    executable: &mut Executable, 
    issuer: I
) {
    let Roles { to_add_map, to_remove_map } = executable.remove_action(issuer);
    assert!(
        to_remove_map.is_empty() &&
        to_add_map.is_empty(),
        ERolesNotExecuted
    );
}

public fun new_migrate(proposal: &mut Proposal, version: u64) {
    proposal.add_action(Migrate { version });
}

public fun migrate<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    issuer: I,
    idx: u64,
) {
    multisig.assert_executed(executable);
    let migrate_mut: &mut Migrate = executable.action_mut(issuer, idx);
    assert!(migrate_mut.version != 0, EVersionAlreadyUpdated);
    multisig.set_version(migrate_mut.version);
    migrate_mut.version = 0; // reset to 0 to enforce exactly one execution
}
    
public fun destroy_migrate<I: copy + drop>(
    executable: &mut Executable,
    issuer: I,
) {
    let Migrate { version } = executable.remove_action(issuer);
    assert!(version == 0, EMigrateNotExecuted);
}

public fun verify_new_rules(
    multisig: &Multisig,
    // members 
    members_to_add: vector<address>, 
    members_to_remove: vector<address>,
    members_to_modify: vector<address>,
    mut weights_to_modify: vector<u64>,
    // roles 
    addresses_add_roles: vector<address>,
    mut roles_to_add: vector<vector<String>>,
    addresses_remove_roles: vector<address>,
    mut roles_to_remove: vector<vector<String>>,
    // thresholds 
    roles_for_thresholds: vector<String>, 
    mut thresholds_to_set: vector<u64>, 
) {
    // vectors length must match
    assert!(
        members_to_modify.length() == weights_to_modify.length() &&
        addresses_add_roles.length() == roles_to_add.length() &&
        addresses_remove_roles.length() == roles_to_remove.length() &&
        roles_for_thresholds.length() == thresholds_to_set.length(),
        EVectorLengthMismatch
    );
    // define future state: member -> weight
    let mut members_weights_map: VecMap<address, u64> = vec_map::empty();
    // init with current members
    multisig.member_addresses().do!(|addr| {
        members_weights_map.insert(addr, multisig.member(&addr).weight());
    });
    // process new members to add/remove/modify
    if (!members_to_add.is_empty())
        assert!(!members_to_add.contains_any(multisig.member_addresses()), EAlreadyMember);
        members_weights_map.append(utils::map_from_keys(members_to_add, 1));
    if (!members_to_remove.is_empty())
        assert!(members_to_remove.contains_any(multisig.member_addresses()), ENotMember);
        members_weights_map.remove_keys(members_to_remove);
    if (!members_to_modify.is_empty())
        members_to_modify.do!(|addr| {
            assert!(members_weights_map.contains(&addr), ENotMember);
            let weight = members_weights_map.get_mut(&addr);
            *weight = weights_to_modify.remove(0);
        });

    // define future state: role -> total member weight
    let mut roles_weights_map: VecMap<String, u64> = vec_map::empty();
    // init with current roles
    members_weights_map.keys().do!(|addr| {
        let weight = members_weights_map[&addr];
        if (multisig.is_member(&addr))
            multisig.member(&addr).roles().do!(|role| {
                roles_weights_map.set_or!(role, weight, |current| {
                    *current = *current + weight;
                });
            });
    });
    // process new roles to add/remove
    if (!addresses_add_roles.is_empty())
        addresses_add_roles.do!(|addr| {
            assert!(members_weights_map.contains(&addr), ENotMember);
            let weight = members_weights_map[&addr];
            let roles = roles_to_add.remove(0);
            roles.do!(|role| {
                if (multisig.is_member(&addr)) 
                    assert!(!multisig.member(&addr).roles().contains(&role), ERoleAlreadyAttributed);
                roles_weights_map.set_or!(role, weight, |current| {
                    *current = *current + weight;
                });
            });
        });
        addresses_remove_roles.do!(|addr| {
            assert!(members_weights_map.contains(&addr), ENotMember);
            let weight = members_weights_map[&addr];
            let roles = roles_to_remove.remove(0);
            roles.do!(|role| {
                if (multisig.is_member(&addr)) 
                    assert!(multisig.member(&addr).roles().contains(&role), ERoleNotAttributed);
                let current = roles_weights_map.get_mut(&role);
                *current = *current - weight;
            });
        });
    
    // define future state: role -> threshold, init with current thresholds for roles
    let mut map_roles_thresholds = multisig.thresholds();
    // process the thresholds to be set
    if (!roles_for_thresholds.is_empty())
        roles_for_thresholds.do!(|role| {
            let threshold = thresholds_to_set.remove(0);
            map_roles_thresholds.set_or!(role, threshold, |current| {
                *current = threshold;
            });
        });

    // verify threshold is reachable with new members 
    while (!map_roles_thresholds.is_empty()) {
        let (role, threshold) = map_roles_thresholds.pop();
        let mut weight = roles_weights_map.try_get(&role);
        if (weight.is_some())
            assert!(threshold <= weight.extract(), EThresholdTooHigh);
    };
}

