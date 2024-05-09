/// This module leverages the access_owned api and allows to deposit and withdraw assets from a Multisig.
/// It uses Dynamic Fields to store and sort assets initially owned by the Multisig.
/// The assets are stored in the Multisig's as Balances (for Coin) or ObjectTables (for other Objects).
/// These assets can be withdrawn (and returned in PTB) or transferred to another address.

module sui_multisig::store_coin {
    use std::debug::print;
    use std::string::{Self, String};
    use std::type_name;
    use sui::transfer::Receiving;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::dynamic_field as df;
    use sui::object_table::{Self, ObjectTable};
    use sui_multisig::access_owned::{Self, Access};
    use sui_multisig::multisig::Multisig;
    use sui_multisig::store_asset::{Self, Stored, Deposit, Withdraw};

    // === Constants ===

    const COIN_PREFIX: vector<u8> = b"COIN";
    const COIN_TYPE: vector<u8> = b"0000000000000000000000000000000000000000000000000000000000000002::coin::Coin";

    // === Errors ===

    const EFungible: u64 = 0;
    const EDifferentLength: u64 = 1;
    const EWrongFungibleType: u64 = 2;
    const EFungibleDoesntExist: u64 = 3;
    const EWrongNonFungibleType: u64 = 4;
    const ENonFungibleDoesntExist: u64 = 5;
    const EWithdrawAllAssetsBefore: u64 = 6;

    // === Multisig functions ===
    public fun deposit<C: drop>(
        multisig: &mut Multisig, 
        action: &mut Deposit, 
        received: Receiving<Coin<C>>
    ) {
        let key = store_asset::vault_key<C>(COIN_PREFIX);
        let (name, description, asset) = action.pop_from_deposit(multisig, received);

        if (!df::exists_(multisig.uid_mut(), key)) {
            store_asset::create_vault<C, Balance<C>>(multisig, name, description, balance::zero<C>());
        };

        let mut container = store_asset::borrow_container_mut<C, Balance<C>>(multisig);
        container.join(coin::into_balance(asset));
    }
    
    public fun withdraw<C: drop>(
        multisig: &mut Multisig, 
        action: &mut Withdraw, 
        ctx: &mut TxContext
    ): Coin<C> {
        let key = store_asset::vault_key<C>(COIN_PREFIX);
        let (asset_type, amount, key) = action.pop_from_withdraw();
        assert!(asset_type == string::from_ascii(type_name::get<C>().into_string()), EWrongFungibleType);
        assert!((df::exists_(multisig.uid_mut(), key)), EFungibleDoesntExist);
        
        let balance: &mut Balance<C> = df::borrow_mut(multisig.uid_mut(), key);
        let coin = coin::from_balance(balance.split(amount), ctx);
        if (balance.value() == 0) {
            let bal: Balance<C> = df::remove(multisig.uid_mut(), key);
            bal.destroy_zero();
        };
        
        coin
    }

    // === Private functions ===

    fun assert_is_non_fungible<O: key + store>() {
        let type_name = type_name::get<O>();
        let name = type_name.into_string().into_bytes();
        let ref = COIN_TYPE;

        let mut i = 0;
        let mut count = 0;
        while (i < ref.length()) {
            if (name[i] == ref[i]) {
                count = count + 1;
            };
            i = i + 1;
        };
        assert!(count != ref.length(), EFungible);
    }
}

