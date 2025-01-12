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

use std::string::String;
use account_protocol::{
    account::Account,
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
public struct Witness() has drop;

/// [ACTION] struct wrapping the deps account field into an action
public struct ConfigDepsAction has drop, store {
    deps: Deps,
}

// === [COMMAND] Public functions ===

public fun edit_metadata<Config>(
    auth: Auth,
    account: &mut Account<Config>,
    keys: vector<String>,
    values: vector<String>,
) {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());

    assert!(keys.length() == values.length(), EMetadataNotSameLength);
    assert!(keys[0] == b"name".to_string(), EMetadataNameMissing);
    assert!(values[0] != b"".to_string(), ENameCannotBeEmpty);

    *account.metadata_mut(version::current()) = metadata::from_keys_values(keys, values);
}

// === Public functions ===

// step 1: propose to update the dependencies
public fun request_config_deps<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    extensions: &Extensions,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    names: vector<String>,
    addresses: vector<address>,
    versions: vector<u64>,
    outcome: Outcome,
) {
    let mut deps = deps::new(extensions);

    names.zip_do!(addresses, |name, addr| {
        let version = versions.remove(0);

        if (extensions.is_extension(name, addr, version)) {
            deps.add(extensions, name, addr, version);
        } else if (upgrade_policies::has_cap(account, addr)) {
            let cap = upgrade_policies::borrow_cap(account, addr);
            deps.add_with_upgrade_cap(cap, name, addr, version);
        } else abort ENoExtensionOrUpgradeCap;
    });

    account.create_intent(
        auth,
        key,
        description,
        execution_time,
        expiration_time,
        outcome,
        ConfigDepsAction { deps },
        version::current(),
        Witness(),
        b"".to_string(),
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: execute the action and modify Account object
public fun execute_config_deps<Config>(
    mut executable: Executable<ConfigDepsAction>,
    account: &mut Account<Config>, 
) {
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());    
    *account.deps_mut(version::current()) = action_mut.deps;
    executable.destroy(version::current(), Witness());
}
