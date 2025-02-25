/// This module demonstrates how to create an intent with a custom action.
/// Here there is no action interface as the action is directly handled as part of the intent.
/// This means that the action cannot be reused in another module.

module account_examples::access_control_simplified;

use std::string::String;
use account_protocol::{
    account::{Account, Auth},
    intents::Expired,
    executable::Executable,
};
use account_multisig::multisig::{Multisig, Approvals};
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

/// Your protocol
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

// === Public functions ===

/// step 1: propose to update the version
public fun request_update_fee(
    auth: Auth,
    outcome: Approvals,
    multisig: &mut Account<Multisig, Approvals>,
    key: String,
    execution_time: u64,
    expiration_time: u64,
    description: String,
    fee: u64,
    ctx: &mut TxContext
) {
    multisig.verify(auth);

    assert!(fee <= MAX_FEE);
    let mut intent = multisig.create_intent(
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

    multisig.add_action(&mut intent, UpdateFeeAction { fee }, version::current(), UpdateFeeIntent());
    multisig.add_intent(intent, version::current(), UpdateFeeIntent());
}

/// step 2: multiple members have to approve the intent (account_multisig::multisig::approve_intent)
/// step 3: execute the intent and return the action (account_protocol::account::execute_intent)

/// step 4: execute the intent and destroy the executable
public fun execute_update_fee(
    mut executable: Executable,
    multisig: &Account<Multisig, Approvals>,
    protocol: &mut Protocol,
) {
    let update_fee: &UpdateFeeAction = multisig.process_action(&mut executable, version::current(), UpdateFeeIntent());
    protocol.fee = update_fee.fee;
    multisig.confirm_execution(executable, version::current(), UpdateFeeIntent());
}

/// step 5: destroy the intent to get the Expired hot potato as there is no execution left

/// step 6: delete the actions from Expired
public fun delete_update_fee(expired: &mut Expired) {
    let UpdateFeeAction { .. } = expired.remove_action();
}