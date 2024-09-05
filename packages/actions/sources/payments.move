/// This module uses the owned apis to stream a coin for a payment.
/// A payment has an amount to be paid at each interval, until the balance is empty.
/// It can be cancelled by multisig members.

module kraken_actions::payments;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    balance::Balance,
    coin::{Self, Coin}
};
use kraken_multisig::multisig::{Multisig, Executable, Proposal};
use kraken_actions::owned;

// === Errors ===

const ECompletePaymentBefore: u64 = 0;
const EPayTooEarly: u64 = 1;
const EPayNotExecuted: u64 = 2;

// === Structs ===

// delegated issuer verifying a proposal is destroyed in the module where it was created
public struct Issuer has copy, drop {}

// [ACTION]
public struct Pay has store {
    // amount to pay at each due date
    amount: u64,
    // number of epochs between each payment
    interval: u64,
    // address to pay
    recipient: address,
}

// balance for a payment is locked and sent automatically from backend
public struct Stream<phantom C: drop> has key {
    id: UID,
    // remaining balance to be sent
    balance: Balance<C>,
    // amount to pay at each due date
    amount: u64,
    // number of epochs between each payment
    interval: u64,
    // epoch of the last payment
    last_epoch: u64,
    // address to pay
    recipient: address,
}

// === [PROPOSAL] Public Functions ===

// step 1: propose to create a Stream with a specific amount to be paid at each interval
public fun propose_pay(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin: ID, // must have the total amount to be paid
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_pay(proposal_mut, coin, amount, interval, recipient);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_pay<C: drop>(
    mut executable: Executable, 
    multisig: &mut Multisig, 
    receiving: Receiving<Coin<C>>,
    ctx: &mut TxContext
) {
    pay(&mut executable, multisig, receiving, Issuer {}, ctx);

    destroy_pay(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// step 5: backend send the coin to the recipient until balance is empty
public fun disburse<C: drop>(stream: &mut Stream<C>, ctx: &mut TxContext) {
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
public fun destroy_empty_stream<C: drop>(stream: Stream<C>) {
    let Stream { id, balance, .. } = stream;
    
    assert!(balance.value() == 0, ECompletePaymentBefore);
    balance.destroy_zero();
    id.delete();
}

// step 6 (bis): multisig member can cancel the payment (member only)
public fun cancel_payment_stream<C: drop>(
    stream: Stream<C>, 
    multisig: &Multisig,
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    let Stream { id, balance, .. } = stream;
    id.delete();

    transfer::public_transfer(
        coin::from_balance(balance, ctx), 
        multisig.addr()
    );
}

// === [ACTION] Public Functions ===

public fun new_pay(proposal: &mut Proposal, coin: ID, amount: u64, interval: u64, recipient: address) {
    owned::new_withdraw(proposal, vector[coin]);
    proposal.add_action(Pay { amount, interval, recipient });
}

public fun pay<I: copy + drop, C: drop>(
    executable: &mut Executable, 
    multisig: &mut Multisig, 
    receiving: Receiving<Coin<C>>,
    issuer: I,
    ctx: &mut TxContext
) {    
    let coin = owned::withdraw(executable, multisig, receiving, issuer);
    let pay_mut: &mut Pay = executable.action_mut(issuer, multisig.addr());

    let stream = Stream<C> { 
        id: object::new(ctx), 
        balance: coin.into_balance(), 
        amount: pay_mut.amount,
        interval: pay_mut.interval,
        last_epoch: 0,
        recipient: pay_mut.recipient
    };
    transfer::share_object(stream);

    pay_mut.amount = 0; // clean to ensure action is executed only once
}

public fun destroy_pay<I: copy + drop>(executable: &mut Executable, issuer: I): address {
    owned::destroy_withdraw(executable, issuer);
    let Pay { amount, recipient, .. } = executable.remove_action(issuer);
    assert!(amount == 0, EPayNotExecuted);

    recipient
}

// === View Functions ===

public fun balance<C: drop>(self: &Stream<C>): u64 {
    self.balance.value()
}

public fun amount<C: drop>(self: &Stream<C>): u64 {
    self.amount
}

public fun interval<C: drop>(self: &Stream<C>): u64 {
    self.interval
}

public fun last_epoch<C: drop>(self: &Stream<C>): u64 {
    self.last_epoch
}

public fun recipient<C: drop>(self: &Stream<C>): address {
    self.recipient
}

