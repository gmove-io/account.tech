/// This module provides the apis to stream a coin for a payment.
/// A payment has an amount to be paid at each interval, until the balance is empty.
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

#[error]
const EBalanceNotEmpty: vector<u8> = b"Stream must be emptied before destruction";
#[error]
const ETooEarly: vector<u8> = b"Cannot disburse payment yet";
#[error]
const EWrongStream: vector<u8> = b"Wrong stream for this Cap";
#[error]
const EVestingOver: vector<u8> = b"The balance has been fully emptied";

// === Structs ===

/// Balance for a payment is locked and sent automatically from backend or claimed manually by the recipient
public struct Stream<phantom CoinType> has key {
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

/// Cap enabling bearer to claim the payment
/// Helper object for discoverability
public struct ClaimCap has key {
    id: UID,
    // id of the stream to claim
    stream_id: ID,
}

/// [ACTION] creates a payment stream
/// coin and amount are managed in other action modules 
public struct VestingAction has store {
    // timestamp when coins can start to be claimed
    start_timestamp: u64,
    // timestamp when balance is totally unlocked
    end_timestamp: u64,
    // address to pay
    recipient: address,
}

// === [PROPOSAL] Public Functions ===

// step 1: propose the pay action from another module
// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)
// step 4: loop over `execute_transfer` it in PTB from the module implementing it

// step 5: bearer of ClaimCap can claim the payment
public fun claim<CoinType>(stream: &mut Stream<CoinType>, cap: &ClaimCap, clock: &Clock, ctx: &mut TxContext) {
    assert!(cap.stream_id == stream.id.to_inner(), EWrongStream);
    stream.disburse(clock, ctx);
}

// step 5(bis): backend send the coin to the recipient until balance is empty
public fun disburse<CoinType>(stream: &mut Stream<CoinType>, clock: &Clock, ctx: &mut TxContext) {
    assert!(clock.timestamp_ms() > stream.start_timestamp, ETooEarly);
    assert!(stream.balance.value() != 0, EVestingOver);

    let amount = if (clock.timestamp_ms() > stream.end_timestamp) {
        stream.balance.value()
    } else {
        let duration_remaining = stream.end_timestamp - stream.last_claimed;
        let duration_claimable = clock.timestamp_ms() - stream.last_claimed;
        
        if (duration_remaining != 0) stream.balance.value() * duration_claimable / duration_remaining else 0
    };

    let coin = coin::from_balance(stream.balance.split(amount), ctx);
    transfer::public_transfer(coin, stream.recipient);

    stream.last_claimed = clock.timestamp_ms();
}

// step 6: account member can cancel the payment (member only)
public fun cancel_payment<Config, Outcome, CoinType>(
    auth: Auth,
    stream: Stream<CoinType>, 
    account: &Account<Config, Outcome>,
    ctx: &mut TxContext
) {
    account.verify(auth);

    let Stream { id, balance, .. } = stream;
    id.delete();

    account.keep(coin::from_balance(balance, ctx));
}

// step 6 (bis): destroy the stream when balance is empty
public fun destroy_empty<CoinType>(stream: Stream<CoinType>) {
    let Stream { id, balance, .. } = stream;
    
    assert!(balance.value() == 0, EBalanceNotEmpty);
    balance.destroy_zero();
    id.delete();
}

public use fun destroy_cap as ClaimCap.destroy;
public fun destroy_cap(cap: ClaimCap) {
    let ClaimCap { id, .. } = cap;
    id.delete();
}

// === [ACTION] Public Functions ===

public fun new_vesting<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>,
    start_timestamp: u64,
    end_timestamp: u64,
    recipient: address,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    account.add_action(intent, VestingAction { start_timestamp, end_timestamp, recipient }, version_witness, intent_witness);
}

public fun do_vesting<Config, Outcome, CoinType, IW: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    coin: Coin<CoinType>,
    version_witness: VersionWitness,
    intent_witness: IW,
    ctx: &mut TxContext
) {    
    let action: &VestingAction = account.process_action(executable, version_witness, intent_witness);

    transfer::share_object(Stream<CoinType> { 
        id: object::new(ctx), 
        balance: coin.into_balance(), 
        last_claimed: 0,
        start_timestamp: action.start_timestamp,
        end_timestamp: action.end_timestamp,
        recipient: action.recipient
    });
}

public fun delete_vesting(expired: &mut Expired) {
    let VestingAction { .. } = expired.remove_action();
}

// === View Functions ===

public fun balance_value<CoinType>(self: &Stream<CoinType>): u64 {
    self.balance.value()
}

public fun last_claimed<CoinType>(self: &Stream<CoinType>): u64 {
    self.last_claimed
}

public fun start_timestamp<CoinType>(self: &Stream<CoinType>): u64 {
    self.start_timestamp
}

public fun end_timestamp<CoinType>(self: &Stream<CoinType>): u64 {
    self.end_timestamp
}

public fun recipient<CoinType>(self: &Stream<CoinType>): address {
    self.recipient
}

// === Test functions ===

#[test_only]
public fun create_stream_for_testing<CoinType>(
    coin: Coin<CoinType>, 
    start_timestamp: u64,
    end_timestamp: u64,
    recipient: address,
    ctx: &mut TxContext
): (ClaimCap, Stream<CoinType>) {
    let id = object::new(ctx);
    (
        ClaimCap {
            id: object::new(ctx),
            stream_id: id.to_inner()
        },
        Stream {
            id,
            balance: coin.into_balance(),
            last_claimed: 0,
            start_timestamp,
            end_timestamp,
            recipient
        }
    )
}