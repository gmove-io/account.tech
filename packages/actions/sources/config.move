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
    metadata,
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

/// [COMMAND] witness defining the metadata command, and associated role
public struct ConfigMetadataCommand() has copy, drop;
/// [PROPOSAL] witness defining the dependencies proposal, and associated role
public struct ConfigDepsProposal() has copy, drop;

/// [ACTION] struct wrapping the deps account field into an action
public struct ConfigDepsAction has store {
    deps: Deps,
}

// === [COMMAND] Public functions ===

public fun edit_metadata<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    keys: vector<String>,
    values: vector<String>,
) {
    auth.verify_with_role<ConfigMetadataCommand>(account.addr(), b"".to_string());

    assert!(keys.length() == values.length(), EMetadataNotSameLength);
    assert!(keys[0] == b"name".to_string(), EMetadataNameMissing);
    assert!(values[0] != b"".to_string(), ENameCannotBeEmpty);

    *account.metadata_mut(version::current()) = metadata::from_keys_values(keys, values);
}

// === [PROPOSAL] Public functions ===

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
        } else if (upgrade_policies::has_cap(account, package)) {
            let cap = upgrade_policies::borrow_cap(account, package);
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