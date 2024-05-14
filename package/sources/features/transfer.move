/// This module uses the owned apis to transfer assets owned by the multisig.

module kraken::transfer {
    use std::debug::print;
    use std::string::String;
    use sui::transfer::Receiving;
    use kraken::owned::{Self, Access};
    use kraken::multisig::Multisig;

    // === Errors ===

    const ETransferAllAssetsBefore: u64 = 1;

    // === Structs ===

    // action to be held in a Proposal
    public struct Transfer has store {
        // sub action - owned objects to access
        request_access: Access,
        // addresses to transfer to
        recipients: vector<address>
    }

    // === Multisig functions ===

    // step 1: propose to retrieve owned objects and store them in the multisig via dof
    public fun propose(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        object_ids: vector<ID>,
        recipients: vector<address>,
        ctx: &mut TxContext
    ) {
        // create a new access with the objects to withdraw (none to borrow)
        let request_access = owned::new_access(vector[], object_ids);
        let action = Transfer { request_access, recipients };
        multisig.create_proposal(
            action,
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: in the PTB loop over deposit functions and pop back Owned in Deposit
    // attach Balances as multisig dof (merge if type already exists)
    public fun transfer<T: key + store>(
        multisig: &mut Multisig, 
        action: &mut Transfer, 
        received: Receiving<T>
    ) {
        let owned = action.request_access.pop_owned();
        let coin = owned::take(multisig, owned, received);
        transfer::public_transfer(coin, action.recipients.pop_back());
    }

    // step 5: destroy the action
    public fun complete(action: Transfer) {
        let Transfer { request_access, recipients } = action;
        assert!(recipients.is_empty(), ETransferAllAssetsBefore);
        request_access.complete();
    }
}

