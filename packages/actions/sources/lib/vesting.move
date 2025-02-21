/// This module provides the apis to create a vesting.
/// A vesting has an amount to be paid at each interval, until the balance is empty.
/// It can be cancelled at any time by the account members.

module account_actions::vesting;

// === Imports ===

use sui::{
    balance::Balance,
    coin::{Self, Coin},
    clock::Clock,
};
use account_protocol::{
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
};

// === Errors ===

const EBalanceNotEmpty: u64 = 0;
const ETooEarly: u64 = 1;
const EWrongStream: u64 = 2;
const EVestingOver: u64 = 3;

// === Structs ===

/// Balance is locked and unlocked gradually to be claimed by the recipient.
public struct Vesting<phantom CoinType> has key {
    id: UID,
    // remaining balance to be sent
    balance: Balance<CoinType>,
    // timestamp of the last payment
    last_claimed: u64,
    // timestamp when coins can start to be claimed
    start_timestamp: u64,
    // timestamp when balance is totally unlocked
    end_timestamp: u64,
    // address to pay
    recipient: address,
}

/// Cap enabling bearer to claim the vesting.
/// Helper object for discoverability.
public struct ClaimCap has key {
    id: UID,
    // id of the vesting to claim
    vesting_id: ID,
}

/// Action creating a vesting.
/// Associated balance is managed in other action modules.
public struct VestAction has store {
    // timestamp when coins can start to be claimed
    start_timestamp: u64,
    // timestamp when balance is totally unlocked
    end_timestamp: u64,
    // address to pay
    recipient: address,
}

// === Public Functions ===

// Bearer of ClaimCap can claim the vesting.
public fun claim<CoinType>(vesting: &mut Vesting<CoinType>, cap: &ClaimCap, clock: &Clock, ctx: &mut TxContext) {
    assert!(cap.vesting_id == vesting.id.to_inner(), EWrongStream);
    assert!(clock.timestamp_ms() > vesting.start_timestamp, ETooEarly);
    assert!(vesting.balance.value() != 0, EVestingOver);

    let amount = if (clock.timestamp_ms() > vesting.end_timestamp) {
        vesting.balance.value()
    } else {
        let duration_remaining = vesting.end_timestamp - vesting.last_claimed;
        let duration_claimable = clock.timestamp_ms() - vesting.last_claimed;
        
        if (duration_remaining != 0) vesting.balance.value() * duration_claimable / duration_remaining else 0
    };

    let coin = coin::from_balance(vesting.balance.split(amount), ctx);
    transfer::public_transfer(coin, vesting.recipient);

    vesting.last_claimed = clock.timestamp_ms();
}

// Authorized address can cancel the vesting.
public fun cancel_payment<Config, Outcome, CoinType>(
    auth: Auth,
    vesting: Vesting<CoinType>, 
    account: &Account<Config, Outcome>,
    ctx: &mut TxContext
) {
    account.verify(auth);

    let Vesting { id, balance, .. } = vesting;
    id.delete();

    account.keep(coin::from_balance(balance, ctx));
}

// Destroys the vesting when balance is empty.
public fun destroy_empty<CoinType>(vesting: Vesting<CoinType>) {
    let Vesting { id, balance, .. } = vesting;
    
    assert!(balance.value() == 0, EBalanceNotEmpty);
    balance.destroy_zero();
    id.delete();
}

// Destroys the claim cap.
public use fun destroy_cap as ClaimCap.destroy;
public fun destroy_cap(cap: ClaimCap) {
    let ClaimCap { id, .. } = cap;
    id.delete();
}

// Intent functions

/// Creates a VestAction and adds it to an intent.
public fun new_vest<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>,
    start_timestamp: u64,
    end_timestamp: u64,
    recipient: address,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    account.add_action(intent, VestAction { start_timestamp, end_timestamp, recipient }, version_witness, intent_witness);
}

/// Processes a VestAction and creates a vesting.
public fun do_vest<Config, Outcome, CoinType, IW: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    coin: Coin<CoinType>,
    version_witness: VersionWitness,
    intent_witness: IW,
    ctx: &mut TxContext
) {    
    let action: &VestAction = account.process_action(executable, version_witness, intent_witness);

    transfer::share_object(Vesting<CoinType> { 
        id: object::new(ctx), 
        balance: coin.into_balance(), 
        last_claimed: 0,
        start_timestamp: action.start_timestamp,
        end_timestamp: action.end_timestamp,
        recipient: action.recipient
    });
}

/// Deletes a VestAction from an expired intent.
public fun delete_vest(expired: &mut Expired) {
    let VestAction { .. } = expired.remove_action();
}

// === View Functions ===

/// Returns the balance value of a vesting.
public fun balance_value<CoinType>(self: &Vesting<CoinType>): u64 {
    self.balance.value()
}

/// Returns the last claimed timestamp of a vesting.
public fun last_claimed<CoinType>(self: &Vesting<CoinType>): u64 {
    self.last_claimed
}

/// Returns the start timestamp of a vesting.
public fun start_timestamp<CoinType>(self: &Vesting<CoinType>): u64 {
    self.start_timestamp
}

/// Returns the end timestamp of a vesting.
public fun end_timestamp<CoinType>(self: &Vesting<CoinType>): u64 {
    self.end_timestamp
}

/// Returns the recipient of a vesting.
public fun recipient<CoinType>(self: &Vesting<CoinType>): address {
    self.recipient
}

// === Test functions ===

#[test_only]
public fun create_vesting_for_testing<CoinType>(
    coin: Coin<CoinType>, 
    start_timestamp: u64,
    end_timestamp: u64,
    recipient: address,
    ctx: &mut TxContext
): (ClaimCap, Vesting<CoinType>) {
    let id = object::new(ctx);
    (
        ClaimCap {
            id: object::new(ctx),
            vesting_id: id.to_inner()
        },
        Vesting {
            id,
            balance: coin.into_balance(),
            last_claimed: 0,
            start_timestamp,
            end_timestamp,
            recipient
        }
    )
}