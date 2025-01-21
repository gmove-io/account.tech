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

module account_protocol::config;

// === Imports ===

use std::string::String;
use account_protocol::{
    account::{Account, Auth},
    intents::Expired,
    executable::Executable,
    deps::{Self, Deps},
    metadata,
    version,
};
use account_extensions::extensions::Extensions;

// === Errors ===

#[error]
const EMetadataNotSameLength: vector<u8> = b"The keys and values are not the same length";

// === Structs ===

public struct ConfigDepsIntent() has copy, drop;
public struct ToggleUnverifiedAllowedIntent() has copy, drop;

/// [ACTION] struct wrapping the deps account field into an action
public struct ConfigDepsAction has store {
    deps: Deps,
}

/// [ACTION] struct wrapping the unverified_allowed account field into an action
public struct ToggleUnverifiedAllowedAction has store {
    new_value: bool,
}

// === Public functions ===

public fun edit_metadata<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    keys: vector<String>,
    values: vector<String>,
) {
    account.verify(auth);
    assert!(keys.length() == values.length(), EMetadataNotSameLength);

    *account.metadata_mut(version::current()) = metadata::from_keys_values(keys, values);
}

public fun request_config_deps<Config, Outcome>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    extensions: &Extensions,
    names: vector<String>,
    addresses: vector<address>,
    mut versions: vector<u64>,
    ctx: &mut TxContext
) {
    account.verify(auth);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        ConfigDepsIntent(),
        ctx
    );

    let mut deps = deps::new(extensions, account.deps().unverified_allowed());
    names.zip_do!(addresses, |name, addr| {
        deps.add(extensions, name, addr, versions.remove(0));
    });

    account.add_action(&mut intent, ConfigDepsAction { deps }, version::current(), ConfigDepsIntent());
    account.add_intent(intent, version::current(), ConfigDepsIntent());
}

public fun execute_config_deps<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>, 
) {
    let action: &ConfigDepsAction = account.process_action(&mut executable, version::current(), ConfigDepsIntent());    
    *account.deps_mut(version::current()) = action.deps;
    account.confirm_execution(executable, version::current(), ConfigDepsIntent());
} 


public fun delete_config_deps(expired: &mut Expired) {
    let ConfigDepsAction { .. } = expired.remove_action();
}

public fun request_toggle_unverified_allowed<Config, Outcome>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    ctx: &mut TxContext
) {
    account.verify(auth);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        ToggleUnverifiedAllowedIntent(),
        ctx
    );

    let new_value = account.deps().unverified_allowed();

    account.add_action(&mut intent, ToggleUnverifiedAllowedAction { new_value }, version::current(), ToggleUnverifiedAllowedIntent());
    account.add_intent(intent, version::current(), ToggleUnverifiedAllowedIntent());
}

public fun execute_toggle_unverified_allowed<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>, 
) {
    let _action: &ToggleUnverifiedAllowedAction = account.process_action(&mut executable, version::current(), ToggleUnverifiedAllowedIntent());    
    account.deps_mut(version::current()).toggle_unverified_allowed();
    account.confirm_execution(executable, version::current(), ToggleUnverifiedAllowedIntent());
}


public fun delete_toggle_unverified_allowed(expired: &mut Expired) {
    let ToggleUnverifiedAllowedAction { .. } = expired.remove_action();
}

