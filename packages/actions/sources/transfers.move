/// This module defines apis to transfer assets owned or managed by the account.
/// The proposals can implement transfers for any action type (e.g. see owned or treasury).

module account_actions::transfers;

// === Imports ===
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
};

// === Errors ===

const ETransferNotExecuted: u64 = 0;

// === Structs ===

/// [ACTION] used in combination with other actions (like WithdrawAction) to transfer the coins or objects to a recipient
public struct TransferAction has store {
    // address to transfer to
    recipient: address,
}

// === [ACTION] Public functions ===

public fun new_transfer<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    recipient: address,
    witness: W,
) {
    proposal.add_action(TransferAction { recipient }, witness);
}

public fun transfer<Config, Outcome, T: key + store, W: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    object: T,
    witness: W,
    is_executed: bool,
) {
    let transfer_mut: &mut TransferAction = executable.action_mut(account.addr(), witness);
    transfer::public_transfer(object, transfer_mut.recipient);

    if (is_executed)
        transfer_mut.recipient = @0xF; // reset to ensure it is executed once
}

public fun destroy_transfer<W: drop>(
    executable: &mut Executable, 
    witness: W
) {
    let TransferAction { recipient } = executable.remove_action(witness);
    assert!(recipient == @0xF, ETransferNotExecuted);
}

public fun delete_transfer_action<Outcome>(expired: Expired<Outcome>) {
    let TransferAction { .. } = expired.remove_expired_action();
}