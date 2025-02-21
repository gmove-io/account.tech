/// This module allows objects owned by the account to be accessed through intents in a secure way.
/// The objects can be taken only via an WithdrawAction action which uses Transfer to Object (TTO).
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.

module account_protocol::owned;

// === Imports ===

use sui::{
    coin::{Self, Coin},
    transfer::Receiving
};
use account_protocol::{
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
};


// === Errors ===

const EWrongObject: u64 = 0;
const EObjectLocked: u64 = 1;

// === Structs ===

/// Action guarding access to account owned objects which can only be received via this action
public struct WithdrawAction has store {
    // the owned objects we want to access
    object_id: ID,
}

// === Public functions ===

/// Creates a new WithdrawAction and add it to an intent
public fun new_withdraw<Config, Outcome, IW: copy + drop>(
    intent: &mut Intent<Outcome>, 
    account: &mut Account<Config, Outcome>,
    object_id: ID, 
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    account.lock_object(object_id);
    account.add_action(intent, WithdrawAction { object_id }, version_witness, intent_witness);
}

/// Executes a WithdrawAction and returns the object
public fun do_withdraw<Config, Outcome, T: key + store, IW: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<T>,
    version_witness: VersionWitness,
    intent_witness: IW,
): T {
    let action: &WithdrawAction = account.process_action(executable, version_witness, intent_witness);
    assert!(receiving.receiving_object_id() == action.object_id, EWrongObject);
    
    account.receive(receiving)
}

/// Deletes a WithdrawAction from an expired intent
public fun delete_withdraw<Config, Outcome>(
    expired: &mut Expired, 
    account: &mut Account<Config, Outcome>,
) {
    let WithdrawAction { object_id } = expired.remove_action();
    account.unlock_object(object_id);
}

// Coin operations

/// Authorized addresses can merge and split coins.
/// Returns the IDs to use in a following intent, conserves the order.
public fun merge_and_split<Config, Outcome, CoinType>(
    _auth: &Auth, 
    account: &mut Account<Config, Outcome>, 
    to_merge: vector<Receiving<Coin<CoinType>>>, // there can be only one coin if we just want to split
    to_split: vector<u64>, // there can be no amount if we just want to merge
    ctx: &mut TxContext
): vector<ID> { 
    // receive all coins
    let mut coins = vector::empty();
    to_merge.do!(|item| {
        let coin = account.receive(item);
        coins.push_back(coin);
    });

    let coin = merge(account, coins, ctx);
    let ids = split(account, coin, to_split, ctx);

    ids
}

fun merge<Config, Outcome, CoinType>(
    account: &Account<Config, Outcome>,
    coins: vector<Coin<CoinType>>, 
    ctx: &mut TxContext
): Coin<CoinType> {
    let mut merged = coin::zero<CoinType>(ctx);
    coins.do!(|coin| {
        assert!(!account.intents().locked().contains(&object::id(&coin)), EObjectLocked);
        merged.join(coin);
    });

    merged
}

fun split<Config, Outcome, CoinType>(
    account: &Account<Config, Outcome>, 
    mut coin: Coin<CoinType>,
    amounts: vector<u64>, 
    ctx: &mut TxContext
): vector<ID> {
    assert!(!account.intents().locked().contains(&object::id(&coin)), EObjectLocked);

    let ids = amounts.map!(|amount| {
        let split = coin.split(amount, ctx);
        let id = object::id(&split);
        account.keep(split);
        id
    });
    account.keep(coin);

    ids
}
