module sui_multisig::management {
    use std::string::String;
    use sui_multisig::multisig::Multisig;

    // === Errors ===

    const EThresholdTooHigh: u64 = 0;
    const ENotMember: u64 = 1;
    const EAlreadyMember: u64 = 2;
    const EThresholdNull: u64 = 3;

    // === Structs ===

    public struct Management has store { 
        is_add: bool, // if true, add members, if false, remove members
        threshold: u64,
        addresses: vector<address>
    }

    // === Multisig-only functions ===

    // step 1: propose to modify multisig params
    public fun propose(
        multisig: &mut Multisig, 
        is_add: bool, // is it to add or remove members
        threshold: u64,
        addresses: vector<address>, // addresses to add or remove
        name: String,
        expiration: u64,
        description: String,
        ctx: &mut TxContext
    ) {
        assert!(threshold > 0, EThresholdNull);
        // verify proposed addresses match current list
        let len = addresses.length();
        let mut i = 0;
        while (i < len) {
            let addr = addresses.borrow(i);
            if (is_add) {
                assert!(!multisig.member_exists(addr), EAlreadyMember);
            } else {
                assert!(multisig.member_exists(addr), ENotMember);
            };
            i = i + 1;
        };
        // verify threshold is reachable with new members 
        let new_addr_len = if (is_add) {
            addresses.length() + multisig.members().length()
        } else {
            multisig.members().length() - addresses.length()
        };
        assert!(new_addr_len >= threshold, EThresholdTooHigh);

        let action = Management { is_add, threshold, addresses };
        multisig.create_proposal(action, name, expiration, description, ctx);
    }

    // step 2: multiple members have to approve the proposal
    
    // step 3: execute the action and modify Multisig object
    public fun execute(multisig: &mut Multisig, name: String, ctx: &mut TxContext) {
        let action = multisig.execute_proposal(name, ctx);
        let Management { is_add, threshold, addresses } = action;

        multisig.set_threshold(threshold);

        let length = vector::length(&addresses);
        if (length == 0) { 
            return
        } else if (is_add) {
            multisig.add_members(addresses);
        } else {
            multisig.remove_members(addresses);
        };
    }
}

