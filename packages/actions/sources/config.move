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
    proposal::Proposal,
    executable::Executable,
    deps,
    members,
    thresholds::{Self, Thresholds},
};

// === Errors ===

const EThresholdTooHigh: u64 = 0;
const ENotMember: u64 = 1;
const EAlreadyMember: u64 = 2;
const EThresholdNull: u64 = 3;
const EMembersNotSameLength: u64 = 4;
const EThresholdNotLastAction: u64 = 5;
const ERoleAlreadyAttributed: u64 = 6;
const ERoleNotAttributed: u64 = 7;
const EVectorLengthMismatch: u64 = 8;

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

    let members = members::new();
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
    assert!(global != 0, EThresholdNull);
    let thresholds = thresholds::new(global);

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
    // TODO: verify that the new thresholds are reachable

}

// public fun destroy_thresholds<I: copy + drop>(
//     executable: &mut Executable, 
//     issuer: I
// ) {
//     let Adjust { thresholds } = executable.remove_action(issuer);
//     assert!(thresholds.is_empty(), EThresholdsNotExecuted);
// }

// public fun destroy_members<I: copy + drop>(
//     executable: &mut Executable, 
//     issuer: I
// ) {
//     let Members { to_add, to_remove } = executable.remove_action(issuer);
//     assert!(
//         to_remove.is_empty() && to_add.is_empty(),
//         EMembersNotExecuted
//     );
// }

// public fun new_weights(
//     proposal: &mut Proposal,
//     addresses: vector<address>, 
//     weights: vector<u64>,
// ) { 
//     proposal.add_action(Weights { addresses_weights_map: vec_map::from_keys_values(addresses, weights) });
// }    

// public fun weights<I: copy + drop>(
//     executable: &mut Executable,
//     multisig: &mut Multisig, 
//     issuer: I,
// ) {
//     let w_mut: &mut Weights = executable.action_mut(issuer, multisig.addr());

//     while (!w_mut.addresses_weights_map.is_empty()) {
//         let idx = w_mut.addresses_weights_map.size() - 1; // cheaper to pop
//         let (addr, weight) = w_mut.addresses_weights_map.remove_entry_by_idx(idx);
//         multisig.member_mut(addr, issuer).set_weight(weight);
//     };
    
// }

// public fun destroy_weights<I: copy + drop>(
//     executable: &mut Executable, 
//     issuer: I
// ) {
//     let Weights { addresses_weights_map } = executable.remove_action(issuer);
//     assert!(addresses_weights_map.is_empty(), EWeightsNotExecuted);
// }

// public fun new_roles(
//     proposal: &mut Proposal,
//     addr_to_add: vector<address>, 
//     roles_to_add: vector<vector<String>>, 
//     addr_to_remove: vector<address>,
//     roles_to_remove: vector<vector<String>>,
// ) { 
//     proposal.add_action(Roles { 
//         to_add: vec_map::from_keys_values(addr_to_add, roles_to_add), 
//         to_remove: vec_map::from_keys_values(addr_to_remove, roles_to_remove) 
//     });
// }

// public fun roles<I: copy + drop>(
//     executable: &mut Executable,
//     multisig: &mut Multisig, 
//     issuer: I,
// ) {
//     let roles_mut: &mut Roles = executable.action_mut(issuer, multisig.addr());

//     while (!roles_mut.to_add.is_empty()) {
//         let idx = roles_mut.to_add.size() - 1;
//         let (addr, roles) = roles_mut.to_add.remove_entry_by_idx(idx);
//         multisig.member_mut(addr, issuer).add_roles(roles);
//     };

//     while (!roles_mut.to_remove.is_empty()) {
//         let idx = roles_mut.to_remove.size() - 1;
//         let (addr, roles) = roles_mut.to_remove.remove_entry_by_idx(idx);
//         multisig.member_mut(addr, issuer).remove_roles(roles);
//     };
// }

// public fun destroy_roles<I: copy + drop>(
//     executable: &mut Executable,
//     issuer: I
// ) {
//     let Roles { to_add, to_remove } = executable.remove_action(issuer);
//     assert!(
//         to_remove.is_empty() &&
//         to_add.is_empty(),
//         ERolesNotExecuted
//     );
// }

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

// public fun new_migrate(proposal: &mut Proposal, packages: vector<address>, versions: vector<u64>) {
//     proposal.add_action(Migrate { to_update: vec_map::from_keys_values(packages, versions) });
// }

// public fun migrate<I: copy + drop>(
//     executable: &mut Executable,
//     multisig: &mut Multisig, 
//     issuer: I,
// ) {
//     let migrate_mut: &mut Migrate = executable.action_mut(issuer, multisig.addr());
//     assert!(!migrate_mut.to_update.is_empty(), EVersionsAlreadyUpdated);
    
//     let (package, version) = migrate_mut.to_update.pop();
//     multisig.deps_mut(issuer).update(package, version);
// }
    
// public fun destroy_migrate<I: copy + drop>(
//     executable: &mut Executable,
//     issuer: I,
// ) {
//     let Migrate { to_update } = executable.remove_action(issuer);
//     assert!(to_update.is_empty(), EMigrateNotExecuted);
// }

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

fun unwrap_config<T>(config: Config<T>): T {
    let Config { inner } = config;
    inner
}

