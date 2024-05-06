/// This module allows to propose a MoveCall action to be executed by a Multisig.
/// The MoveCall action is unwrapped from an approved proposal 
/// and its digest is verified against the actual transaction (digest) 
/// the proposal can request to borrow or withdraw some objects from the Multisig's account in the PTB
/// allowing to get a Cap to call the proposed function.

module sui_multisig::move_call {
    use std::ascii::String;
    use sui_multisig::multisig::Multisig;
    use sui_multisig::access_owned::{Self, Access};
    use sui_multisig::store_asset::{Self, Withdraw};

    // === Error ===

    const EDigestDoesntMatch: u64 = 0;

    // === Structs ===

    // action to be held in a Proposal
    public struct MoveCall has store {
        // digest of the tx we want to execute
        digest: vector<u8>,
        // sub action requesting to access owned objects (such as a Cap)
        owned: Access,
        // sub action requesting access to assets stored in the Multisig (such as Coins)
        stored: Withdraw,
    }

    // === Public mutative functions ===

    // step 1: propose a MoveCall by passing the digest of the tx
    public fun propose(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        digest: vector<u8>,
        owned_to_borrow: vector<ID>,
        owned_to_withdraw: vector<ID>,
        asset_types: vector<String>,
        amounts: vector<u64>,
        keys: vector<String>,
        ctx: &mut TxContext
    ) {
        let owned = access_owned::new_access(owned_to_borrow, owned_to_withdraw);
        let stored = store_asset::new_withdraw(asset_types, amounts, keys);
        let action = MoveCall { digest, owned, stored };

        multisig.create_proposal(
            action,
            name,
            expiration,
            description,
            ctx
        );
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: destroy MoveCall if digest match and return Access
    public fun execute(action: MoveCall, ctx: &TxContext): (Access, Withdraw) {
        let MoveCall { digest, owned, stored } = action;
        assert!(digest == ctx.digest(), EDigestDoesntMatch);
        
        (owned, stored)
    }    

    // step 5: borrow or withdraw the objects from access_owned (get a Cap to call another function)
    // step 6: destroy Access in access_owned
}

