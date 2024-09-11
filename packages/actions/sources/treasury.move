/// Members can set multiple treasuries with different budgets and manager.
/// This allows for a more flexible and granular way to manage funds.

module kraken_actions::treasury;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use sui::{
    bag::{Self, Bag},
    balance::Balance,
    coin::{Self, Coin},
    vec_map::{Self, VecMap},
};
use kraken_multisig::{
    multisig::Multisig,
    proposals::Proposal,
    executable::Executable
};

// === Errors ===

const ETreasuryDoesntExist: u64 = 0;
const EOpenNotExecuted: u64 = 1;
const ETreasuryAlreadyExists: u64 = 2;
const EWrongLength: u64 = 3;
const EWithdrawNotExecuted: u64 = 4;
const ETreasuryNotEmpty: u64 = 5;

// === Structs ===

// delegated issuer protecting the proposal flow, role and treasury key
public struct Issuer has copy, drop {}

// [ACTION] propose to open a treasury for the multisig
public struct Open has store {
    // label for the treasury and role
    name: String,
}

// [ACTION] action to be used with specific proposals making good use of the returned coins, similar as owned::withdraw
public struct Spend has store {
    // name of the treasury to withdraw from
    name: String,
    // coin types to amounts
    coins_amounts_map: VecMap<String, u64>,
}

public struct TreasuryKey has copy, drop, store { name: String }

// multisig's dynamic field holding a budget with different coin types, key is name
public struct Treasury has store {
    // heterogeneous array of Balances, String -> Balance<C>
    bag: Bag
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

public fun treasury_exists(multisig: &Multisig, name: String): bool {
    multisig.has_managed_asset(TreasuryKey { name })
}

public fun treasury(multisig: &Multisig, name: String): &Treasury {
    multisig.borrow_managed_asset(Issuer {}, TreasuryKey { name })
}

public fun deposit<C: drop>(
    multisig: &mut Multisig,
    name: String, 
    coin: Coin<C>, 
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    assert!(treasury_exists(multisig, name), ETreasuryDoesntExist);

    let treasury: &mut Treasury = 
        multisig.borrow_managed_asset_mut(Issuer {}, TreasuryKey { name });
    let coin_type = coin_type_string<C>();

    if (treasury.coin_type_exists(coin_type)) {
        let balance: &mut Balance<C> = treasury.bag.borrow_mut(coin_type);
        balance.join(coin.into_balance());
    } else {
        treasury.bag.add(coin_type, coin.into_balance());
    };
}

public fun close(multisig: &mut Multisig, name: String, ctx: &mut TxContext) {
    multisig.assert_is_member(ctx);
    let Treasury { bag } = 
        multisig.remove_managed_asset(Issuer {}, TreasuryKey { name });
    assert!(bag.is_empty(), ETreasuryNotEmpty);
    bag.destroy_empty();
}

// === [PROPOSAL] Public Functions ===

// step 1: propose to open a treasury for the multisig
public fun propose_open(
    multisig: &mut Multisig,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    name: String,
    ctx: &mut TxContext
) {
    assert!(!treasury_exists(multisig, name), ETreasuryAlreadyExists);
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        name,
        key,
        description,
        execution_time,
        expiration_epoch,
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
    open(&mut executable, multisig, Issuer {}, ctx);
    destroy_open(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// === [ACTION] Public Functions ===

public fun new_open(proposal: &mut Proposal, name: String) {
    proposal.add_action(Open { name });
}

public fun open<I: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    issuer: I,
    ctx: &mut TxContext
) {
    let open_mut: &mut Open = executable.action_mut(issuer, multisig.addr());
    multisig.add_managed_asset(Issuer {}, TreasuryKey { name: open_mut.name }, Treasury { bag: bag::new(ctx) });
    open_mut.name = b"".to_string(); // reset to ensure execution
}

public fun destroy_open<I: copy + drop>(executable: &mut Executable, issuer: I) {
    let Open { name } = executable.remove_action(issuer);
    assert!(name.is_empty(), EOpenNotExecuted);
}

public fun new_spend(
    proposal: &mut Proposal,
    name: String,
    coin_types: vector<String>,
    amounts: vector<u64>
) {
    assert!(coin_types.length() == amounts.length(), EWrongLength);
    proposal.add_action(Spend { name, coins_amounts_map: vec_map::from_keys_values(coin_types, amounts) });
}

public fun spend<I: copy + drop, C: drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    issuer: I,
    ctx: &mut TxContext
): Coin<C> {
    let spend_mut: &mut Spend = executable.action_mut(issuer, multisig.addr());
    let (coin_type, amount) = spend_mut.coins_amounts_map.remove(&coin_type_string<C>());
    
    let treasury: &mut Treasury = multisig.borrow_managed_asset_mut(Issuer {}, TreasuryKey { name: spend_mut.name });
    let balance: &mut Balance<C> = treasury.bag.borrow_mut(coin_type);
    let coin = coin::take(balance, amount, ctx);

    if (balance.value() == 0) { // clean empty balances
        let balance: Balance<C> = treasury.bag.remove(coin_type);
        balance.destroy_zero();
    };

    coin
}

public fun destroy_spend<I: copy + drop>(executable: &mut Executable, issuer: I) {
    let Spend { coins_amounts_map, .. } = executable.remove_action(issuer);
    assert!(coins_amounts_map.is_empty(), EWithdrawNotExecuted);
}

public fun spend_is_executed(executable: &Executable): bool {
    let spend: &Spend = executable.action();
    spend.coins_amounts_map.is_empty()
}
