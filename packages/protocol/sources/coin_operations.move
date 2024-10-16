/// Handles coin merging and splitting for the multisig Accounts.
/// Any member can merge and split without approvals.
/// Used to prepare a Proposal with coins having the exact amount needed.

module account_protocol::coin_operations;

// === Imports ===

use sui::{
    coin::{Self, Coin},
    transfer::Receiving
};
use account_protocol::{
    account::Account,
    auth::Auth,
    version,
};

// === Structs ===

/// Witness authorizing access to the inner Account
public struct CoreDep() has drop;

// === [MEMBER] Public functions ===

/// Members can merge and split coins, no need for approvals
/// Returns the IDs to use in a following proposal, conserve the order
public fun merge_and_split<Config, Outcome, T: drop>(
    _auth: &Auth, // must be an authorized member, done before proposal
    account: &mut Account<Config, Outcome>, 
    to_merge: vector<Receiving<Coin<T>>>, // there can be only one coin if we just want to split
    to_split: vector<u64>, // there can be no amount if we just want to merge
    ctx: &mut TxContext
): vector<ID> { 
    // account.assert_is_member(ctx);

    // receive all coins
    let mut coins = vector::empty();
    to_merge.do!(|item| {
        let coin = account.receive(item, version::current());
        coins.push_back(coin);
    });

    let coin = merge(coins, ctx);
    let ids = split(account, coin, to_split, ctx);

    ids
}

fun merge<T: drop>(
    coins: vector<Coin<T>>, 
    ctx: &mut TxContext
): Coin<T> {
    let mut merged = coin::zero<T>(ctx);
    coins.do!(|coin| {
        merged.join(coin);
    });

    merged
}

fun split<Config, Outcome, T: drop>(
    account: &Account<Config, Outcome>, 
    mut coin: Coin<T>,
    amounts: vector<u64>, 
    ctx: &mut TxContext
): vector<ID> {
    let ids = amounts.map!(|amount| {
        let split = coin.split(amount, ctx);
        let id = object::id(&split);
        account.keep(split);
        id
    });
    account.keep(coin);

    ids
}