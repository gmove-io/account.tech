/// Members can set multiple treasuries with different budgets and manager.
/// This allows for a more flexible and granular way to manage funds.

module kraken::treasury;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use sui::{
    bag::{Self, Bag},
    balance::Balance,
    coin::{Self, Coin},
    dynamic_field as df,
    vec_map::{Self, VecMap},
};
use kraken::multisig::{Multisig, Proposal, Executable};

// === Errors ===

const ETreasuryDoesntExist: u64 = 0;
const EOpenNotExecuted: u64 = 1;
const ETreasuryAlreadyExists: u64 = 2;
const EWrongLength: u64 = 3;
const ECoinTypeDoesntExist: u64 = 4;
const EWithdrawNotExecuted: u64 = 5;

// === Structs ===

// delegated witness protecting the proposal flow, role and treasury key
public struct Auth has copy, drop {
    // key name 
    name: String
}

// [ACTION] propose to open a treasury for the multisig
public struct Open has store {
    // label for the treasury and role
    name: String,
}

// [ACTION] action to be used with specific proposals making good use of the returned coins, similar as owned::withdraw
public struct Withdraw has store {
    // name of the treasury to withdraw from
    name: String,
    // coin types to amounts
    coin_amounts: VecMap<String, u64>,
}

// [ACTION] used in combination with Withdraw to transfer the coins to a recipient
public struct Transfer has store {
    // recipient
    recipient: address,
}

// multisig's dynamic field holding a budget with different coin types, key is name
public struct Treasury has store {
    // heterogeneous array of Balances, String -> Balance<C>
    bag: Bag
}

// === [MEMBER] Public Functions ===

public fun deposit<C: drop>(
    multisig: &mut Multisig,
    name: String, 
    coin: Coin<C>, 
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    assert!(treasury_exists(multisig, name), ETreasuryDoesntExist);

    let treasury: &mut Treasury = df::borrow_mut(multisig.uid_mut(), name);
    let coin_type = coin_type_string<C>();

    if (treasury.coin_type_exists(coin_type)) {
        let balance: &mut Balance<C> = treasury.bag.borrow_mut(coin_type);
        balance.join(coin.into_balance());
    } else {
        treasury.bag.add(coin_type, coin);
    };
}

// === [PROPOSAL] Public Functions ===

// step 1: propose to open a treasury for the multisig
public fun propose_open(
    multisig: &mut Multisig,
    key: String,
    execution_time: u64,
    expiration_epoch: u64,
    description: String,
    name: String,
    ctx: &mut TxContext
) {
    assert!(!treasury_exists(multisig, name), ETreasuryAlreadyExists);
    let proposal_mut = multisig.create_proposal(
        Auth { name },
        key,
        execution_time,
        expiration_epoch,
        description,
        ctx
    );
    new_open(proposal_mut, name);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: create the Treasury
public fun execute_open(
    mut executable: Executable,
    multisig: &mut Multisig,
    ctx: &mut TxContext
) {
    let name = executable.action<Open>(0).name;
    open(&mut executable, multisig, Auth { name }, 0, ctx);
    executable.destroy(Auth { name });
}

// step 1: propose to execute a transfer with multiple coins for different recipients
public fun propose_batch_transfer(
    multisig: &mut Multisig,
    key: String,
    execution_time: u64,
    expiration_epoch: u64,
    description: String,
    name: String,
    coin_types: vector<String>,
    amounts: vector<u64>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(treasury_exists(multisig, name), ETreasuryDoesntExist);
    let treasury = treasury(multisig, name);
    coin_types.do_ref!(|coin_type| {
        assert!(coin_type_exists(treasury, *coin_type), ECoinTypeDoesntExist);
    });

    let proposal_mut = multisig.create_proposal(
        Auth { name },
        key,
        execution_time,
        expiration_epoch,
        description,
        ctx
    );

    // push Withdraw/Transfer as many times as there are recipients
    recipients.do!(|recipient| {
        new_transfer(proposal_mut, name, coin_types, amounts, recipient);
    });
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: loop over this function passing the coin type as a generic parameter
public fun execute_transfer<C: drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    ctx: &mut TxContext
) {
    let name = executable.action<Withdraw>(0).name;
    transfer<Auth ,C>(executable, multisig, Auth { name }, 0, ctx); // TODO: handle idx
}

// step 5: each time a Withdraw is consumed, we destroy it with the Transfer
public fun confirm_transfer<C: drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    ctx: &mut TxContext
) {
    let name = executable.action<Withdraw>(0).name;
    destroy_withdraw(executable, Auth { name });
    destroy_transfer(executable, Auth { name });
}

public fun confirm_batch_transfer<C: drop>(
    executable: Executable,
    ctx: &mut TxContext
) {
    let name = executable.action<Withdraw>(0).name;
    executable.destroy(Auth { name });
}

// === [ACTION] Public Functions ===

public fun new_open(proposal: &mut Proposal, name: String) {
    proposal.add_action(Open { name });
}

public fun open<W: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    witness: W,
    idx: u64,
    ctx: &mut TxContext
) {
    let open_mut: &mut Open = executable.action_mut(witness, idx);
    df::add(multisig.uid_mut(), open_mut.name, Treasury { bag: bag::new(ctx) });
    open_mut.name = b"".to_string(); // reset to ensure execution
}

public fun destroy_open<W: copy + drop>(executable: &mut Executable, witness: W) {
    let Open { name } = executable.remove_action(witness);
    assert!(name.is_empty(), EOpenNotExecuted);
}

public fun new_withdraw(
    proposal: &mut Proposal,
    name: String,
    coin_types: vector<String>,
    amounts: vector<u64>
) {
    assert!(coin_types.length() == amounts.length(), EWrongLength);
    proposal.add_action(Withdraw { name, coin_amounts: vec_map::from_keys_values(coin_types, amounts) });
}

public fun withdraw<W: copy + drop, C: drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    witness: W,
    idx: u64,
    ctx: &mut TxContext
): Coin<C> {
    let withdraw_mut: &mut Withdraw = executable.action_mut(witness, idx);
    let (coin_type, amount) = withdraw_mut.coin_amounts.remove(&coin_type_string<C>());
    
    let treasury: &mut Treasury = df::borrow_mut(multisig.uid_mut(), withdraw_mut.name);
    let balance: &mut Balance<C> = treasury.bag.borrow_mut(coin_type);
    
    coin::take(balance, amount, ctx)
}

public fun destroy_withdraw<W: copy + drop>(executable: &mut Executable, witness: W) {
    let Withdraw { name: _, coin_amounts } = executable.remove_action(witness);
    assert!(coin_amounts.is_empty(), EWithdrawNotExecuted);
}

public fun new_transfer(
    proposal: &mut Proposal,
    name: String,
    coin_types: vector<String>,
    amounts: vector<u64>,
    recipient: address
) {
    new_withdraw(proposal, name, coin_types, amounts);
    proposal.add_action(Transfer { recipient });
}

public fun transfer<W: copy + drop, C: drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    witness: W,
    idx: u64,
    ctx: &mut TxContext
) {
    let coin: Coin<C> = withdraw(executable, multisig, witness, idx, ctx);
    let transfer_mut: &mut Transfer = executable.action_mut(witness, idx + 1);
    transfer::public_transfer(coin, transfer_mut.recipient);
}

public fun destroy_transfer<W: copy + drop>(executable: &mut Executable, witness: W) {
    destroy_withdraw(executable, witness); // only possible if all withdrawals/transfers are done
    let Transfer { .. } = executable.remove_action(witness);
}

// === View Functions ===

public fun treasury_exists(multisig: &Multisig, name: String): bool {
    df::exists_(multisig.uid(), name)
}

public fun treasury(multisig: &Multisig, name: String): &Treasury {
    df::borrow(multisig.uid(), name)
}

public fun coin_type_string<C: drop>(): String {
    type_name::get<C>().into_string().to_string()
}

public fun coin_type_exists(treasury: &Treasury, coin_type: String): bool {
    treasury.bag.contains(coin_type)
}

public fun coin_type_value<C: drop>(treasury: &Treasury, coin_type: String): u64 {
    treasury.bag.borrow<String, Balance<C>>(coin_type).value()
}