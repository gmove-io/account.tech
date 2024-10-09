/// Members can create multiple treasuries with different budgets and managers (members with roles).
/// This allows for a more flexible and granular way to manage funds.
/// 
/// Coins managed by treasuries can also be transferred or paid to any address.

module account_actions::treasury;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use sui::{
    bag::{Self, Bag},
    balance::Balance,
    coin::{Self, Coin},
    transfer::Receiving,
    vec_map::{Self, VecMap},
};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth,
};
use account_actions::{
    transfers,
    payments,
};

// === Errors ===

const ETreasuryDoesntExist: u64 = 0;
const EOpenNotExecuted: u64 = 1;
const ETreasuryAlreadyExists: u64 = 2;
const EWrongLength: u64 = 3;
const EWithdrawNotExecuted: u64 = 4;
const EDifferentLength: u64 = 5;
const ETreasuryNotEmpty: u64 = 6;

// === Structs ===

/// Dynamic Field key for the Treasury
public struct TreasuryKey has copy, drop, store { name: String }

/// Dynamic field holding a budget with different coin types, key is name
public struct Treasury has store {
    // heterogeneous array of Balances, String -> Balance<C>
    bag: Bag
}

/// [MEMBER] can close a treasury and deposit coins into it
public struct Do() has drop;
/// [MEMBER] can deposit coins into a treasury
public struct Deposit() has drop;
/// [PROPOSAL] opens a treasury for the account
public struct OpenProposal() has drop;
/// [PROPOSAL] transfers from a treasury 
public struct TransferProposal() has drop;
/// [PROPOSAL] pays from a treasury
public struct PayProposal() has drop;

/// [ACTION] proposes to open a treasury for the account
public struct OpenAction has store {
    // label for the treasury and role
    name: String,
}

/// [ACTION] action to be used with specific proposals making good use of the returned coins, similar as owned::withdraw
public struct SpendAction has store {
    // name of the treasury to withdraw from
    name: String,
    // coin types to amounts
    coins_amounts_map: VecMap<String, u64>,
}

// === View Functions ===

public fun coin_type_string<C: drop>(): String {
    type_name::get<C>().into_string().to_string()
}

public fun coin_type_exists(treasury: &Treasury, coin_type: String): bool {
    treasury.bag.contains(coin_type)
}

public fun coin_type_value<C: drop>(treasury: &Treasury, coin_type: String): u64 {
    treasury.bag.borrow<String, Balance<C>>(coin_type).value()
}

// === [MEMBER] Public Functions ===

public fun treasury_exists<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): bool {
    account.has_managed_asset(TreasuryKey { name })
}

/// Deposits coins owned by the account into a treasury
public fun deposit_owned<Config, Outcome, C: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String, 
    receiving: Receiving<Coin<C>>, 
) {
    let coin = account.receive(Deposit(), receiving);
    deposit<Config, Outcome, C>(auth, account, name, coin);
}

/// Deposits coins owned by a member into a treasury
public fun deposit<Config, Outcome, C: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String, 
    coin: Coin<C>, 
) {
    auth.verify_with_role<Deposit>(account.addr(), name);
    assert!(treasury_exists(account, name), ETreasuryDoesntExist);

    let treasury: &mut Treasury = 
        account.borrow_managed_asset_mut(Deposit(), TreasuryKey { name });
    let coin_type = coin_type_string<C>();

    if (treasury.coin_type_exists(coin_type)) {
        let balance: &mut Balance<C> = treasury.bag.borrow_mut(coin_type);
        balance.join(coin.into_balance());
    } else {
        treasury.bag.add(coin_type, coin.into_balance());
    };
}

/// Closes the treasury if empty
public fun close<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
) {
    auth.verify(account.addr());

    let Treasury { bag } = 
        account.remove_managed_asset(Do(), TreasuryKey { name });
    assert!(bag.is_empty(), ETreasuryNotEmpty);
    bag.destroy_empty();
}

// === [PROPOSAL] Public Functions ===

// step 1: propose to open a treasury for the account
public fun propose_open<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    name: String,
    ctx: &mut TxContext
) {
    assert!(!treasury_exists(account, name), ETreasuryAlreadyExists);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        OpenProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    new_open(&mut proposal, name, OpenProposal());
    account.add_proposal(proposal, OpenProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: create the Treasury
public fun execute_open<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    ctx: &mut TxContext
) {
    open(&mut executable, account, OpenProposal(), ctx);
    destroy_open(&mut executable, OpenProposal());
    executable.destroy(OpenProposal());
}

// step 1: propose to send managed coins
public fun propose_transfer<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    treasury_name: String,
    coin_types: vector<vector<String>>,
    coin_amounts: vector<vector<u64>>,
    mut recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(coin_amounts.length() == coin_types.length(), EDifferentLength);
    let mut proposal = account.create_proposal(
        auth,
        outcome,
        TransferProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    coin_types.zip_do!(coin_amounts, |types, amounts| {
        new_spend(&mut proposal, treasury_name, types, amounts, TransferProposal());
        transfers::new_transfer(&mut proposal, recipients.remove(0), TransferProposal());
    });

    account.add_proposal(proposal, TransferProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer<Config, Outcome, C: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<C> = spend(executable, account, TransferProposal(), ctx);

    let mut is_executed = false;
    let spend: &SpendAction = executable.action();

    if (spend.coins_amounts_map.is_empty()) {
        let SpendAction { coins_amounts_map, .. } = executable.remove_action(TransferProposal());
        coins_amounts_map.destroy_empty();
        is_executed = true;
    };

    transfers::transfer(executable, account, coin, TransferProposal(), is_executed);

    if (is_executed) {
        transfers::destroy_transfer(executable, TransferProposal());
    }
}

// step 1(bis): same but from a treasury
public fun propose_pay<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
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
    let mut proposal = account.create_proposal(
        auth,
        outcome,
        PayProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    new_spend(&mut proposal, treasury_name, vector[coin_type], vector[coin_amount], PayProposal());
    payments::new_pay(&mut proposal, amount, interval, recipient, PayProposal());
    account.add_proposal(proposal, PayProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_pay<Config, Outcome, C: drop>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<C> = spend(&mut executable, account, PayProposal(), ctx);
    payments::pay(&mut executable, account, coin, PayProposal(), ctx);

    destroy_spend(&mut executable, PayProposal());
    payments::destroy_pay(&mut executable, PayProposal());
    executable.destroy(PayProposal());
}

// === [ACTION] Public Functions ===

public fun new_open<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    name: String, 
    witness: W
) {
    proposal.add_action(OpenAction { name }, witness);
}

public fun open<Config, Outcome, W: drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    witness: W,
    ctx: &mut TxContext
) {
    let open_mut: &mut OpenAction = executable.action_mut(account.addr(), witness);
    account.add_managed_asset(Do(), TreasuryKey { name: open_mut.name }, Treasury { bag: bag::new(ctx) });
    open_mut.name = b"".to_string(); // reset to ensure execution
}

public fun destroy_open<W: drop>(executable: &mut Executable, witness: W) {
    let OpenAction { name } = executable.remove_action(witness);
    assert!(name.is_empty(), EOpenNotExecuted);
}

public fun new_spend<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>,
    name: String,
    coin_types: vector<String>,
    amounts: vector<u64>,
    witness: W,
) {
    assert!(coin_types.length() == amounts.length(), EWrongLength);
    proposal.add_action(
        SpendAction { name, coins_amounts_map: vec_map::from_keys_values(coin_types, amounts) },
        witness
    );
}

public fun spend<Config, Outcome, W: drop, C: drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    witness: W,
    ctx: &mut TxContext
): Coin<C> {
    let spend_mut: &mut SpendAction = executable.action_mut(account.addr(), witness);
    let (coin_type, amount) = spend_mut.coins_amounts_map.remove(&coin_type_string<C>());
    
    let treasury: &mut Treasury = account.borrow_managed_asset_mut(Do(), TreasuryKey { name: spend_mut.name });
    let balance: &mut Balance<C> = treasury.bag.borrow_mut(coin_type);
    let coin = coin::take(balance, amount, ctx);

    if (balance.value() == 0) { // clean empty balances
        let balance: Balance<C> = treasury.bag.remove(coin_type);
        balance.destroy_zero();
    };

    coin
}

public fun destroy_spend<W: drop>(executable: &mut Executable, witness: W) {
    let SpendAction { coins_amounts_map, .. } = executable.remove_action(witness);
    assert!(coins_amounts_map.is_empty(), EWithdrawNotExecuted);
}

public fun delete_spend_action<Outcome>(expired: Expired<Outcome>) {
    let SpendAction { .. } = expired.remove_expired_action();
}
