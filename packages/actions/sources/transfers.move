/// This module defines apis to transfer assets owned or managed by the multisig.
/// The proposals can implement transfers for any action type (e.g. see owned or treasury).

module kraken_actions::transfers;

// === Imports ===
use kraken_multisig::{
    multisig::Multisig,
    proposals::Proposal,
    executable::Executable
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

public fun new_transfer(
    proposal: &mut Proposal, 
    recipient: address
) {
    proposal.add_action(TransferAction { recipient });
}

public fun transfer<T: key + store, W: copy + drop>(
    executable: &mut Executable, 
    multisig: &mut Multisig, 
    object: T,
    witness: W,
    is_executed: bool,
) {
    let transfer_mut: &mut TransferAction = executable.action_mut(witness, multisig.addr());
    transfer::public_transfer(object, transfer_mut.recipient);

    if (is_executed)
        transfer_mut.recipient = @0xF; // reset to ensure it is executed once
}

public fun destroy_transfer<W: copy + drop>(
    executable: &mut Executable, 
    witness: W
) {
    let TransferAction { recipient } = executable.remove_action(witness);
    assert!(recipient == @0xF, ETransferNotExecuted);
}

// === [CORE DEPS] Public functions ===

public fun delete_transfer_action<W: copy + drop>(
    action: TransferAction, 
    multisig: &Multisig, 
    witness: W
) {
    multisig.deps().assert_core_dep(witness);
    let TransferAction { .. } = action;
}