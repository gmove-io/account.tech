module sui_multisig::treasury {
    use std::ascii::String;
    use std::type_name;
    use sui::transfer::Receiving;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::dynamic_field as df;
    use sui::object_table::{Self, ObjectTable};
    use sui_multisig::access_owned::{Self, Access};
    use sui_multisig::multisig::Multisig;

    // === Constants ===

    const COIN_TYPE: vector<u8> = b"0x0000000000000000000000000000000000000000000000000000000000000002::coin::Coin";

    // === Errors ===

    const EFungible: u64 = 0;
    const EDifferentLength: u64 = 1;
    const EWrongFungibleType: u64 = 2;
    const EFungibleDoesntExist: u64 = 3;
    const EWithdrawAllAssetsBefore: u64 = 4;
    const EMustBeTransferred: u64 = 5;

    // action to be held in a Proposal
    public struct Deposit has store {
        // sub action
        access_owned: Access,
    }

    // action to be held in a Proposal
    public struct Withdraw has store {
        // assets to withdraw
        assets: vector<Asset>,
    }

    // asset to withdrawn from the treasury
    public struct Asset has copy, drop, store {
        asset_type: String,
        amount: u64,
        key: String,
        transfer_to: address,
    }

    /// Dynamic field key representing a balance of a particular coin type.
    public struct Fungible<phantom T> has copy, drop, store { }
    /// Dynamic field key representing a balance of a particular object type.
    public struct NonFungible<phantom T> has copy, drop, store { }

    // === Public functions ===

    // destroy empty Fungible balance dof
    public fun clean_balance<C: drop>(multisig: &mut Multisig) {
        let balance: Balance<C> = df::remove(multisig.uid_mut(), Fungible<C>{});
        balance.destroy_zero();
    }

    // destroy empty NonFungible table dof
    public fun clean_table<O: key + store>(multisig: &mut Multisig) {
        let table: ObjectTable<String, O> = df::remove(multisig.uid_mut(), NonFungible<O>{});
        table.destroy_empty();
    }

    // === Multisig functions ===

    // step 1: propose to retrieve objects and store them in the multisig via dof
    public fun propose_deposit(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        object_ids: vector<ID>,
        ctx: &mut TxContext
    ) {
        let access_owned = access_owned::new_access(vector[], object_ids);
        let action = Deposit { access_owned };

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
    public fun deposit_fungible<C: drop>(
        multisig: &mut Multisig, 
        action: &mut Deposit, 
        received: Receiving<Coin<C>>
    ) {
        let owned = action.access_owned.pop_owned();
        let coin = access_owned::withdraw(multisig, owned, received);
        let balance = coin.into_balance();

        if (df::exists_(multisig.uid_mut(), Fungible<C>{})) {
            let fungible = df::borrow_mut(multisig.uid_mut(), Fungible<C>{});
            balance::join(fungible, balance);
        } else {
            df::add(multisig.uid_mut(), Fungible<C>{}, balance);
        }
    }

    // step 4 bis: in the PTB loop over deposit functions and pop back Owned in Deposit
    public fun deposit_non_fungible<O: key + store>(
        multisig: &mut Multisig, 
        action: &mut Deposit, 
        received: Receiving<O>, 
        key: String,
        ctx: &mut TxContext
    ) {
        assert_is_non_fungible<O>();
        let owned = action.access_owned.pop_owned();
        let object = access_owned::withdraw(multisig, owned, received);

        if (df::exists_(multisig.uid_mut(), NonFungible<O>{})) {
            let table: &mut ObjectTable<String, O> = 
                df::borrow_mut(multisig.uid_mut(), NonFungible<O>{});
            table.add(key, object);
        } else {
            let mut table = object_table::new(ctx);
            table.add(key, object);
            df::add(multisig.uid_mut(), NonFungible<O>{}, table);
        }
    }

    // step 5: destroy the action
    public fun complete_deposit(action: Deposit) {
        let Deposit { access_owned } = action;
        access_owned::complete(access_owned);
    }

    // step 1: propose to withdraw objects and coins from the multisig
    public fun propose_withdraw(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        mut asset_types: vector<String>, // TypeName of the object
        mut amounts: vector<u64>, // amount if fungible
        mut keys: vector<String>, // key if non-fungible (to find in the Table)
        mut transfer_to: vector<address>, // address to transfer to (@0x0 it is withdrawn)
        ctx: &mut TxContext
    ) {
        assert!(
            asset_types.length() == amounts.length() &&
            asset_types.length() == keys.length() &&
            asset_types.length() == transfer_to.length(),
            EDifferentLength
        );

        let mut assets = vector[];
        while (!asset_types.is_empty()) {
            let asset_type = asset_types.pop_back();
            let amount = amounts.pop_back();
            let key = keys.pop_back();
            let transfer_to = transfer_to.pop_back();
            assets.push_back(Asset { asset_type, amount, key, transfer_to });
        };

        let action = Withdraw { assets };

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

    // step 4: in the PTB loop over withdraw and pop requested coins in Withdraw
    public fun withdraw_fungible<C: drop>(
        multisig: &mut Multisig, 
        action: &mut Withdraw, 
        ctx: &mut TxContext
    ): Coin<C> {
        let addr = action.assets[action.assets.length() - 1].transfer_to;
        assert!(addr == @0x0, EMustBeTransferred);
        withdraw_fungible_impl(multisig, action, ctx)
    }

    // step 4 bis: in the PTB loop over withdraw and pop requested objects in Withdraw
    public fun withdraw_non_fungible<O: key + store>(
        multisig: &mut Multisig, 
        action: &mut Withdraw, 
    ): O {
        let addr = action.assets[action.assets.length() - 1].transfer_to;
        assert!(addr == @0x0, EMustBeTransferred);
        withdraw_non_fungible_impl(multisig, action)
    }

    // step 4 bis: in the PTB loop over transfer and pop requested coins in Withdraw
    public fun transfer_fungible<C: drop>(
        multisig: &mut Multisig, 
        action: &mut Withdraw, 
        ctx: &mut TxContext
    ) {
        let addr = action.assets[action.assets.length() - 1].transfer_to;
        let coin: Coin<C> = withdraw_fungible_impl(multisig, action, ctx);
        transfer::public_transfer(coin, addr);
    }

    // step 4 bis: in the PTB loop over transfer and pop requested objects in Withdraw
    public fun transfer_non_fungible<O: key + store>(
        multisig: &mut Multisig, 
        action: &mut Withdraw, 
    ) {
        let addr = action.assets[action.assets.length() - 1].transfer_to;
        let object: O = withdraw_non_fungible_impl(multisig, action);
        transfer::public_transfer(object, addr);
    }

    // step 5: destroy the action if vector of Asset has been emptied
    public fun complete_withdraw(action: Withdraw) {
        let Withdraw { assets } = action;
        assert!(assets.is_empty(), EWithdrawAllAssetsBefore);
    }

    // === Private functions ===

    fun withdraw_fungible_impl<C: drop>(
        multisig: &mut Multisig, 
        action: &mut Withdraw, 
        ctx: &mut TxContext
    ): Coin<C> {
        let Asset { asset_type, amount, key: _, transfer_to: _ } = action.assets.pop_back();
        assert!(asset_type == type_name::get<C>().into_string(), EWrongFungibleType);
        assert!((df::exists_(multisig.uid_mut(), Fungible<C>{})), EFungibleDoesntExist);
        
        let fungible: &mut Balance<C> = df::borrow_mut(multisig.uid_mut(), Fungible<C>{});
        coin::from_balance(fungible.split(amount), ctx)
    }

    // step 4: in the PTB loop over withdraw and pop requested objects in Withdraw
    fun withdraw_non_fungible_impl<O: key + store>(
        multisig: &mut Multisig, 
        action: &mut Withdraw, 
    ): O {
        let Asset { asset_type, amount: _, key, transfer_to: _ } = action.assets.pop_back();
        assert!(asset_type == type_name::get<O>().into_string(), EWrongFungibleType);
        assert!((df::exists_(multisig.uid_mut(), NonFungible<O>{})), EFungibleDoesntExist);
        
        let table: &mut ObjectTable<String, O> = df::borrow_mut(multisig.uid_mut(), NonFungible<O>{});
        table.remove(key)
    }

    fun assert_is_non_fungible<T: key + store>() {
        let type_name = type_name::get<T>();
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
        assert!(count == ref.length(), EFungible);
    }
}

