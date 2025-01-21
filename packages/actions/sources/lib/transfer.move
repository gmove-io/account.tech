/// This module defines apis to transfer assets owned or managed by the account.
/// The proposals can implement transfers for any action type (e.g. see owned or treasury).

module account_actions::transfer;

// === Imports ===

use account_protocol::{
    account::Account,
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
};

// === Structs ===

/// [ACTION] used in combination with other actions (like WithdrawAction) to transfer the coins or objects to a recipient
public struct TransferAction has store {
    // address to transfer to
    recipient: address,
}

// === Public functions ===

public fun new_transfer<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>, 
    recipient: address,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    account.add_action(intent, TransferAction { recipient }, version_witness, intent_witness);
}

public fun do_transfer<Config, Outcome, T: key + store, IW: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    object: T,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    let action: &TransferAction = account.process_action(executable, version_witness, intent_witness);
    transfer::public_transfer(object, action.recipient);
}

public fun delete_transfer(expired: &mut Expired) {
    let TransferAction { .. } = expired.remove_action();
}
