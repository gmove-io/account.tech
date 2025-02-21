/// This module contains the logic for modifying the Multisig configuration via an intent.

module account_multisig::config;

// === Imports ===

use std::string::String;
use account_protocol::{
    intents::Expired,
    executable::Executable,
    account::{Account, Auth},
};
use account_multisig::{
    multisig::{Self, Multisig, Approvals},
    version,
};

// === Structs ===

/// Intent to modify the members and thresholds of the account.
public struct ConfigMultisigIntent() has copy, drop;

/// Action wrapping a Multisig struct into an action.
public struct ConfigMultisigAction has drop, store {
    config: Multisig,
}

// === Public functions ===

/// No actions are defined as changing the config isn't supposed to be composable for security reasons

/// Requests new Multisig settings.
public fun request_config_multisig(
    auth: Auth,
    outcome: Approvals,
    account: &mut Account<Multisig, Approvals>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
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
    account.verify(auth);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        ConfigMultisigIntent(),
        ctx
    );

    let config = multisig::new_config(addresses, weights, roles, global, role_names, role_thresholds);

    account.add_action(&mut intent, ConfigMultisigAction { config }, version::current(), ConfigMultisigIntent());
    account.add_intent(intent, version::current(), ConfigMultisigIntent());
}

/// Executes the action and modifies the Account Multisig.
public fun execute_config_multisig(
    mut executable: Executable,
    account: &mut Account<Multisig, Approvals>, 
) {
    let action: &ConfigMultisigAction = account.process_action(&mut executable, version::current(), ConfigMultisigIntent());
    *multisig::config_mut(account) = action.config;
    account.confirm_execution(executable, version::current(), ConfigMultisigIntent());
}

/// Deletes the action in an expired intent.
public fun delete_config_multisig(expired: &mut Expired) {
    let ConfigMultisigAction { .. } = expired.remove_action();
}