/// This is the core module managing the account Account.
/// It provides the apis to create, approve and execute proposals with actions.
/// 
/// The flow is as follows:
///   1. A proposal is created by pushing actions into it. 
///      Actions are stacked from first to last, they must be executed then destroyed in the same order.
///   2. When the threshold is reached, a proposal can be executed. 
///      This returns an Executable hot potato constructed from certain fields of the approved Proposal. 
///      It is directly passed into action functions to enforce account approval for an action to be executed.
///   3. The module that created the proposal must destroy all of the actions and the Executable after execution 
///      by passing the same witness that was used for instanciation. 
///      This prevents the actions or the proposal to be stored instead of executed.

module account_protocol::account;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    clock::Clock, 
    dynamic_field as df,
    bag::Bag,
};
use account_protocol::{
    auth,
    deps::{Self, Deps},
    thresholds::{Self, Thresholds},
    members::{Self, Members, Member},
    proposals::{Self, Proposals, Proposal},
    executable::{Self, Executable},
};
use account_extensions::extensions::Extensions;

// === Errors ===

const ECantBeExecutedYet: u64 = 0;
const ECallerIsNotMember: u64 = 1;

// === Constants ===

const VERSION: u64 = 1;

// === Structs ===

/// Shared multisig Account object 
public struct Account has key {
    id: UID,
    // human readable name to differentiate the multisig accounts
    name: String,
    // ids and versions of the packages this account is using
    // idx 0: account_protocol, idx 1: account_actions
    deps: Deps,
    // members of the account
    members: Members,
    // manage global threshold and role -> threshold
    thresholds: Thresholds,
    // open proposals, key should be a unique descriptive name
    proposals: Proposals,
}

// === Public mutative functions ===

/// Init and returns a new Account object
/// Creator is added by default with weight and global threshold of 1
public fun new(
    extensions: &Extensions,
    name: String, 
    account_id: ID, 
    ctx: &mut TxContext
): Account {
    let mut members = members::new();
    members.add(ctx.sender(), 1, option::some(account_id), vector[]);
    
    Account { 
        id: object::new(ctx),
        name,
        deps: deps::new(extensions),
        thresholds: thresholds::new(1),
        members,
        proposals: proposals::new(),
    }
}

/// Must be initialized by the creator before being shared
#[allow(lint(share_owned))]
public fun share(account: Account) {
    transfer::share_object(account);
}

// === Account-only functions ===

/// Creates a new proposal that must be constructed in another module
public fun create_proposal<W: copy + drop>(
    account: &mut Account, 
    witness: W, // module's auth witness
    auth_name: String, // module's auth name
    key: String, // proposal key
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64, // epoch when we can delete the proposal
    ctx: &mut TxContext
): Proposal {
    account.assert_is_member(ctx);
    let auth = auth::construct(witness, auth_name, account.addr());
    account.deps.assert_version(&auth, VERSION);

    proposals::new_proposal(
        auth,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    )
}

public fun add_proposal<W: copy + drop>(
    account: &mut Account, 
    proposal: Proposal, 
    witness: W
) {
    proposal.auth().assert_is_witness(witness);
    account.proposals.add(proposal);
}

/// Increases the global threshold and the role threshold if the signer has the one from the proposal
public fun approve_proposal(
    account: &mut Account, 
    key: String, 
    ctx: &mut TxContext
) {
    account.assert_is_member(ctx);

    let proposal = account.proposals.get_mut(key);
    // asserts that it uses the right AccountProtocol package version
    account.deps.assert_version(proposal.auth(), VERSION);
    let member = account.members.get(ctx.sender()); 
    proposal.approve(member, ctx);
}

/// The signer removes his agreement
public fun remove_approval(
    account: &mut Account, 
    key: String, 
    ctx: &mut TxContext
) {
    let proposal = account.proposals.get_mut(key);
    account.deps.assert_version(proposal.auth(), VERSION);
    let member = account.members.get(ctx.sender()); 
    proposal.disapprove(member, ctx);
}

/// Returns an executable if the number of signers is >= (global || role) threshold
/// Anyone can execute a proposal, this allows to automate the execution of proposals
public fun execute_proposal(
    account: &mut Account, 
    key: String, 
    clock: &Clock,
): Executable {
    let proposal = account.proposals.get(key);
    assert!(clock.timestamp_ms() >= proposal.execution_time(), ECantBeExecutedYet);
    account.thresholds.assert_reached(proposal);

    let (auth, actions) = account.proposals.remove(key);
    account.deps.assert_version(&auth, VERSION);

    executable::new(auth, actions)
}

/// Removes a proposal if it has expired
/// Needs to delete each action in the bag within their own module
public fun delete_proposal(
    account: &mut Account, 
    key: String, 
    ctx: &mut TxContext
): Bag {
    let (auth, actions) = account.proposals.delete(key, ctx);
    account.deps.assert_version(&auth, VERSION);

    actions
}

// === View functions ===

public fun addr(account: &Account): address {
    account.id.uid_to_inner().id_to_address()
}

public fun name(account: &Account): String {
    account.name
}

public fun deps(account: &Account): &Deps {
    &account.deps
}

public fun members(account: &Account): &Members {
    &account.members
}

public fun member(account: &Account, addr: address): &Member {
    account.members.get(addr)
}

public fun thresholds(account: &Account): &Thresholds {
    &account.thresholds
}

public fun proposals(account: &Account): &Proposals {
    &account.proposals
}

public fun proposal(account: &Account, key: String): &Proposal {
    account.proposals.get(key)
}

public fun assert_is_member(account: &Account, ctx: &TxContext) {
    assert!(account.members.is_member(ctx.sender()), ECallerIsNotMember);
}

// === Deps-only functions ===

/// Managed assets:
/// Those are objects attached as dynamic fields to the account object

public fun add_managed_asset<K: copy + drop + store, A: store, W: copy + drop>(
    account: &mut Account, 
    witness: W,
    key: K, 
    asset: A,
) {
    account.deps.assert_dep(witness);
    df::add(&mut account.id, key, asset);
}

public fun borrow_managed_asset<K: copy + drop + store, A: store, W: copy + drop>(
    account: &Account, 
    witness: W,
    key: K, 
): &A {
    account.deps.assert_dep(witness);
    df::borrow(&account.id, key)
}

public fun borrow_managed_asset_mut<K: copy + drop + store, A: store, W: copy + drop>(
    account: &mut Account, 
    witness: W,
    key: K, 
): &mut A {
    account.deps.assert_dep(witness);
    df::borrow_mut(&mut account.id, key)
}

public fun remove_managed_asset<K: copy + drop + store, A: store, W: copy + drop>(
    account: &mut Account, 
    witness: W,
    key: K, 
): A {
    account.deps.assert_dep(witness);
    df::remove(&mut account.id, key)
}

public fun has_managed_asset<K: copy + drop + store>(
    account: &Account, 
    key: K, 
): bool {
    df::exists_(&account.id, key)
}

// === Core Deps only functions ===

/// Owned objects:
/// Those are objects owned by the account

public fun receive<T: key + store, W: copy + drop>(
    account: &mut Account, 
    witness: W,
    receiving: Receiving<T>,
): T {
    account.deps.assert_core_dep(witness);
    transfer::public_receive(&mut account.id, receiving)
}

/// Fields:
/// Those are the fields of the account object

public fun name_mut<W: copy + drop>(
    account: &mut Account, 
    executable: &Executable,
    witness: W,
): &mut String {
    executable.auth().assert_is_witness(witness);
    executable.auth().assert_is_account(account.addr());
    account.deps.assert_core_dep(witness);
    &mut account.name
}

public fun deps_mut<W: copy + drop>(
    account: &mut Account, 
    executable: &Executable,
    witness: W,
): &mut Deps {
    executable.auth().assert_is_witness(witness);
    executable.auth().assert_is_account(account.addr());
    account.deps.assert_core_dep(witness);
    &mut account.deps
}

public fun thresholds_mut<W: copy + drop>(
    account: &mut Account, 
    executable: &Executable,
    witness: W,
): &mut Thresholds {
    executable.auth().assert_is_witness(witness);
    executable.auth().assert_is_account(account.addr());
    account.deps.assert_core_dep(witness);
    &mut account.thresholds
}

public fun members_mut<W: copy + drop>(
    account: &mut Account, 
    executable: &Executable,
    witness: W,
): &mut Members {
    executable.auth().assert_is_witness(witness);
    executable.auth().assert_is_account(account.addr());
    account.deps.assert_core_dep(witness);
    &mut account.members
}

// === Package functions ===

/// Only accessible from account module
public(package) fun member_mut(
    account: &mut Account, 
    addr: address,
): &mut Member {
    account.members.get_mut(addr)
}

// === Test functions ===

#[test_only]
public fun deps_mut_for_testing(
    account: &mut Account, 
): &mut Deps {
    &mut account.deps
}

#[test_only]
public fun name_mut_for_testing(
    account: &mut Account, 
): &mut String {
    &mut account.name
}

#[test_only]
public fun thresholds_mut_for_testing(
    account: &mut Account, 
): &mut Thresholds {
    &mut account.thresholds
}

#[test_only]
public fun members_mut_for_testing(
    account: &mut Account, 
): &mut Members {
    &mut account.members
}

#[test_only]
public fun member_mut_for_testing(
    account: &mut Account, 
    addr: address,
): &mut Member {
    account.members.get_mut(addr)
}


