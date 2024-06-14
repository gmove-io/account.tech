/// This module uses the owned apis to stream a coin for a payment.
/// A payment has an amount to be paid at each interval, until the balance is empty.
/// It can be cancelled by multisig members.

module kraken::payments {
    use std::string::String;

    use sui::transfer::Receiving;
    use sui::balance::Balance;
    use sui::coin::{Self, Coin};
    
    use kraken::owned;
    use kraken::multisig::{Multisig, Executable, Proposal};

    // === Errors ===

    const ECompletePaymentBefore: u64 = 0;
    const EPayTooEarly: u64 = 1;
    const EPayNotExecuted: u64 = 2;

    // === Structs ===

    public struct Witness has copy, drop {}

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
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        coin: ID, // must have the total amount to be paid
        amount: u64, // amount to be paid at each interval
        interval: u64, // number of epochs between each payment
        recipient: address,
        ctx: &mut TxContext
    ) {
        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
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
        received: Receiving<Coin<C>>,
        ctx: &mut TxContext
    ) {
        pay(&mut executable, multisig, received, Witness {}, 0, ctx);

        owned::destroy_withdraw(&mut executable, Witness {});
        destroy_pay(&mut executable, Witness {});
        executable.destroy(Witness {});
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
        let Stream { 
            id, 
            balance, 
            amount: _, 
            interval: _, 
            last_epoch: _, 
            recipient: _ 
        } = stream;
        
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
        let Stream { 
            id, 
            balance, 
            amount: _, 
            interval: _, 
            last_epoch: _, 
            recipient: _ 
        } = stream;
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

    public fun pay<W: copy + drop, C: drop>(
        executable: &mut Executable, 
        multisig: &mut Multisig, 
        received: Receiving<Coin<C>>,
        witness: W,
        idx: u64, // index in actions bag
        ctx: &mut TxContext
    ) {
        multisig.assert_executed(executable);
        
        let coin = owned::withdraw(executable, multisig, witness, received, idx);
        let pay_mut: &mut Pay = executable.action_mut(witness, idx + 1);

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

    public fun destroy_pay<W: copy + drop>(executable: &mut Executable, witness: W): address {
        owned::destroy_withdraw(executable, witness);
        let Pay { amount, interval: _, recipient } = executable.remove_action(witness);
        assert!(amount == 0, EPayNotExecuted);

        recipient
    }
}

