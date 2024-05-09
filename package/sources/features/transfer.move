/// This module uses the access_owned and store_asset apis to transfer assets.
/// It can be assets stored in the multisig, meaning an amount can be chosen for coins.Access
/// Or owned obejcts by the multisig, meaning the objectis directly trsnaferred by the multisig.

module sui_multisig::transfer {
    use std::debug::print;
    use std::string::{Self, String};
    use sui::transfer::Receiving;
    use sui::coin::Coin;
    use sui_multisig::store_asset::{Self, Withdraw};
    use sui_multisig::store_coin;
    use sui_multisig::access_owned::{Self, Access};
    use sui_multisig::multisig::Multisig;

    // === Errors ===

    const EDifferentLength: u64 = 0;
    const ETransferAllAssetsBefore: u64 = 1;

    // action to be held in a Proposal
    public struct TransferStored has store {
        // sub action - assets to withdraw
        request_withdraw: Withdraw,
        // addresses to transfer to
        recipients: vector<address>
    }

    public struct TransferOwned has store {
        // sub action - owned objects to access
        request_access: Access,
        // addresses to transfer to
        recipients: vector<address>
    }

    // step 1: propose to transfer objects and coins from the multisig
    public fun propose_transfer_stored(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        asset_types: vector<String>, // TypeName of the object
        amounts: vector<u64>, // amount if fungible
        keys: vector<String>, // key if non-fungible (to find in the Table)
        recipients: vector<address>, // address to transfer to 
        ctx: &mut TxContext
    ) {
        assert!(asset_types.length() == recipients.length(), EDifferentLength);

        let request_withdraw = store_asset::new_withdraw(asset_types, amounts, keys);
        let action = TransferStored { request_withdraw, recipients: recipients };

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
    public fun transfer_stored_fungible<C: drop>(
        multisig: &mut Multisig, 
        action: &mut TransferStored, 
        ctx: &mut TxContext
    ) {
        let coin: Coin<C> = 
            store_coin::withdraw(multisig, &mut action.request_withdraw, ctx);
        transfer::public_transfer(coin, action.recipients.pop_back());
    }

    // transfer an object
    public fun transfer_stored_non_fungible<O: key + store>(
        multisig: &mut Multisig, 
        action: &mut TransferStored, 
    ) {
        // TODO
        // let object: O = 
        //     store_asset::withdraw_non_fungible(multisig, &mut action.request_withdraw);
        // transfer::public_transfer(object, action.recipients.pop_back());
    }

    // step 5: destroy the action if all vectors have been emptied
    public fun complete_stored_transfer(action: TransferStored) {
        let TransferStored { request_withdraw, recipients } = action;
        store_asset::complete_withdraw(request_withdraw);
        assert!(recipients.is_empty(), ETransferAllAssetsBefore);
    }


    // step 1: propose to retrieve owned objects and store them in the multisig via dof
    public fun propose_transfer_owned(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        object_ids: vector<ID>,
        recipients: vector<address>,
        ctx: &mut TxContext
    ) {
        // create a new access with the objects to withdraw (none to borrow)
        let request_access = access_owned::new_access(vector[], object_ids);
        let action = TransferOwned { request_access, recipients };
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

    // step 4: in the PTB loop over deposit functions and pop back Owned in Deposit
    // attach Balances as multisig dof (merge if type already exists)
    public fun transfer_owned<T: key + store>(
        multisig: &mut Multisig, 
        action: &mut TransferOwned, 
        received: Receiving<T>
    ) {
        let owned = action.request_access.pop_owned();
        let coin = access_owned::take(multisig, owned, received);
        transfer::public_transfer(coin, action.recipients.pop_back());
    }

    // step 5: destroy the action
    public fun complete_transfer_owned(action: TransferOwned) {
        let TransferOwned { request_access, recipients } = action;
        assert!(recipients.is_empty(), ETransferAllAssetsBefore);
        request_access.complete();
    }
}

