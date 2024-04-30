module sui_multisig::move_call {
    use std::string::String;
    use sui_multisig::multisig::Multisig;
    use sui_multisig::access_owned::{Self, Access};

    // === Error ===

    const EDigestDoesntMatch: u64 = 0;

    // === Structs ===

    // action to be held in a Proposal
    public struct MoveCall has store {
        // digest of the tx we want to execute
        digest: vector<u8>,
        // sub action requesting to access owned objects
        access_owned: Access,
    }

    // === Public mutative functions ===

    // step 1: propose a MoveCall by passing the digest of the tx
    public fun propose(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        digest: vector<u8>,
        objects_to_borrow: vector<ID>,
        objects_to_withdraw: vector<ID>,
        ctx: &mut TxContext
    ) {
        let access_owned = access_owned::new_access(objects_to_borrow, objects_to_withdraw);
        let action = MoveCall { digest, access_owned };

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
    
    // step 4: get Owned vector and retrieve/receive them in multisig::access_owned
    public fun access_owned(action: &mut MoveCall, ctx: &TxContext): &mut Access {
        assert!(action.digest == ctx.digest(), EDigestDoesntMatch);
        &mut action.access_owned
    }

    // step 5: borrow or withdraw the objects from access_owned 

    // step 6: destroy Access if empty and the MoveCall
    public fun complete_action(action: MoveCall) {
        let MoveCall { digest: _, access_owned } = action;
        access_owned.complete_action();
    }    
}

