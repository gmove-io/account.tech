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
    type_name,
};
use sui::{
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
    version_witness::VersionWitness,
    intents::{Self, Intents, Intent, Expired},
    executable::{Self, Executable},
};
use account_extensions::extensions::Extensions;

// === Errors ===

const ECantBeRemovedYet: u64 = 1;
const EHasntExpired: u64 = 2;
const ECantBeExecutedYet: u64 = 3;
const EWrongAccount: u64 = 4;
const ENotCalledFromConfigModule: u64 = 5;
const EActionsRemaining: u64 = 6;

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

/// Creates a new Account object, called from a config module
public fun new<Config, Outcome>(
    extensions: &Extensions,
    config: Config, 
    unverified_deps_allowed: bool,
    ctx: &mut TxContext
): Account<Config, Outcome> {
    Account<Config, Outcome> { 
        id: object::new(ctx),
        metadata: metadata::empty(),
        deps: deps::new(extensions, unverified_deps_allowed),
        intents: intents::empty(),
        config,
    }
}

/// Helper function to transfer an object to the account
public fun keep<Config, Outcome, T: key + store>(account: &Account<Config, Outcome>, obj: T) {
    transfer::public_transfer(obj, account.addr());
}

/// Verifies the Auth matches the account 
public fun verify<Config, Outcome>(
    account: &Account<Config, Outcome>,
    auth: Auth,
) {
    let Auth { account_addr } = auth;

    assert!(account.addr() == account_addr, EWrongAccount);
}

// === Deps-only functions ===

/// Creates a new intent that must be constructed in another module
/// Only an authorized address can create an intent from a package which is a dependency
public fun create_intent<Config, Outcome, IW: copy + drop>(
    account: &mut Account<Config, Outcome>, 
    key: String, // proposal key
    description: String, // optional description
    execution_times: vector<u64>, // multiple timestamps in ms for recurrent intents (ascending order)
    expiration_time: u64, // timestamp when the proposal can be deleted
    managed_name: String, // managed struct/object name
    outcome: Outcome, // resolution settings
    version_witness: VersionWitness, // proof of the package address that creates the intent
    intent_witness: IW, // intent witness
    ctx: &mut TxContext
): Intent<Outcome> {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness); 
    // set account_addr and intent_type to enforce correct execution
    let issuer = issuer::new(account.addr(), intent_witness);
    // creates a role from the intent package id and module name with an optional name
    let role = intents::new_role<IW>(managed_name, intent_witness);

    intents::new_intent(
        issuer,
        key,
        description,
        execution_times,
        expiration_time,
        role,
        outcome,
        ctx
    )
}

/// Adds an action to the intent
/// must be called from the same intent interface that created it
/// and from a package that is a dependency
public fun add_action<Config, Outcome, Action: store, IW: drop>(
    account: &Account<Config, Outcome>, 
    intent: &mut Intent<Outcome>,
    action: Action,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    // ensures the package address is a dependency of this account
    account.deps().check(version_witness);
    // ensures the right account is passed
    intent.issuer().assert_is_account(account.addr());
    // ensures the intent is created by the same package that creates the action
    intent.issuer().assert_is_intent(intent_witness);

    intent.add_action(action);
}

/// Adds an intent to the account
/// must be called by the same intent interface that created it
/// and from a package that is a dependency
public fun add_intent<Config, Outcome, IW: drop>(
    account: &mut Account<Config, Outcome>, 
    intent: Intent<Outcome>, 
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    // ensures the right account is passed
    intent.issuer().assert_is_account(account.addr());
    // ensures the intent is created by the same package that creates the action
    intent.issuer().assert_is_intent(intent_witness);

    account.intents.add_intent(intent);
}

/// Called in action modules
public fun process_action<Config, Outcome, Action: store, IW: drop>(
    account: &Account<Config, Outcome>, 
    executable: &mut Executable,
    version_witness: VersionWitness,
    intent_witness: IW,
): &Action {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    // ensures the right account is passed
    executable.issuer().assert_is_account(account.addr());
    // ensures the intent is created by the same package that creates the action
    executable.issuer().assert_is_intent(intent_witness);
    
    let (key, idx) = executable.next_action();
    account.intents.get(key).actions().borrow(idx)
}

/// Called in action modules
public fun confirm_execution<Config, Outcome, IW: drop>(
    account: &Account<Config, Outcome>, 
    executable: Executable,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    // ensures the right account is passed
    executable.issuer().assert_is_account(account.addr());
    // ensures the intent is created by the same package that creates the action
    executable.issuer().assert_is_intent(intent_witness);

    let intent = account.intents.get(executable.key());
    assert!(executable.action_idx() == intent.actions().length(), EActionsRemaining);
    executable.destroy();
}

/// Called in config modules or directly
public fun destroy_empty_intent<Config, Outcome: drop>(
    account: &mut Account<Config, Outcome>, 
    key: String, 
): Expired {
    assert!(account.intents.get(key).execution_times().is_empty(), ECantBeRemovedYet);
    account.intents.destroy(key)
}

/// Called in config modules or directly
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

/// Managed structs and objects:
/// Structs and objects attached as dynamic fields to the account object.
/// They are separated to improve objects discoverability on frontends and indexers.
/// Keys must be custom types defined in the same module where the function is called
/// The version typename should be issued from the same package and is checked against dependencies

public fun add_managed_struct<Config, Outcome, K: copy + drop + store, Struct: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    `struct`: Struct,
    version_witness: VersionWitness,
) {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
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
    version_witness: VersionWitness,
): &Struct {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    df::borrow(&account.id, key)
}

public fun borrow_managed_struct_mut<Config, Outcome, K: copy + drop + store, Struct: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version_witness: VersionWitness,
): &mut Struct {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    df::borrow_mut(&mut account.id, key)
}

public fun remove_managed_struct<Config, Outcome, K: copy + drop + store, A: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version_witness: VersionWitness,
): A {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    df::remove(&mut account.id, key)
}

public fun add_managed_object<Config, Outcome, K: copy + drop + store, Obj: key + store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    obj: Obj,
    version_witness: VersionWitness,
) {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
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
    version_witness: VersionWitness,
): &Obj {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    dof::borrow(&account.id, key)
}

public fun borrow_managed_object_mut<Config, Outcome, K: copy + drop + store, Obj: key + store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version_witness: VersionWitness,
): &mut Obj {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    dof::borrow_mut(&mut account.id, key)
}

public fun remove_managed_object<Config, Outcome, K: copy + drop + store, Obj: key + store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version_witness: VersionWitness,
): Obj {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    dof::remove(&mut account.id, key)
}

// === Config-only functions ===

/// Can only be called from the module that defines the config of the account
public fun new_auth<Config, Outcome, CW: drop>(
    account: &Account<Config, Outcome>,
    _config_witness: CW,
): Auth {
    assert_is_config_module<Config, CW>();
    Auth { account_addr: account.addr() }
}

/// Can only be called from the module that defines the config of the account
/// Returns an Executable with the Proposal Outcome that must be validated in AccountCOnfig
public fun execute_intent<Config, Outcome: copy, CW: drop>(
    account: &mut Account<Config, Outcome>,
    key: String, 
    clock: &Clock,
    version_witness: VersionWitness,
    _config_witness: CW,
): (Executable, Outcome) {
    account.deps().check(version_witness);
    assert_is_config_module<Config, CW>();

    let intent = account.intents.get_mut(key);
    let time = intent.pop_front_execution_time();
    assert!(clock.timestamp_ms() >= time, ECantBeExecutedYet);

    (executable::new(*intent.issuer(), key), *intent.outcome())
}

public fun intents_mut<Config, Outcome, CW: drop>(
    account: &mut Account<Config, Outcome>, 
    version_witness: VersionWitness,
    _config_witness: CW,
): &mut Intents<Outcome> {
    account.deps().check(version_witness);
    assert_is_config_module<Config, CW>();

    &mut account.intents
}

public fun config_mut<Config, Outcome, CW: drop>(
    account: &mut Account<Config, Outcome>, 
    version_witness: VersionWitness,
    _config_witness: CW,
): &mut Config {
    account.deps().check(version_witness);
    assert_is_config_module<Config, CW>();

    &mut account.config
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

// === Package functions ===

/// Fields of the account object

public(package) fun metadata_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    version_witness: VersionWitness,
): &mut Metadata {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    &mut account.metadata
}

public(package) fun deps_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    version_witness: VersionWitness,
): &mut Deps {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    &mut account.deps
}

/// Objects owned by the account

public(package) fun receive<Config, Outcome, T: key + store>(
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<T>,
): T {
    transfer::public_receive(&mut account.id, receiving)
}

public(package) fun lock_object<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    id: ID,
) {
    account.intents.lock(id);
}

public(package) fun unlock_object<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    id: ID,
) {
    account.intents.unlock(id);
}

// === Private functions ===

fun assert_is_config_module<Config, W>() {
    let account_type = type_name::get<Config>();
    let witness_type = type_name::get<W>();
    assert!(
        account_type.get_address() == witness_type.get_address() &&
        account_type.get_module() == witness_type.get_module(),
        ENotCalledFromConfigModule
    );
}

// === Test functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ACCOUNT {}, ctx);
}

#[test_only]
public struct Witness() has drop;

#[test_only]
public fun not_config_witness(): Witness {
    Witness()
}

#[test_only]
public fun deps_mut_for_testing<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
): &mut Deps {
    // ensures the package address is a dependency for this account
    &mut account.deps
}