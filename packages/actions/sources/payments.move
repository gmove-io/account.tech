/// This module uses the owned apis to stream a coin for a payment.
/// A payment has an amount to be paid at each interval, until the balance is empty.
/// It can be cancelled at any time by the multisig members.

module kraken_actions::payments;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    balance::Balance,
    coin::{Self, Coin},
    event,
};
use kraken_multisig::{
    multisig::Multisig,
    proposals::Proposal,
    executable::Executable
};
use kraken_actions::{
    owned::{Self, WithdrawAction},
    treasury::{Self, SpendAction},
    currency::{Self, MintAction}
};

// === Errors ===

const ECompletePaymentBefore: u64 = 0;
const EPayTooEarly: u64 = 1;
const EPayNotExecuted: u64 = 2;
const EReceivingShouldBeSome: u64 = 3;
const EWrongStream: u64 = 4;
const EInvalidExecutable: u64 = 5;

// === Events ===

public struct StreamCreated has copy, drop, store {
    stream_id: ID,
    amount: u64,
    interval: u64,
    recipient: address,
}

// === Structs ===

/// Balance for a payment is locked and sent automatically from backend or claimed manually by the recipient
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

/// Cap enabling bearer to claim the payment
public struct ClaimCap has key {
    id: UID,
    // id of the stream to claim
    stream_id: ID,
}

/// [PROPOSAL] streams an amount of coin to be paid at specific intervals
public struct PayProposal has copy, drop {}

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

// step 1: propose to create a Stream with a specific amount to be paid at each interval
public fun propose_pay_owned(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin: ID, // coin owned by the multisig, must have the total amount to be paid
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        PayProposal {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_pay_owned(proposal_mut, coin, amount, interval, recipient);
}

// step 1(bis): same but from a treasury
public fun propose_pay_treasury(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    treasury_name: String, 
    coin_type: String, 
    coin_amount: u64, 
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        PayProposal {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_pay_treasury(proposal_mut, treasury_name, coin_type, coin_amount, amount, interval, recipient);
}

// step 1(bis): same but from a minted coin
public fun propose_pay_minted<C: drop>(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin_amount: u64,
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        PayProposal {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_pay_minted<C>(proposal_mut, coin_amount, amount, interval, recipient);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_pay<C: drop>(
    mut executable: Executable, 
    multisig: &mut Multisig, 
    receiving: Option<Receiving<Coin<C>>>,
    ctx: &mut TxContext
) {
    let coin = access_coin(&mut executable, multisig, receiving, PayProposal {}, ctx);
    pay<C, PayProposal>(&mut executable, multisig, coin, PayProposal {}, ctx);

    destroy_pay<C, PayProposal>(&mut executable, PayProposal {});
    executable.destroy(PayProposal {});
}

// step 5: bearer of ClaimCap can claim the payment
public fun claim<C: drop>(stream: &mut Stream<C>, cap: &ClaimCap, ctx: &mut TxContext) {
    assert!(cap.stream_id == stream.id.to_inner(), EWrongStream);
    stream.disburse(ctx);
}

// step 5(bis): backend send the coin to the recipient until balance is empty
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

public fun new_pay_owned(
    proposal: &mut Proposal, 
    coin_id: ID, 
    amount: u64,
    interval: u64,
    recipient: address,
) {
    owned::new_withdraw(proposal, vector[coin_id]);
    proposal.add_action(PayAction { amount, interval, recipient });
}

public fun new_pay_treasury(
    proposal: &mut Proposal, 
    treasury_name: String, 
    coin_type: String, 
    coin_amount: u64, 
    amount: u64,
    interval: u64, 
    recipient: address
) {
    treasury::new_spend(proposal, treasury_name, vector[coin_type], vector[coin_amount]);
    proposal.add_action(PayAction { amount, interval, recipient });
}

public fun new_pay_minted<C: drop>(
    proposal: &mut Proposal, 
    coin_amount: u64,
    amount: u64, 
    interval: u64, 
    recipient: address
) {
    currency::new_mint<C>(proposal, coin_amount);
    proposal.add_action(PayAction { amount, interval, recipient });
}

public fun pay<C: drop, W: copy + drop>(
    executable: &mut Executable, 
    multisig: &mut Multisig, 
    coin: Coin<C>,
    witness: W,
    ctx: &mut TxContext
) {    
    let pay_mut: &mut PayAction = executable.action_mut(witness, multisig.addr());

    let stream = Stream<C> { 
        id: object::new(ctx), 
        balance: coin.into_balance(), 
        amount: pay_mut.amount,
        interval: pay_mut.interval,
        last_epoch: 0,
        recipient: pay_mut.recipient
    };

    event::emit(StreamCreated {
        stream_id: stream.id.to_inner(),
        amount: stream.amount,
        interval: stream.interval,
        recipient: stream.recipient
    });

    transfer::share_object(stream);
    pay_mut.amount = 0; // reset to ensure action is executed only once
}

public fun destroy_pay<C: drop, W: copy + drop>(executable: &mut Executable, witness: W): address {
    if (is_withdraw<C>(executable)) {
        if (owned::withdraw_is_executed(executable))
            owned::destroy_withdraw(executable, witness);
    } else if (is_spend<C>(executable)) {
        if (treasury::spend_is_executed(executable))
            treasury::destroy_spend(executable, witness);
    } else if (is_mint<C>(executable)) {
        if (currency::mint_is_executed<C>(executable))
            currency::destroy_mint<C, W>(executable, witness);
    } else {
        abort EInvalidExecutable
    };    

    let PayAction { amount, recipient, .. } = executable.remove_action(witness);
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

// === Private functions ===

// retrieves an object from the Multisig owned or managed assets 
fun access_coin<C: drop, W: copy + drop>(
    executable: &mut Executable, 
    multisig: &mut Multisig,
    receiving: Option<Receiving<Coin<C>>>,
    witness: W,
    ctx: &mut TxContext
): Coin<C> {
    if (is_withdraw<C>(executable)) {
        assert!(receiving.is_some(), EReceivingShouldBeSome);
        owned::withdraw(executable, multisig, receiving.destroy_some(), witness)
    } else if (is_spend<C>(executable)) {
        treasury::spend(executable, multisig, witness, ctx)
    } else if (is_mint<C>(executable)) {
        currency::mint(executable, multisig, witness, ctx)
    } else {
        abort EInvalidExecutable
    }
}

fun is_withdraw<C: drop>(executable: &Executable): bool {
    executable.action_index<WithdrawAction>() < executable.action_index<SpendAction>() &&
    executable.action_index<WithdrawAction>() < executable.action_index<MintAction<C>>()
}

fun is_spend<C: drop>(executable: &Executable): bool {
    executable.action_index<SpendAction>() < executable.action_index<WithdrawAction>() &&
    executable.action_index<SpendAction>() < executable.action_index<MintAction<C>>()
}

fun is_mint<C: drop>(executable: &Executable): bool {
    executable.action_index<MintAction<C>>() < executable.action_index<WithdrawAction>() &&
    executable.action_index<MintAction<C>>() < executable.action_index<SpendAction>()
}

