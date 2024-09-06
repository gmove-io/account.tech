/// Handles coin merging and splitting for the multisig.
/// Any member can merge and split without approvals.
/// Used to prepare a Proposal with coins having the exact amount needed.

module kraken_multisig::coin_operations;

// === Imports ===

use sui::{
    coin::{Self, Coin},
    transfer::Receiving
};
use kraken_multisig::multisig::Multisig;

// === Structs ===

public struct Issuer has copy, drop {}

// === [MEMBER] Public functions ===

// members can merge and split coins, no need for approvals
// returns the IDs to use in a following proposal, sorted by "to_split" amounts
public fun merge_and_split<T: drop>(
    multisig: &mut Multisig, 
    mut to_merge: vector<Receiving<Coin<T>>>, // there can be only one coin if we just want to split
    to_split: vector<u64>, // there can be no amount if we just want to merge
    ctx: &mut TxContext
): vector<ID> { 
    multisig.assert_is_member(ctx);

    // receive all coins
    let mut coins = vector::empty();
    while (!to_merge.is_empty()) {
        let item = to_merge.pop_back();
        let coin = multisig.receive(Issuer {}, item);
        coins.push_back(coin);
    };
    to_merge.destroy_empty();

    let coin = merge(coins, ctx);
    let ids = split(multisig, coin, to_split, ctx);

    ids
}

fun merge<T: drop>(
    mut coins: vector<Coin<T>>, 
    ctx: &mut TxContext
): Coin<T> {
    let mut merged = coin::zero<T>(ctx);
    while (!coins.is_empty()) {
        merged.join(coins.pop_back());
    };
    coins.destroy_empty();

    merged
}

fun split<T: drop>(
    multisig: &Multisig, 
    mut coin: Coin<T>,
    mut amounts: vector<u64>, 
    ctx: &mut TxContext
): vector<ID> {
    let mut ids = vector::empty();
    while (!amounts.is_empty()) {
        let split = coin.split(amounts.pop_back(), ctx);
        ids.push_back(object::id(&split));
        transfer::public_transfer(split, multisig.addr());
    };
    transfer::public_transfer(coin, multisig.addr());

    ids
}