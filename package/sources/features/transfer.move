/// This module uses the access_owned and treasury apis to transfer assets that are owned or held by a Multisig.

module sui_multisig::transfer {
    use std::debug::print;
    use std::ascii::{Self, String};
    use sui::coin::Coin;
    use sui_multisig::treasury::{Self, Withdraw};
    use sui_multisig::multisig::Multisig;

    // === Errors ===

    const EDifferentLength: u64 = 0;
    const EWithdrawAllAssetsBefore: u64 = 1;

    // action to be held in a Proposal
    public struct Transfer has store {
        // sub action - assets to withdraw
        withdraw: Withdraw,
        // addresses to transfer to
        recipients: vector<address>
    }

    // step 1: propose to transfer objects and coins from the multisig
    public fun propose_transfer(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        asset_types: vector<String>, // TypeName of the object
        amounts: vector<u64>, // amount if fungible
        keys: vector<String>, // key if non-fungible (to find in the Table)
        transfer_to: vector<address>, // address to transfer to 
        ctx: &mut TxContext
    ) {
        assert!(asset_types.length() == transfer_to.length(), EDifferentLength);

        let withdraw = treasury::create_withdraw(asset_types, amounts, keys);
        let action = Transfer { withdraw, recipients: transfer_to };

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

    // step 4: in the PTB loop over withdraw and transfer functions and pop or transfer requested coins in Withdraw
    // transfer a Coin
    public fun transfer_fungible<C: drop>(
        multisig: &mut Multisig, 
        action: &mut Transfer, 
        ctx: &mut TxContext
    ) {
        let coin: Coin<C> = treasury::withdraw_fungible(multisig, &mut action.withdraw, ctx);
        transfer::public_transfer(coin, action.recipients.pop_back());
    }

    // transfer an object
    public fun transfer_non_fungible<O: key + store>(
        multisig: &mut Multisig, 
        action: &mut Transfer, 
    ) {
        let object: O = treasury::withdraw_non_fungible(multisig, &mut action.withdraw);
        transfer::public_transfer(object, action.recipients.pop_back());
    }

    // step 5: destroy the action if all vectors have been emptied
    public fun complete_withdraw(action: Transfer) {
        let Transfer { withdraw, recipients } = action;
        treasury::complete_withdraw(withdraw);
        assert!(recipients.is_empty(), EWithdrawAllAssetsBefore);
    }
}

