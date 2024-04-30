module sui_multisig::treasury {
    use std::string::String;
    use std::type_name;
    use sui::transfer::Receiving;
    use sui::coin::{Coin};
    use sui::balance;
    use sui::dynamic_field as df;
    use sui::object_table::{Self, ObjectTable};
    use sui_multisig::access_owned::{Self, Access};
    use sui_multisig::multisig::Multisig;

    // === Constants ===

    const COIN_TYPE: vector<u8> = b"0x0000000000000000000000000000000000000000000000000000000000000002::coin::Coin";

    // === Errors ===

    const EFungible: u64 = 0;

    // action to be held in a Proposal
    public struct Deposit has store {
        access_owned: Access,
    }

    /// Dynamic field key representing a balance of a particular coin type.
    public struct Fungible<phantom T> has copy, drop, store { }
    /// Dynamic field key representing a balance of a particular object type.
    public struct NonFungible<phantom T> has copy, drop, store { }

    // === Public mutative functions ===

    // step 1: propose to retrieve objects and attach them to the multisig
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

    // step 4: in the PTB loop over deposit functions
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

    // step 4 bis
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

    // /// Withdraw `amount` of coins of type `T` from `account`.
    // public fun withdraw<T>(account: &mut Account, amount: u64, ctx: &mut TxContext): Coin<T> {
    //     let account_balance_type = Asset<T>{};
    //     let account_uid = &mut account.id;
    //     // Make sure what we are withdrawing exists
    //     assert!(df::exists_(account_uid, account_balance_type), EBalanceDONE);
    //     let balance: &mut Coin<T> = df::borrow_mut(account_uid, account_balance_type);
    //     coin::split(balance, amount, ctx)
    // }

    // === Private functions ===

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

