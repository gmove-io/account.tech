module account_actions::config_intents;

// === Imports ===

use std::string::String;
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
};
use account_extensions::extensions::Extensions;
use account_actions::{
    version,
    config,
};

// === Structs ===

/// [PROPOSAL] witness defining the dependencies proposal, and associated role
public struct ConfigDepsIntent() has copy, drop;

// === [PROPOSAL] Public functions ===

// step 1: propose to update the dependencies
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
    versions: vector<u64>,
    ctx: &mut TxContext
) {
    let mut intent = account.create_intent(
        auth,
        key,
        description,
        vector[execution_time],
        expiration_time,
        outcome,
        version::current(),
        ConfigDepsIntent(),
        b"".to_string(),
        ctx
    );

    config::new_config_deps(&mut intent, account, extensions, names, addresses, versions, ConfigDepsIntent());
    account.add_intent(intent, version::current(), ConfigDepsIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: execute the action and modify Account object
public fun execute_config_deps<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>, 
) {
    config::do_config_deps(&mut executable, account, version::current(), ConfigDepsIntent());
    account.confirm_execution(executable, version::current(), ConfigDepsIntent());
}