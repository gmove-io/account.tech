module sui_multisig::move_call {
    use std::ascii::String;
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

    // step 4: destroy MoveCall if digest match and return Access
    public fun execute(action: MoveCall, ctx: &TxContext): Access {
        let MoveCall { digest, access_owned } = action;
        assert!(digest == ctx.digest(), EDigestDoesntMatch);
        
        access_owned
    }    

    // step 5: borrow or withdraw the objects from access_owned 
    // step 6: destroy Access in access_owned
}

