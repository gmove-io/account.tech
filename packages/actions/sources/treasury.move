/// Members can create multiple treasuries with different budgets and managers (members with roles).
/// This allows for a more flexible and granular way to manage funds.
/// 
/// Coins managed by treasuries can also be transferred or paid to any address.

module account_actions::treasury;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};
use sui::{
    bag::{Self, Bag},
    balance::Balance,
    coin::{Self, Coin},
    transfer::Receiving,
};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth,
};
use account_actions::{
    transfer as acc_transfer,
    vesting,
    version,
};

// === Errors ===

#[error]
const ETreasuryDoesntExist: vector<u8> = b"No Treasury with this name";
#[error]
const ETreasuryAlreadyExists: vector<u8> = b"A treasury already exists with this name";
#[error]
const ETypesAmountsNotSameLength: vector<u8> = b"Types and amounts vectors not same length";
#[error]
const ETreasuryNotEmpty: vector<u8> = b"Treasury must be emptied before closing";

// === Structs ===

/// Dynamic Field key for the Treasury
public struct TreasuryKey has copy, drop, store { name: String }
/// Dynamic field holding a budget with different coin types, key is name
public struct Treasury has store {
    // heterogeneous array of Balances, String -> Balance<C>
    bag: Bag
}

/// [MEMBER] can deposit coins into a treasury
public struct Deposit() has drop;
/// [PROPOSAL] acc_transfer from a treasury 
public struct TransferProposal() has copy, drop;
/// [PROPOSAL] pays from a treasury
public struct PayProposal() has copy, drop;

/// [ACTION] action to be used with specific proposals making good use of the returned coins, similar to owned::withdraw
public struct SpendAction has store {
    // coin types to withdraw
    coin_type: String,
    // amount to withdraw
    amount: u64,
}

// === View Functions ===

public fun treasury_exists<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): bool {
    account.has_managed_asset(TreasuryKey { name })
}

public fun borrow_treasury<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): &Treasury {
    account.borrow_managed_asset(TreasuryKey { name }, version::current())
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

// === [MEMBER] Public Functions ===

// Members can open a treasury
public fun open<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
    ctx: &mut TxContext
) {
    auth.verify(account.addr());
    assert!(!treasury_exists(account, name), ETreasuryAlreadyExists);

    account.add_managed_asset(TreasuryKey { name }, Treasury { bag: bag::new(ctx) }, version::current());
}

/// Deposits coins owned by the account into a treasury
public fun deposit_owned<Config, Outcome, C: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String, 
    receiving: Receiving<Coin<C>>, 
) {
    let coin = account.receive(receiving, version::current());
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
        account.borrow_managed_asset_mut(TreasuryKey { name }, version::current());
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
        account.remove_managed_asset(TreasuryKey { name }, version::current());
    assert!(bag.is_empty(), ETreasuryNotEmpty);
    bag.destroy_empty();
}

// === [PROPOSAL] Public Functions ===

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
    coin_types: vector<String>,
    amounts: vector<u64>,
    mut recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(coin_types.length() == amounts.length(), ETypesAmountsNotSameLength);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        TransferProposal(),
        treasury_name,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    coin_types.zip_do!(amounts, |coin_type, amount| {
        new_spend(&mut proposal, coin_type, amount, TransferProposal());
        acc_transfer::new_transfer(&mut proposal, recipients.remove(0), TransferProposal());
    });

    account.add_proposal(proposal, version::current(), TransferProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer<Config, Outcome, C: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<C> = do_spend(executable, account, version::current(), TransferProposal(), ctx);
    acc_transfer::do_transfer(executable, account, coin, version::current(), TransferProposal());
}

// step 5: complete acc_transfer and destroy the executable
public fun complete_transfer(executable: Executable) {
    executable.destroy(version::current(), TransferProposal());
}

// step 1(bis): same but from a treasury
public fun propose_vesting<Config, Outcome>(
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
    start_timestamp: u64, 
    end_timestamp: u64, 
    recipient: address,
    ctx: &mut TxContext
) {
    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        PayProposal(),
        treasury_name,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    new_spend(&mut proposal, coin_type, coin_amount, PayProposal());
    vesting::new_vesting(&mut proposal, start_timestamp, end_timestamp, recipient, PayProposal());
    account.add_proposal(proposal, version::current(), PayProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_vesting<Config, Outcome, C: drop>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<C> = do_spend(&mut executable, account, version::current(), PayProposal(), ctx);
    vesting::do_vesting(&mut executable, account, coin, version::current(), PayProposal(), ctx);
    executable.destroy(version::current(), PayProposal());
}

// === [ACTION] Public Functions ===

public fun new_spend<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>,
    coin_type: String,
    amount: u64,
    witness: W,
) {
    proposal.add_action(SpendAction { coin_type, amount }, witness);
}

public fun do_spend<Config, Outcome, C: drop, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W,
    ctx: &mut TxContext
): Coin<C> {
    let name = executable.issuer().role_name();
    let SpendAction { coin_type, amount } = executable.action(account.addr(), version, witness);
    
    let treasury: &mut Treasury = account.borrow_managed_asset_mut(TreasuryKey { name }, version);
    let balance: &mut Balance<C> = treasury.bag.borrow_mut(coin_type);
    let coin = coin::take(balance, amount, ctx);

    if (balance.value() == 0) treasury.bag.remove<String, Balance<C>>(coin_type).destroy_zero();
    
    coin
}

public fun delete_spend_action<Outcome>(expired: &mut Expired<Outcome>) {
    let SpendAction { .. } = expired.remove_expired_action();
}
