/// This module uses the owned apis to transfer assets owned by the multisig.
/// Objects can also be delivered to a single address, meaning that the recipient must claim the objects.
/// If the delivery is not confirmed, the Multisig can retrieve the objects.

module kraken_actions::transfers;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    coin::Coin,
};
use kraken_multisig::{
    multisig::Multisig,
    proposals::Proposal,
    executable::Executable
};
use kraken_actions::{
    currency::{Self, Mint},
    owned::{Self, Withdraw},
    treasury::{Self, Spend},
};

// === Errors ===

const EInvalidExecutable: u64 = 0;
const EDifferentLength: u64 = 1;
const EReceivingShouldBeSome: u64 = 2;
const ETransferNotExecuted: u64 = 3;

// === Structs ===

// delegated issuer verifying a proposal is destroyed in the module where it was created
public struct Issuer has copy, drop {}

// [ACTION] used in combination with Mint, Withdraw or Spend 
// to transfer the coins or objects to a recipient
public struct Transfer has store {
    // address to transfer to
    recipient: address,
}

// === [PROPOSAL] Public functions ===

// step 1: propose to send owned objects
public fun propose_transfer_object(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    objects: vector<vector<ID>>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(recipients.length() == objects.length(), EDifferentLength);
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    objects.zip_do!(recipients, |objs, recipient| {
        new_transfer_object(proposal_mut, objs, recipient);
    });
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer_object<T: key + store>(
    executable: &mut Executable, 
    multisig: &mut Multisig, 
    receiving: Receiving<T>,
) {
    transfer_object(executable, multisig, receiving, Issuer {});
}

// step 5: destroy transfer for recipient
public fun confirm_transfer_object(executable: &mut Executable) {
    destroy_transfer_object(executable, Issuer {});
}

// step 6: complete transfers and destroy the executable
public fun complete_transfer(executable: Executable) {
    executable.destroy(Issuer {});
}

// step 1: propose to send owned coins
public fun propose_transfer_coin_owned(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin_objects: vector<vector<ID>>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(recipients.length() == coin_objects.length(), EDifferentLength);
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    coin_objects.zip_do!(recipients, |coins, recipient| {
        new_transfer_coin_owned(proposal_mut, coins, recipient);
    });
}

// step 1(bis): propose to send managed coins
public fun propose_transfer_coin_treasury(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    treasury_name: String,
    coin_types: vector<vector<String>>,
    coin_amounts: vector<vector<u64>>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(coin_amounts.length() == coin_types.length(), EDifferentLength);
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    coin_types.zip_do!(coin_amounts, |types, amounts| {
        let recipient = recipients[0];
        new_transfer_coin_treasury(proposal_mut, treasury_name, types, amounts, recipient);
    });
}

// step 1(bis): propose to send managed coins
public fun propose_transfer_coin_minted<C: drop>(
    multisig: &mut Multisig, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    amounts: vector<u64>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(amounts.length() == recipients.length(), EDifferentLength);
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    amounts.zip_do!(recipients, |amount, recipient| {
        new_transfer_coin_minted<C>(proposal_mut, amount, recipient);
    });
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer_coin<C: drop>(
    executable: &mut Executable, 
    multisig: &mut Multisig, 
    receiving: Option<Receiving<Coin<C>>>,
    ctx: &mut TxContext
) {
    let coin = access_coin<C, Issuer>(executable, multisig, receiving, Issuer {}, ctx);
    transfer_coin(executable, multisig, coin, Issuer {});
}

// step 5: destroy transfer for recipient
public fun confirm_transfer_coin<C: drop>(executable: &mut Executable) {
    destroy_transfer_coin<C, Issuer>(executable, Issuer {});
}
// step 6: complete transfers and destroy the executable `complete_transfer`

// === [ACTION] Public functions ===

// retrieve an object from the Multisig owned or managed assets 
public fun access_coin<C: drop, I: copy + drop>(
    executable: &mut Executable, 
    multisig: &mut Multisig,
    receiving: Option<Receiving<Coin<C>>>,
    issuer: I,
    ctx: &mut TxContext
): Coin<C> {
    if (is_withdraw<C>(executable)) {
        assert!(receiving.is_some(), EReceivingShouldBeSome);
        owned::withdraw(executable, multisig, receiving.destroy_some(), issuer)
    } else if (is_spend<C>(executable)) {
        treasury::spend(executable, multisig, issuer, ctx)
    } else if (is_mint<C>(executable)) {
        currency::mint(executable, multisig, issuer, ctx)
    } else {
        abort EInvalidExecutable
    }
}

public fun new_transfer_object(
    proposal: &mut Proposal, 
    objects: vector<ID>, 
    recipient: address
) {
    owned::new_withdraw(proposal, objects);
    proposal.add_action(Transfer { recipient });
}

public fun transfer_object<T: key + store, I: copy + drop>(
    executable: &mut Executable, 
    multisig: &mut Multisig, 
    receiving: Receiving<T>,
    issuer: I,
) {
    let object = owned::withdraw(executable, multisig, receiving, issuer);
    let is_executed = owned::withdraw_is_executed(executable);
    
    let transfer_mut: &mut Transfer = executable.action_mut(issuer, multisig.addr());
    transfer::public_transfer(object, transfer_mut.recipient);

    if (is_executed)
        transfer_mut.recipient = @0xF; // reset to ensure it is executed once
}

public fun destroy_transfer_object<I: copy + drop>(
    executable: &mut Executable, 
    issuer: I
) {
    owned::destroy_withdraw(executable, issuer);
    let Transfer { recipient } = executable.remove_action(issuer);
    assert!(recipient == @0xF, ETransferNotExecuted);
}

public fun new_transfer_coin_owned(
    proposal: &mut Proposal, 
    objects: vector<ID>, 
    recipient: address
) {
    owned::new_withdraw(proposal, objects);
    proposal.add_action(Transfer { recipient });
}

public fun new_transfer_coin_treasury(
    proposal: &mut Proposal, 
    treasury_name: String, 
    coin_types: vector<String>, 
    amounts: vector<u64>, 
    recipient: address
) {
    treasury::new_spend(proposal, treasury_name, coin_types, amounts);
    proposal.add_action(Transfer { recipient });
}

public fun new_transfer_coin_minted<C: drop>(
    proposal: &mut Proposal, 
    amount: u64, 
    recipient: address
) {
    currency::new_mint<C>(proposal, amount);
    proposal.add_action(Transfer { recipient });
}

public fun transfer_coin<C: drop, I: copy + drop>(
    executable: &mut Executable, 
    multisig: &Multisig,
    coin: Coin<C>,
    issuer: I,
) {
    let is_executed = (
        owned::withdraw_is_executed(executable) || 
        treasury::spend_is_executed(executable) || 
        currency::mint_is_executed<C>(executable)
    );
    let transfer_mut: &mut Transfer = executable.action_mut(issuer, multisig.addr());
    transfer::public_transfer(coin, transfer_mut.recipient);  
    
    if (is_executed)
        transfer_mut.recipient = @0xF; // reset to ensure it is executed once
}

public fun destroy_transfer_coin<C: drop, I: copy + drop>(
    executable: &mut Executable, 
    issuer: I
) {
    if (is_withdraw<C>(executable)) {
        if (owned::withdraw_is_executed(executable))
            owned::destroy_withdraw(executable, issuer);
    } else if (is_spend<C>(executable)) {
        if (treasury::spend_is_executed(executable))
            treasury::destroy_spend(executable, issuer);
    } else if (is_mint<C>(executable)) {
        if (currency::mint_is_executed<C>(executable))
            currency::destroy_mint<C, I>(executable, issuer);
    } else {
        abort EInvalidExecutable
    };  

    let Transfer { recipient } = executable.remove_action(issuer);
    assert!(recipient == @0xF, ETransferNotExecuted);
}

// === Private functions ===

fun is_withdraw<C: drop>(executable: &Executable): bool {
    executable.action_index<Withdraw>() < executable.action_index<Spend>() &&
    executable.action_index<Withdraw>() < executable.action_index<Mint<C>>()
}

fun is_spend<C: drop>(executable: &Executable): bool {
    executable.action_index<Spend>() < executable.action_index<Withdraw>() &&
    executable.action_index<Spend>() < executable.action_index<Mint<C>>()
}

fun is_mint<C: drop>(executable: &Executable): bool {
    executable.action_index<Mint<C>>() < executable.action_index<Withdraw>() &&
    executable.action_index<Mint<C>>() < executable.action_index<Spend>()
}

