/// This module demonstrates how to create a proposal with a custom action.
/// Here there is no action accessor as the action is directly implemented as part of the proposal.
/// This means that the action cannot be reused in another module.

module examples::access_control;

use std::string::String;
use kraken::{
    multisig::{Multisig, Executable}
};

// === Constants ===

const MAX_FEE: u64 = 10000; // 100%

// === Structs ===

public struct Auth has copy, drop {}

// [ACTION] action structs must have store only 
public struct UpdateFee has store {
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
* the rest of the module implementation 
* { ... }
*/

// === [PROPOSAL] Public functions ===

// step 1: propose to update the version
public fun propose_update_fee(
    multisig: &mut Multisig, 
    key: String,
    execution_time: u64,
    expiration_epoch: u64,
    description: String,
    fee: u64,
    ctx: &mut TxContext
) {
    assert!(fee <= MAX_FEE);
    let proposal_mut = multisig.create_proposal(
        Auth {}, 
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    proposal_mut.add_action(UpdateFee { fee });
}

// step 2: multiple members have to approve the proposal (kraken::multisig::approve_proposal)
// step 3: execute the proposal and return the action (kraken::multisig::execute_proposal)

// function guarded by a Multisig action
public fun execute_update_fee(
    mut executable: Executable,
    multisig: &Multisig,
    protocol: &mut Protocol,
) {
    let update_fee_mut: &mut UpdateFee = executable.action_mut(Auth {}, multisig.addr());
    protocol.fee = update_fee_mut.fee;

    let UpdateFee { .. } = executable.remove_action(Auth {}); 
    executable.destroy(Auth {}); 
}