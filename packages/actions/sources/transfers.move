/// This module defines apis to transfer assets owned or managed by the account.
/// The proposals can implement transfers for any action type (e.g. see owned or treasury).

module account_actions::transfers;

// === Imports ===

use std::type_name::TypeName;
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
};

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

public fun transfer<Config, Outcome, T: key + store, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    object: T,
    version: TypeName,
    witness: W,
    is_executed: bool,
) {
    let transfer_action = executable.load<TransferAction, W>(account.addr(), version, witness);
    transfer::public_transfer(object, transfer_action.recipient);

    if (is_executed) executable.process<TransferAction, W>(version, witness);
}

public fun destroy_transfer<W: drop>(
    executable: &mut Executable, 
    version: TypeName,
    witness: W,
) {
    let TransferAction { .. } = executable.cleanup(version, witness);
}

public fun delete_transfer_action<Outcome>(expired: &mut Expired<Outcome>) {
    let TransferAction { .. } = expired.remove_expired_action();
}