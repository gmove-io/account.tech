/// This module uses the owned apis to stream a coin for a payment.
/// A payment has an amount to be paid at each interval, until the balance is empty.
/// It can be cancelled by the multisig member.

module kraken::payments {
    use std::string::String;

    use sui::transfer::Receiving;
    use sui::balance::Balance;
    use sui::coin::{Self, Coin};
    
    use kraken::owned;
    use kraken::multisig::{Multisig, Executable};

    // === Errors ===

    const ECompletePaymentBefore: u64 = 0;
    const EPayTooEarly: u64 = 1;

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

    // === [PROPOSALS] Public Functions ===

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

        proposal_mut.push_action(new_pay(amount, interval, recipient));
        proposal_mut.push_action(owned::new_withdraw(vector[coin]));
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
        let idx = executable.executable_last_action_idx();
        pay(&mut executable, multisig, received, Witness {}, idx, ctx);

        owned::destroy_withdraw(&mut executable, Witness {});
        destroy_pay(&mut executable, Witness {});
        executable.destroy_executable(Witness {});
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

    // === [ACTIONS] Public Functions ===

    public fun new_pay(amount: u64, interval: u64, recipient: address): Pay {
        Pay { amount, interval, recipient }
    }

    public fun pay<W: copy + drop, C: drop>(
        executable: &mut Executable, 
        multisig: &mut Multisig, 
        received: Receiving<Coin<C>>,
        witness: W,
        idx: u64, // index in actions bag
        ctx: &mut TxContext
    ) {
        let coin = owned::withdraw(executable, multisig, witness, received, idx + 1);
        let pay_mut: &mut Pay = executable.action_mut(witness, idx);

        let stream = Stream<C> { 
            id: object::new(ctx), 
            balance: coin.into_balance(), 
            amount: pay_mut.amount,
            interval: pay_mut.interval,
            last_epoch: 0,
            recipient: pay_mut.recipient
        };
        transfer::share_object(stream);
    }

    public fun destroy_pay<W: drop>(executable: &mut Executable, witness: W): (u64, u64, address) {
        let Pay { amount, interval, recipient } = executable.pop_action(witness);
        (amount, interval, recipient)
    }
}

