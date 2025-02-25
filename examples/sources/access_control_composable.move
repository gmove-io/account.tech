/// This module demonstrates how to create an intent with a custom action.
/// Here the action accessors are public but protected by an Intent and an Executable.
/// This means that any package can reuse this action for implementing its own intent.

module account_examples::access_control_composable;

use std::string::String;
use account_protocol::{
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
};
use account_examples::version;

// === Constants ===

const MAX_FEE: u64 = 10000; // 100%

// === Structs ===

/// Intent structs must have copy and drop only
public struct UpdateFeeIntent() has copy, drop;

/// Action structs must have store only 
public struct UpdateFeeAction has store {
    fee: u64,
}

public struct Protocol has key {
    id: UID,
    // add bunch of fields
    fee: u64,
}

// === Public functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(Protocol {
        id: object::new(ctx),
        fee: 0,
    });
}    

/*
* the rest of the protocol implementation 
* { ... }
*/

/// step 1: request to update the fee
public fun request_update_fee<Config, Outcome>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>,
    key: String,
    execution_time: u64,
    expiration_time: u64,
    description: String,
    fee: u64,
    ctx: &mut TxContext
) {
    account.verify(auth);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time], // executed once only
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        UpdateFeeIntent(),
        ctx
    );

    new_update_fee(&mut intent, account, fee, version::current(), UpdateFeeIntent());
    account.add_intent(intent, version::current(), UpdateFeeIntent());
}

/// step 2: resolve the intent according to the account config
/// step 3: execute the proposal and return the action (package::account_config::execute_intent)

/// step 4: execute the intent using the Executable
public fun execute_update_fee<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    protocol: &mut Protocol,
) {
    update_fee(protocol, &mut executable, account, version::current(), UpdateFeeIntent());
    account.confirm_execution(executable, version::current(), UpdateFeeIntent());
}

/// step 5: destroy the intent to get the Expired hot potato as there is no execution left
/// and delete the actions from Expired in their own module 

// Action functions

/// These functions are public and necessitate both a witness and a "VersionWitness" 
/// to ensure correct implementation of the intents that could be defined.
/// 
/// The action can only be instantiated within an intent.
/// And it can be accessed (and executed) only through the acquisition of an Executable.
/// 
/// This is the pattern that should be used to make actions available to other packages.

public fun new_update_fee<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>,
    account: &mut Account<Config, Outcome>,
    fee: u64,
    version_witness: VersionWitness,
    intent_witness: IW,    
) {
    assert!(fee <= MAX_FEE);
    account.add_action(intent, UpdateFeeAction { fee }, version_witness, intent_witness);
}

public fun update_fee<Config, Outcome, IW: drop>(
    protocol: &mut Protocol,
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    let update_fee: &UpdateFeeAction = account.process_action(executable, version_witness, intent_witness);
    protocol.fee = update_fee.fee;
}
    
public fun delete_update_fee(expired: &mut Expired) {
    let UpdateFeeAction { .. } = expired.remove_action();
}