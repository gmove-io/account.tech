/// This module allows to manage Account settings.
/// The actions are related to the modifications of all the fields of the Account (except Proposals).
/// All these fields are encapsulated in the `Account` struct and each managed in their own module.
/// They are only accessible mutably via [core-deps-only] functions defined in account.move which are used here only.
/// 
/// The members and thresholds modifications are grouped under a single proposal because they often go by pair.
/// The threshold modification must be executed at the end to ensure they are reachable.
/// The proposal also verifies the validity of the new values upon creation (e.g. threshold not higher than total weight).
/// 
/// Dependencies are all the packages and their versions that the account depends on (including this one).
/// The allowed dependencies are defined in the `Extensions` struct and are maintained by Kraken team.
/// Account users can choose to use any version of any package and must explicitly migrate to the new version.
/// This is closer to a trustless model where anyone with the UpgradeCap could update the dependencies maliciously.

module account_actions::config;

// === Imports ===

use std::{
    type_name::TypeName,
    string::String,
};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    deps::{Self, Deps},
    metadata::{Self, Metadata},
    auth::Auth,
};
use account_extensions::extensions::Extensions;
use account_actions::{
    version,
    upgrade_policies,
};

// === Errors ===

#[error]
const EMetadataNotSameLength: vector<u8> = b"The keys and values are not the same length";
#[error]
const EMetadataNameMissing: vector<u8> = b"New metadata must set a name for the Account";
#[error]
const ENameCannotBeEmpty: vector<u8> = b"Name cannot be empty";
#[error]
const ENoExtensionOrUpgradeCap: vector<u8> = b"No extension or upgrade cap for this package";

// === Structs ===

/// The following structs are delegated witnesses (copy & drop abilities).
/// They are used to authenticate the account proposals.
/// Only the proposal that instantiated the witness can also destroy it.
/// Those structs also define the different roles that members can have.
/// Finally, they are used to parse the actions of the proposal off-chain.

/// proof of core dependency
public struct CoreDep() has drop;
/// [PROPOSAL] modifies the name of the account
public struct ConfigMetadataProposal() has copy, drop;
/// [PROPOSAL] modifies the dependencies of the account
public struct ConfigDepsProposal() has copy, drop;

/// [ACTION] wraps the metadata account field into an action
public struct ConfigMetadataAction has store {
    metadata: Metadata,
}
/// [ACTION] wraps the deps account field into an action
public struct ConfigDepsAction has store {
    deps: Deps,
}

// === [PROPOSAL] Public functions ===

// step 1: propose to change the name
public fun propose_config_metadata<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    keys: vector<String>,
    values: vector<String>,
    ctx: &mut TxContext
) {
    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        ConfigMetadataProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_time,
        ctx
    );

    new_config_metadata(&mut proposal, keys, values, ConfigMetadataProposal());
    account.add_proposal(proposal, version::current(), ConfigMetadataProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: execute the action and modify Account object
public fun execute_config_metadata<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>, 
) {
    do_config_metadata(&mut executable, account, version::current(), ConfigMetadataProposal());
    executable.destroy(version::current(), ConfigMetadataProposal());
}

// step 1: propose to update the dependencies
public fun propose_config_deps<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    extensions: &Extensions,
    names: vector<String>,
    addresses: vector<address>,
    versions: vector<u64>,
    ctx: &mut TxContext
) {
    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        ConfigDepsProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_time,
        ctx
    );

    new_config_deps(&mut proposal, account, extensions, names, addresses, versions, ConfigDepsProposal());
    account.add_proposal(proposal, version::current(), ConfigDepsProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: execute the action and modify Account object
public fun execute_config_deps<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>, 
) {
    do_config_deps(&mut executable, account, version::current(), ConfigDepsProposal());
    executable.destroy(version::current(), ConfigDepsProposal());
}

// === [ACTION] Public functions ===

public fun new_config_metadata<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    keys: vector<String>,
    values: vector<String>,
    witness: W
) {
    assert!(keys.length() == values.length(), EMetadataNotSameLength);
    assert!(keys[0] == b"name".to_string(), EMetadataNameMissing);
    assert!(values[0] != b"".to_string(), ENameCannotBeEmpty);

    proposal.add_action(
        ConfigMetadataAction { metadata: metadata::from_keys_values(keys, values) }, 
        witness
    );
}

public fun do_config_metadata<Config, Outcome, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>, 
    version: TypeName,
    witness: W,
) {
    let ConfigMetadataAction { metadata } = executable.action(account.addr(), version, witness);
    *account.metadata_mut(version) = metadata;
}

public fun delete_config_metadata_action<Outcome>(expired: &mut Expired<Outcome>) {
    let ConfigMetadataAction { .. } = expired.remove_expired_action();
}

public fun new_config_deps<Config, Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>,
    account: &Account<Config, Outcome>,
    extensions: &Extensions,
    names: vector<String>,
    packages: vector<address>,
    mut versions: vector<u64>,
    witness: W,
) {    
    let mut deps = deps::new(extensions);

    names.zip_do!(packages, |name, package| {
        let version = versions.remove(0);

        if (extensions.is_extension(name, package, version)) {
            deps.add(extensions, name, package, version);
        } else if (upgrade_policies::has_lock(account, package)) {
            let cap = upgrade_policies::borrow_lock(account, package).upgrade_cap();
            deps.add_with_upgrade_cap(cap, name, package, version);
        } else abort ENoExtensionOrUpgradeCap;
    });

    proposal.add_action(ConfigDepsAction { deps }, witness);
}

public fun do_config_deps<Config, Outcome, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>, 
    version: TypeName,
    witness: W,
) {
    let ConfigDepsAction { deps } = executable.action(account.addr(), version, witness);    
    *account.deps_mut(version) = deps;
}

public fun delete_config_deps_action<Outcome>(expired: &mut Expired<Outcome>) {
    let ConfigDepsAction { .. } = expired.remove_expired_action();
}