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
    type_name::{Self, TypeName},
};
use sui::{
    hex,
    address,
    transfer::Receiving,
    clock::Clock, 
    dynamic_field as df,
    dynamic_object_field as dof,
    package,
};
use account_protocol::{
    issuer,
    metadata::{Self, Metadata},
    deps::{Self, Deps},
    intents::{Self, Intents, Intent, Expired},
    executable::{Self, Executable},
};
use account_extensions::extensions::Extensions;

// === Errors ===

const EInvalidAction: u64 = 0;
const ECantBeRemovedYet: u64 = 1;
const EHasntExpired: u64 = 2;
const ECantBeExecutedYet: u64 = 3;
const EWrongAccount: u64 = 4;

// === Structs ===

public struct ACCOUNT has drop {}

/// Shared multisig Account object 
public struct Account<Config, Outcome> has key, store {
    id: UID,
    // arbitrary data that can be proposed and added by members
    // first field is a human readable name to differentiate the multisig accounts
    metadata: Metadata,
    // ids and versions of the packages this account is using
    // idx 0: account_protocol, idx 1: account_actions
    deps: Deps,
    // open proposals, key should be a unique descriptive name
    intents: Intents<Outcome>,
    // config can be anything (e.g. Multisig, coin-based DAO, etc.)
    config: Config,
}

/// Protected type ensuring provenance
public struct Auth {
    // address of the account that created the auth
    account_addr: address,
}

// === Public mutative functions ===

fun init(otw: ACCOUNT, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx);
}

/// Creates a new Account object, called from AccountConfig
public fun new<Config, Outcome>(
    extensions: &Extensions,
    config: Config, 
    ctx: &mut TxContext
): Account<Config, Outcome> {
    Account<Config, Outcome> { 
        id: object::new(ctx),
        metadata: metadata::new(),
        deps: deps::new(extensions),
        intents: intents::empty(),
        config,
    }
}

public fun keep<Config, Outcome, T: key + store>(account: &Account<Config, Outcome>, obj: T) {
    transfer::public_transfer(obj, account.addr());
}

public fun new_auth(
    extensions: &Extensions,
    account_addr: address,
    version: TypeName,
): Auth {
    let addr = address::from_bytes(hex::decode(version.get_address().into_bytes()));
    extensions.assert_is_core_extension(addr);

    Auth { account_addr }
}

public fun verify(
    auth: Auth,
    addr: address,
) {
    let Auth { account_addr } = auth;

    assert!(addr == account_addr, EWrongAccount);
}

// === Proposal functions ===

/// Creates a new proposal that must be constructed in another module
/// Only packages (instantiating the witness) allowed in extensions can create an issuer
public fun create_intent<Config, Outcome, W: drop>(
    account: &mut Account<Config, Outcome>, 
    auth: Auth, // proves that the caller is a member
    key: String, // proposal key
    description: String,
    execution_times: vector<u64>, // timestamps in ms
    expiration_time: u64, // epoch when we can delete the proposal
    outcome: Outcome, // vote settings
    version: TypeName,
    witness: W, // module's issuer witness (proposal/role witness)
    opt_name: String, // module's issuer name (role name)
    ctx: &mut TxContext
): Intent<Outcome> {
    // ensures the caller is authorized for this account
    auth.verify(account.addr());
    // only an account dependency can create a proposal
    account.deps().assert_is_dep(version);

    let issuer = issuer::construct(
        account.addr(), 
        witness, 
        opt_name
    );

    intents::new_intent(
        issuer,
        key,
        description,
        execution_times,
        expiration_time,
        outcome,
        ctx
    )
}

public fun lock_object<Config, Outcome, W: drop>(
    account: &mut Account<Config, Outcome>,
    intent: &Intent<Outcome>, 
    id: ID,
    version: TypeName,
    witness: W,
) {
    account.deps().assert_is_core_dep(version);  
    intent.issuer().assert_is_account(account.addr());
    intent.issuer().assert_is_constructor(witness);

    account.intents_mut(version).lock(id);
}

public fun unlock_object<Config, Outcome, Action, W: drop>(
    account: &mut Account<Config, Outcome>,
    expired: &Expired, 
    _action: &Action,
    id: ID,
    version: TypeName,
    _: W, // this one is to check that unlock is called from the module that defined the action
) {
    account.deps().assert_is_core_dep(version);  
    expired.issuer().assert_is_account(account.addr());
    assert!(
        type_name::get<Action>().get_address() == type_name::get<W>().get_address() && 
        type_name::get<Action>().get_module() == type_name::get<W>().get_module(),
        EInvalidAction
    );

    account.intents_mut(version).unlock(id);
}

/// Adds a proposal to the account
/// must be called by the same proposal interface that created it
public fun add_intent<Config, Outcome, W: drop>(
    account: &mut Account<Config, Outcome>, 
    intent: Intent<Outcome>, 
    version: TypeName,
    witness: W,
) {
    account.deps().assert_is_dep(version);  
    intent.issuer().assert_is_account(account.addr());
    intent.issuer().assert_is_constructor(witness);

    account.intents.add(intent);
}

/// Called by CoreDep only, AccountConfig
/// Returns an Executable with the Proposal Outcome that must be validated in AccountCOnfig
public fun execute_intent<Config, Outcome: copy>(
    account: &mut Account<Config, Outcome>,
    key: String, 
    clock: &Clock,
    version: TypeName,
): (Executable, Outcome) {
    account.deps().assert_is_core_dep(version);
    let intent = account.intents.get_mut(key);

    let time = intent.pop_front_execution_time();
    assert!(clock.timestamp_ms() >= time, ECantBeExecutedYet);

    (executable::new(key, *intent.issuer()), *intent.outcome())
}

/// Called in action modules
public fun process_action<Config, Outcome, Action: store, W: drop>(
    account: &Account<Config, Outcome>, 
    executable: &mut Executable,
    version: TypeName,
    witness: W,
): &Action {
    account.deps().assert_is_dep(version);

    let (key, idx) = executable.next_action(account.addr(), witness);
    account.intents.get(key).actions().borrow(idx)
}

/// Called in action modules
public fun confirm_execution<Config, Outcome, W: drop>(
    account: &Account<Config, Outcome>, 
    executable: Executable,
    version: TypeName,
    witness: W,
) {
    account.deps().assert_is_dep(version);    

    let intent = account.intents.get(executable.key());
    executable.destroy(intent.actions().length(), witness);
}

/// Called in config modules
public fun destroy_empty_intent<Config, Outcome: drop>(
    account: &mut Account<Config, Outcome>, 
    key: String, 
): Expired {
    assert!(account.intents.get(key).execution_times().is_empty(), ECantBeRemovedYet);
    account.intents.destroy(key)
}

/// Called in config modules
/// Removes a proposal if it has expired
/// Needs to delete each action in the bag within their own module
public fun delete_expired_intent<Config, Outcome: drop>(
    account: &mut Account<Config, Outcome>, 
    key: String, 
    clock: &Clock,
): Expired {
    assert!(clock.timestamp_ms() >= account.intents.get(key).expiration_time(), EHasntExpired);
    account.intents.destroy(key)
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

public fun intents<Config, Outcome>(account: &Account<Config, Outcome>): &Intents<Outcome> {
    &account.intents
}

public fun config<Config, Outcome>(account: &Account<Config, Outcome>): &Config {
    &account.config
}

// === Deps-only functions ===

/// Managed structs and objects:
/// Structs and objects attached as dynamic fields to the account object.
/// They are separated to improve objects discoverability on frontends and indexers.
/// Keys must be custom types defined in the same module where the function is called
/// The version typename should be issued from the same package and is checked against dependencies

public fun add_managed_struct<Config, Outcome, K: copy + drop + store, Struct: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    `struct`: Struct,
    version: TypeName,
) {
    account.deps.assert_is_dep(version);
    df::add(&mut account.id, key, `struct`);
}

public fun has_managed_struct<Config, Outcome, K: copy + drop + store>(
    account: &Account<Config, Outcome>, 
    key: K, 
): bool {
    df::exists_(&account.id, key)
}

public fun borrow_managed_struct<Config, Outcome, K: copy + drop + store, Struct: store>(
    account: &Account<Config, Outcome>,
    key: K, 
    version: TypeName,
): &Struct {
    account.deps.assert_is_dep(version);
    df::borrow(&account.id, key)
}

public fun borrow_managed_struct_mut<Config, Outcome, K: copy + drop + store, Struct: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version: TypeName,
): &mut Struct {
    account.deps.assert_is_dep(version);
    df::borrow_mut(&mut account.id, key)
}

public fun remove_managed_struct<Config, Outcome, K: copy + drop + store, A: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version: TypeName,
): A {
    account.deps.assert_is_dep(version);
    df::remove(&mut account.id, key)
}

public fun add_managed_object<Config, Outcome, K: copy + drop + store, Obj: key + store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    obj: Obj,
    version: TypeName,
) {
    account.deps.assert_is_dep(version);
    dof::add(&mut account.id, key, obj);
}

public fun has_managed_object<Config, Outcome, K: copy + drop + store>(
    account: &Account<Config, Outcome>, 
    key: K, 
): bool {
    dof::exists_(&account.id, key)
}

public fun borrow_managed_object<Config, Outcome, K: copy + drop + store, Obj: key + store>(
    account: &Account<Config, Outcome>,
    key: K, 
    version: TypeName,
): &Obj {
    account.deps.assert_is_dep(version);
    dof::borrow(&account.id, key)
}

public fun borrow_managed_object_mut<Config, Outcome, K: copy + drop + store, Obj: key + store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version: TypeName,
): &mut Obj {
    account.deps.assert_is_dep(version);
    dof::borrow_mut(&mut account.id, key)
}

public fun remove_managed_object<Config, Outcome, K: copy + drop + store, Obj: key + store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version: TypeName,
): Obj {
    account.deps.assert_is_dep(version);
    dof::remove(&mut account.id, key)
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

public fun intents_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    version: TypeName,
): &mut Intents<Outcome> {
    account.deps.assert_is_core_dep(version);
    &mut account.intents
}

public fun config_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    version: TypeName,
): &mut Config {
    account.deps.assert_is_core_dep(version);
    &mut account.config
}

// === Test functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ACCOUNT {}, ctx);
}