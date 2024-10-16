/// This module provides the apis to stream a coin for a payment.
/// A payment has an amount to be paid at each interval, until the balance is empty.
/// It can be cancelled at any time by the account members.

module account_actions::payments;

// === Imports ===

use std::type_name::TypeName;
use sui::{
    balance::Balance,
    coin::{Self, Coin},
};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth,
};

// === Errors ===

#[error]
const ECompletePaymentBefore: vector<u8> = b"Stream must be emptied before destruction";
#[error]
const EPayTooEarly: vector<u8> = b"Cannot disburse payment yet";
#[error]
const EWrongStream: vector<u8> = b"Wrong stream for this Cap";

// === Structs ===

/// Balance for a payment is locked and sent automatically from backend or claimed manually by the recipient
public struct Stream<phantom CoinType> has key {
    id: UID,
    // remaining balance to be sent
    balance: Balance<CoinType>,
    // amount to pay at each due date
    amount: u64,
    // number of epochs between each payment
    interval: u64,
    // epoch of the last payment
    last_epoch: u64,
    // address to pay
    recipient: address,
}

/// Cap enabling bearer to claim the payment
public struct ClaimCap has key {
    id: UID,
    // id of the stream to claim
    stream_id: ID,
}

/// [ACTION] creates a payment stream
public struct PayAction has store {
    // amount to pay at each due date
    amount: u64,
    // number of epochs between each payment
    interval: u64,
    // address to pay
    recipient: address,
}

// === [PROPOSAL] Public Functions ===

// step 1: propose the pay action from another module
// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)
// step 4: loop over `execute_transfer` it in PTB from the module implementing it

// step 5: bearer of ClaimCap can claim the payment
public fun claim<CoinType>(stream: &mut Stream<CoinType>, cap: &ClaimCap, ctx: &mut TxContext) {
    assert!(cap.stream_id == stream.id.to_inner(), EWrongStream);
    stream.disburse(ctx);
}

// step 5(bis): backend send the coin to the recipient until balance is empty
public fun disburse<CoinType>(stream: &mut Stream<CoinType>, ctx: &mut TxContext) {
    assert!(ctx.epoch() > stream.last_epoch + stream.interval, EPayTooEarly);

    let amount = if (stream.balance.value() < stream.amount) {
        stream.balance.value()
    } else {
        stream.amount
    };
    let coin = coin::from_balance(stream.balance.split(amount), ctx);

    transfer::public_transfer(coin, stream.recipient);
    stream.last_epoch = ctx.epoch();
}

// step 6: destroy the stream when balance is empty
public fun destroy_empty_stream<CoinType>(stream: Stream<CoinType>) {
    let Stream { id, balance, .. } = stream;
    
    assert!(balance.value() == 0, ECompletePaymentBefore);
    balance.destroy_zero();
    id.delete();
}

// step 6 (bis): account member can cancel the payment (member only)
public fun cancel_payment_stream<Config, Outcome, CoinType>(
    auth: Auth,
    stream: Stream<CoinType>, 
    account: &Account<Config, Outcome>,
    ctx: &mut TxContext
) {
    auth.verify(account.addr());

    let Stream { id, balance, .. } = stream;
    id.delete();

    account.keep(coin::from_balance(balance, ctx));
}

// === [ACTION] Public Functions ===

public fun new_pay<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    amount: u64,
    interval: u64,
    recipient: address,
    witness: W,
) {
    proposal.add_action(PayAction { amount, interval, recipient }, witness);
}

public fun pay<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    coin: Coin<CoinType>,
    version: TypeName,
    witness: W,
    ctx: &mut TxContext
) {    
    let pay_action = executable.load<PayAction, W>(account.addr(), version, witness);

    transfer::share_object(Stream<CoinType> { 
        id: object::new(ctx), 
        balance: coin.into_balance(), 
        amount: pay_action.amount,
        interval: pay_action.interval,
        last_epoch: 0,
        recipient: pay_action.recipient
    });
    
    executable.process<PayAction, W>(version, witness);
}

public fun destroy_pay<W: drop>(executable: &mut Executable, version: TypeName, witness: W) {
    let PayAction { .. } = executable.cleanup(version, witness);
}

public fun delete_pay_action<Outcome>(expired: &mut Expired<Outcome>) {
    let PayAction { .. } = expired.remove_expired_action();
}

// === View Functions ===

public fun balance<CoinType>(self: &Stream<CoinType>): u64 {
    self.balance.value()
}

public fun amount<CoinType>(self: &Stream<CoinType>): u64 {
    self.amount
}

public fun interval<CoinType>(self: &Stream<CoinType>): u64 {
    self.interval
}

public fun last_epoch<CoinType>(self: &Stream<CoinType>): u64 {
    self.last_epoch
}

public fun recipient<CoinType>(self: &Stream<CoinType>): address {
    self.recipient
}