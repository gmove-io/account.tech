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
use kraken_extensions::extensions::Extensions;

// === Errors ===

const EThresholdTooHigh: u64 = 0;
const EThresholdNull: u64 = 1;
const EMembersNotSameLength: u64 = 2;
const ERolesNotSameLength: u64 = 3;
const EThresholdNotLastAction: u64 = 4;
const ERoleDoesntExist: u64 = 5;

// === Structs ===

// [PROPOSAL] modify the name of the multisig
public struct ConfigNameProposal has copy, drop {}
// [PROPOSAL] modify the members and thresholds of the multisig
public struct ConfigRulesProposal has copy, drop {}
// [PROPOSAL] modify the dependencies of the multisig
public struct ConfigDepsProposal has copy, drop {}

// [ACTION] wrap a multisig field into a generic action
public struct ConfigAction<T> has store {
    inner: T,
}

// === [PROPOSAL] Public functions ===

// step 1: propose to change the name
public fun propose_config_name(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    name: String,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        ConfigNameProposal {},
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
public fun execute_config_name(
    mut executable: Executable,
    multisig: &mut Multisig, 
) {
    config_name(&mut executable, multisig, ConfigNameProposal {});
    executable.destroy(ConfigNameProposal {});
}

// step 1: propose to modify multisig rules (everything touching weights)
// threshold has to be valid (reachable and different from 0 for global)
public fun propose_config_rules(
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
    verify_new_rules(addresses, weights, roles, global, role_names, role_thresholds);
    // verify new rules are valid
    let proposal_mut = multisig.create_proposal(
        ConfigRulesProposal {},
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
public fun execute_config_rules(
    mut executable: Executable,
    multisig: &mut Multisig, 
) {
    config_members(&mut executable, multisig, ConfigRulesProposal {});
    config_thresholds(&mut executable, multisig, ConfigRulesProposal {});
    executable.destroy(ConfigRulesProposal {});
}

// step 1: propose to update the version
public fun propose_config_deps(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    extensions: &Extensions,
    names: vector<String>,
    packages: vector<address>,
    versions: vector<u64>,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        ConfigDepsProposal {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_config_deps(proposal_mut, extensions, names, packages, versions);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: execute the action and modify Multisig object
public fun execute_config_deps(
    mut executable: Executable,
    multisig: &mut Multisig, 
) {
    config_deps(&mut executable, multisig, ConfigDepsProposal {});
    executable.destroy(ConfigDepsProposal {});
}

// === [ACTION] Public functions ===

public fun new_config_name(proposal: &mut Proposal, name: String) {
    proposal.add_action(ConfigAction { inner: name });
}

public fun config_name<W: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    witness: W,
) {
    let ConfigAction { inner } = executable.remove_action(witness);
    *multisig.name_mut(executable, witness) = inner;
}

public fun new_config_members(
    proposal: &mut Proposal,
    addresses: vector<address>,
    weights: vector<u64>, 
    mut roles: vector<vector<String>>, // inner vectors can be empty
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
    
    proposal.add_action(ConfigAction { inner: members });
}    

public fun config_members<W: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    witness: W,
) {
    let ConfigAction { inner } = executable.remove_action(witness);
    *multisig.members_mut(executable, witness) = inner;
}

public fun new_config_thresholds(
    proposal: &mut Proposal,
    global: u64,
    role_names: vector<String>,
    role_thresholds: vector<u64>, 
) { 
    assert!(role_names.length() == role_thresholds.length(), ERolesNotSameLength);
    assert!(global != 0, EThresholdNull);

    let mut thresholds = thresholds::new(global);
    role_names.zip_do!(role_thresholds, |role, threshold| {
        thresholds.add(role, threshold);
    });

    proposal.add_action(ConfigAction { inner: thresholds });
}    

public fun config_thresholds<W: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    witness: W,
) {
    // threshold modification must be the latest action to be executed to ensure it is reachable
    assert!(
        executable.action_index<ConfigAction<Thresholds>>() + 1 - executable.next_to_destroy() == executable.actions_length(), 
        EThresholdNotLastAction
    );
    
    let ConfigAction { inner } = executable.remove_action(witness);
    *multisig.thresholds_mut(executable, witness) = inner;
}

public fun new_config_deps(
    proposal: &mut Proposal,
    extensions: &Extensions,
    names: vector<String>,
    packages: vector<address>,
    mut versions: vector<u64>,
) {    
    let mut deps = deps::new(extensions);
    names.zip_do!(packages, |name, package| {
        let version = versions.remove(0);
        let dep = deps::new_dep(extensions, name, package, version);
        deps.add(dep);
    });
    proposal.add_action(ConfigAction { inner: deps });
}

public fun config_deps<W: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig, 
    witness: W,
) {
    let ConfigAction { inner } = executable.remove_action(witness);
    *multisig.deps_mut(executable, witness) = inner;
}

// === Private functions ===

fun verify_new_rules(
    // members 
    addresses: vector<address>,
    weights: vector<u64>,
    roles: vector<vector<String>>,
    // thresholds 
    global: u64,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
) {
    let total_weight = weights.fold!(0, |acc, weight| acc + weight);    
    assert!(addresses.length() == weights.length() && addresses.length() == roles.length(), EMembersNotSameLength);
    assert!(role_names.length() == role_thresholds.length(), ERolesNotSameLength);
    assert!(total_weight >= global, EThresholdTooHigh);
    assert!(global != 0, EThresholdNull);

    let mut weights_for_role: VecMap<String, u64> = vec_map::empty();
    weights.zip_do!(roles, |weight, roles_for_addr| {
        roles_for_addr.do!(|role| {
            if (weights_for_role.contains(&role)) {
                *weights_for_role.get_mut(&role) = weight;
            } else {
                weights_for_role.insert(role, weight);
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