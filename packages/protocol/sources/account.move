/// This is the core module managing the account Account<Config>.
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

use std::{
    string::String,
    type_name::TypeName,
};
use sui::{
    transfer::Receiving,
    clock::Clock, 
    dynamic_field as df,
};
use account_protocol::{
    source,
    metadata::{Self, Metadata},
    deps::{Self, Deps},
    proposals::{Self, Proposals, Proposal, Expired},
    executable::{Self, Executable},
    auth::Auth,
};
use account_extensions::extensions::Extensions;

// === Structs ===

/// Shared multisig Account object 
public struct Account<Config, Outcome> has key {
    id: UID,
    // arbitrary data that can be proposed and added by members
    // first field is a human readable name to differentiate the multisig accounts
    metadata: Metadata,
    // ids and versions of the packages this account is using
    // idx 0: account_protocol, idx 1: account_actions
    deps: Deps,
    // open proposals, key should be a unique descriptive name
    proposals: Proposals<Outcome>,
    // config can be anything (e.g. Multisig, coin-based DAO, etc.)
    config: Config,
}

// === Public mutative functions ===

/// Creates a new Account object, called from AccountConfig
public fun new<Config, Outcome>(
    extensions: &Extensions,
    name: String, 
    config: Config, 
    ctx: &mut TxContext
): Account<Config, Outcome> {
    Account<Config, Outcome> { 
        id: object::new(ctx),
        metadata: metadata::new(name),
        deps: deps::new(extensions),
        proposals: proposals::empty(),
        config,
    }
}

/// Can be initialized by the creator before being shared
#[allow(lint(share_owned))]
public fun share<Config: store, Outcome: store>(account: Account<Config, Outcome>) {
    transfer::share_object(account);
}

public fun keep<Config, Outcome, T: key + store>(account: &Account<Config, Outcome>, obj: T) {
    transfer::public_transfer(obj, account.addr());
}

// === Proposal functions ===

/// Creates a new proposal that must be constructed in another module
/// Only packages (instantiating the witness) allowed in extensions can create an source
public fun create_proposal<Config, Outcome, W: drop>(
    account: &mut Account<Config, Outcome>, 
    auth: Auth, // proves that the caller is a member
    outcome: Outcome, // vote settings
    version: TypeName,
    witness: W, // module's source witness (proposal/role witness)
    w_name: String, // module's source name (role name)
    key: String, // proposal key
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64, // epoch when we can delete the proposal
    ctx: &mut TxContext
): Proposal<Outcome> {
    // ensures the caller is authorized for this account
    auth.verify(account.addr());
    // only an account dependency can create a proposal
    account.deps().assert_is_dep(version);

    let source = source::construct(
        account.addr(), 
        version,
        witness, 
        w_name
    );

    proposals::new_proposal(
        source,
        key,
        description,
        execution_time,
        expiration_epoch,
        outcome,
        ctx
    )
}

/// Adds a proposal to the account
/// must be called by the same proposal interface that created it
public fun add_proposal<Config, Outcome, W: drop>(
    account: &mut Account<Config, Outcome>, 
    proposal: Proposal<Outcome>, 
    version: TypeName,
    witness: W
) {
    account.deps().assert_is_dep(version);  
    proposal.source().assert_is_constructor(witness);  
    account.proposals.add(proposal);
}

/// Called by CoreDep only, AccountConfig
/// Returns an Executable with the Proposal Outcome that must be validated in AccountCOnfig
public fun execute_proposal<Config, Outcome>(
    account: &mut Account<Config, Outcome>,
    key: String, 
    clock: &Clock,
    version: TypeName,
    ctx: &mut TxContext,
): (Executable, Outcome) {
    account.deps().assert_is_core_dep(version);
    let (source, actions, outcome) = account.proposals.remove(key, clock);

    (executable::new(account.deps, source, actions, ctx), outcome)
}

/// Removes a proposal if it has expired
/// Needs to delete each action in the bag within their own module
public fun delete_proposal<Config: drop, Outcome>(
    account: &mut Account<Config, Outcome>, 
    key: String, 
    version: TypeName,
    ctx: &mut TxContext
): Expired<Outcome> {
    let expired = account.proposals.delete(key, ctx);

    account.deps().assert_is_core_dep(version);

    expired
}

// === View functions ===

public fun addr<Config, Outcome>(account: &Account<Config, Outcome>): address {
    account.id.uid_to_inner().id_to_address()
}

public fun metadata<Config, Outcome>(account: &Account<Config, Outcome>): &Metadata {
    &account.metadata
}

public fun deps<Config, Outcome>(account: &Account<Config, Outcome>): &Deps {
    &account.deps
}

public fun proposals<Config, Outcome>(account: &Account<Config, Outcome>): &Proposals<Outcome> {
    &account.proposals
}

public fun proposal<Config, Outcome>(account: &Account<Config, Outcome>, key: String): &Proposal<Outcome> {
    account.proposals.get(key)
}

public fun config<Config, Outcome>(account: &Account<Config, Outcome>): &Config {
    &account.config
}

// === Deps-only functions ===

/// Managed assets:
/// Objects attached as dynamic fields to the account object
/// Keys must be custom types defined in the same module where the function is called
/// The key type is checked against dependencies

public fun add_managed_asset<Config, Outcome, K: copy + drop + store, A: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    asset: A,
    version: TypeName,
) {
    account.deps.assert_is_dep(version);
    df::add(&mut account.id, key, asset);
}

public fun borrow_managed_asset<Config, Outcome, K: copy + drop + store, A: store>(
    account: &Account<Config, Outcome>,
    key: K, 
    version: TypeName,
): &A {
    account.deps.assert_is_dep(version);
    df::borrow(&account.id, key)
}

public fun borrow_managed_asset_mut<Config, Outcome, K: copy + drop + store, A: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version: TypeName,
): &mut A {
    account.deps.assert_is_dep(version);
    df::borrow_mut(&mut account.id, key)
}

public fun remove_managed_asset<Config, Outcome, K: copy + drop + store, A: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version: TypeName,
): A {
    account.deps.assert_is_dep(version);
    df::remove(&mut account.id, key)
}

public fun has_managed_asset<Config, Outcome, K: copy + drop + store>(
    account: &Account<Config, Outcome>, 
    key: K, 
): bool {
    df::exists_(&account.id, key)
}

// === Core Deps only functions ===

/// Owned objects:
/// Objects owned by the account

public fun receive<Config, Outcome, T: key + store>(
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<T>,
    version: TypeName,
): T {
    account.deps.assert_is_core_dep(version);
    transfer::public_receive(&mut account.id, receiving)
}

/// Fields:
/// Fields of the account object

public fun metadata_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    version: TypeName,
): &mut Metadata {
    account.deps.assert_is_core_dep(version);
    &mut account.metadata
}

public fun deps_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    version: TypeName,
): &mut Deps {
    account.deps.assert_is_core_dep(version);
    &mut account.deps
}

public fun proposals_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    version: TypeName,
): &mut Proposals<Outcome> {
    account.deps.assert_is_core_dep(version);
    &mut account.proposals
}

public fun config_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    version: TypeName,
): &mut Config {
    account.deps.assert_is_core_dep(version);
    &mut account.config
}

/// Only called in AccountConfig
public fun outcome_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    key: String,
    version: TypeName,
): &mut Outcome {
    account.deps.assert_is_core_dep(version);
    account.proposals.get_mut(key).outcome_mut()
}

// === Test functions ===

#[test_only]
public fun deps_mut_for_testing<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
): &mut Deps {
    &mut account.deps
}