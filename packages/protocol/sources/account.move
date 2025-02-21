/// This is the core module managing the account Account<Config>.
/// It provides the apis to create, approve and execute intents with actions.
/// 
/// The flow is as follows:
///   1. An intent is created by stacking actions into it. 
///      Actions are pushed from first to last, they must be executed then destroyed in the same order.
///   2. When the intent is resolved (threshold reached, quorum reached, etc), it can be executed. 
///      This returns an Executable hot potato constructed from certain fields of the validated Intent. 
///      It is directly passed into action functions to enforce account approval for an action to be executed.
///   3. The module that created the intent must destroy all of the actions and the Executable after execution 
///      by passing the same witness that was used for instantiation. 
///      This prevents the actions or the intent to be stored instead of executed.
/// 
/// Dependencies can create and manage dynamic fields for an account.
/// They should use custom types as keys to enable access only via the accessors defined.
/// 
/// Functions related to authentication, intent resolution, state of intents and config for an account type 
/// must be called from the module that defines the config of the account.
/// They necessitate a config_witness to ensure the caller is a dependency of the account.
/// 
/// The rest of the functions manipulating the common state of accounts are only called within this package.

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

/// Shared multisig Account object.
public struct Account<Config, Outcome> has key, store {
    id: UID,
    // arbitrary data that can be proposed and added by members
    // first field is a human readable name to differentiate the multisig accounts
    metadata: Metadata,
    // ids and versions of the packages this account is using
    // idx 0: account_protocol, idx 1: account_actions optionally
    deps: Deps,
    // open intents, key should be a unique descriptive name
    intents: Intents<Outcome>,
    // config can be anything (e.g. Multisig, coin-based DAO, etc.)
    config: Config,
}

/// Protected type ensuring provenance.
public struct Auth {
    // address of the account that created the auth
    account_addr: address,
}

// === Public mutative functions ===

fun init(otw: ACCOUNT, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx); // to create Display objects in the future
}

/// Creates a new Account object, called from a config module defining a new account type.
public fun new<Config, Outcome>(
    extensions: &Extensions,
    config: Config, 
    unverified_deps_allowed: bool,
    names: vector<String>,
    addresses: vector<address>,
    versions: vector<u64>,
    ctx: &mut TxContext
): Account<Config, Outcome> {
    Account<Config, Outcome> { 
        id: object::new(ctx),
        metadata: metadata::empty(),
        deps: deps::new(extensions, unverified_deps_allowed, names, addresses, versions),
        intents: intents::empty(),
        config,
    }
}

/// Helper function to transfer an object to the account.
public fun keep<Config, Outcome, T: key + store>(account: &Account<Config, Outcome>, obj: T) {
    transfer::public_transfer(obj, account.addr());
}

/// Unpacks and verifies the Auth matches the account.
public fun verify<Config, Outcome>(
    account: &Account<Config, Outcome>,
    auth: Auth,
) {
    let Auth { account_addr } = auth;

    assert!(account.addr() == account_addr, EWrongAccount);
}

// === Deps-only functions ===

/// The following functions are used to compose intents in external modules and packages.
/// 
/// The proper instantiation and execution of an intent is ensured by an intent witness.
/// This is a drop only type defined in the intent module preventing other modules to misuse the intent.
/// 
/// Additionally, these functions require a version witness which is a protected type for the protocol. 
/// It is checked against the dependencies of the account to ensure the package being called is authorized.
/// VersionWitness is a wrapper around a type defined in the version of the package being called.
/// It behaves like a witness but it is usable in the entire package instead of in a single module.

// Intent lib functions - called in intent modules

/// Creates a new intent that must be constructed in another module.
public fun create_intent<Config, Outcome, IW: copy + drop>(
    account: &mut Account<Config, Outcome>, 
    key: String, // intent key
    description: String, // optional description
    execution_times: vector<u64>, // multiple timestamps in ms for recurrent intents (ascending order)
    expiration_time: u64, // timestamp when the intent can be deleted
    managed_name: String, // managed struct/object name for the role
    outcome: Outcome, // resolution settings
    version_witness: VersionWitness, // proof of the package address that creates the intent
    intent_witness: IW, // intent witness
    ctx: &mut TxContext
): Intent<Outcome> {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness); 
    // set account_addr and intent_type to enforce correct execution
    let issuer = issuer::new(account.addr(), key, intent_witness);
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

/// Adds an action to the intent.
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

/// Adds an intent to the account.
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

// Action lib functions - called in action modules

/// Increases the action index and returns the action.
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
    
    let key = executable.issuer().intent_key();
    let action_idx = executable.next_action();
    account.intents.get(key).actions().borrow(action_idx)
}

/// Verifies all actions have been processed and destroys the executable.
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

    let intent = account.intents.get(executable.issuer().intent_key());
    assert!(executable.action_idx() == intent.actions().length(), EActionsRemaining);
    executable.destroy();
}

/// Destroys an intent if it has no remaining execution.
/// Expired needs to be emptied by deleting each action in the bag within their own module.
public fun destroy_empty_intent<Config, Outcome: drop>(
    account: &mut Account<Config, Outcome>, 
    key: String, 
): Expired {
    assert!(account.intents.get(key).execution_times().is_empty(), ECantBeRemovedYet);
    account.intents.destroy(key)
}

/// Destroys an intent if it has expired.
/// Expired needs to be emptied by deleting each action in the bag within their own module.
public fun delete_expired_intent<Config, Outcome: drop>(
    account: &mut Account<Config, Outcome>, 
    key: String, 
    clock: &Clock,
): Expired {
    assert!(clock.timestamp_ms() >= account.intents.get(key).expiration_time(), EHasntExpired);
    account.intents.destroy(key)
}

/// Managed data and assets:
/// Data structs and Assets objects attached as dynamic fields to the account object.
/// They are separated to improve objects discoverability on frontends and indexers.
/// Keys must be custom types defined in the same module where the function is implemented.

/// Adds a managed data struct to the account.
public fun add_managed_data<Config, Outcome, K: copy + drop + store, Data: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    data: Data,
    version_witness: VersionWitness,
) {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    df::add(&mut account.id, key, data);
}

/// Checks if a managed data struct exists in the account.
public fun has_managed_data<Config, Outcome, K: copy + drop + store>(
    account: &Account<Config, Outcome>, 
    key: K, 
): bool {
    df::exists_(&account.id, key)
}

/// Borrows a managed data struct from the account.
public fun borrow_managed_data<Config, Outcome, K: copy + drop + store, Data: store>(
    account: &Account<Config, Outcome>,
    key: K, 
    version_witness: VersionWitness,
): &Data {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    df::borrow(&account.id, key)
}

/// Borrows a managed data struct mutably from the account.
public fun borrow_managed_data_mut<Config, Outcome, K: copy + drop + store, Data: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version_witness: VersionWitness,
): &mut Data {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    df::borrow_mut(&mut account.id, key)
}

/// Removes a managed data struct from the account.
public fun remove_managed_data<Config, Outcome, K: copy + drop + store, A: store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version_witness: VersionWitness,
): A {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    df::remove(&mut account.id, key)
}

/// Adds a managed object to the account.
public fun add_managed_asset<Config, Outcome, K: copy + drop + store, Asset: key + store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    asset: Asset,
    version_witness: VersionWitness,
) {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    dof::add(&mut account.id, key, asset);
}

/// Checks if a managed object exists in the account.
public fun has_managed_asset<Config, Outcome, K: copy + drop + store>(
    account: &Account<Config, Outcome>, 
    key: K, 
): bool {
    dof::exists_(&account.id, key)
}

/// Borrows a managed object from the account.
public fun borrow_managed_asset<Config, Outcome, K: copy + drop + store, Asset: key + store>(
    account: &Account<Config, Outcome>,
    key: K, 
    version_witness: VersionWitness,
): &Asset {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    dof::borrow(&account.id, key)
}

/// Borrows a managed object mutably from the account.
public fun borrow_managed_asset_mut<Config, Outcome, K: copy + drop + store, Asset: key + store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version_witness: VersionWitness,
): &mut Asset {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    dof::borrow_mut(&mut account.id, key)
}

/// Removes a managed object from the account.
public fun remove_managed_asset<Config, Outcome, K: copy + drop + store, Asset: key + store>(
    account: &mut Account<Config, Outcome>, 
    key: K, 
    version_witness: VersionWitness,
): Asset {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    dof::remove(&mut account.id, key)
}

// === Config-only functions ===

/// The following functions are used to define account and intent behavior for a specific account type/config.
/// 
/// They must be implemented in the module that defines the config of the account, which must be a dependency of the account.

/// Returns an Auth object that can be used to call certain functions with the account.
public fun new_auth<Config, Outcome, CW: drop>(
    account: &Account<Config, Outcome>,
    version_witness: VersionWitness,
    config_witness: CW,
): Auth {
    account.deps().check(version_witness);
    account.assert_is_config_module(config_witness);

    Auth { account_addr: account.addr() }
}

/// Returns an Executable with the Intent Outcome that must be validated in the config module.
public fun execute_intent<Config, Outcome: copy, CW: drop>(
    account: &mut Account<Config, Outcome>,
    key: String, 
    clock: &Clock,
    version_witness: VersionWitness,
    config_witness: CW,
): (Executable, Outcome) {
    account.deps().check(version_witness);
    account.assert_is_config_module(config_witness);

    let intent = account.intents.get_mut(key);
    let time = intent.pop_front_execution_time();
    assert!(clock.timestamp_ms() >= time, ECantBeExecutedYet);

    (
        executable::new(*intent.issuer()), 
        *intent.outcome()
    )
}

/// Returns a mutable reference to the intents of the account.
public fun intents_mut<Config, Outcome, CW: drop>(
    account: &mut Account<Config, Outcome>, 
    version_witness: VersionWitness,
    config_witness: CW,
): &mut Intents<Outcome> {
    account.deps().check(version_witness);
    account.assert_is_config_module(config_witness);

    &mut account.intents
}

/// Returns a mutable reference to the config of the account.
public fun config_mut<Config, Outcome, CW: drop>(
    account: &mut Account<Config, Outcome>, 
    version_witness: VersionWitness,
    config_witness: CW,
): &mut Config {
    account.deps().check(version_witness);
    account.assert_is_config_module(config_witness);

    &mut account.config
}

// === View functions ===

/// Returns the address of the account.
public fun addr<Config, Outcome>(account: &Account<Config, Outcome>): address {
    account.id.uid_to_inner().id_to_address()
}

/// Returns the metadata of the account.
public fun metadata<Config, Outcome>(account: &Account<Config, Outcome>): &Metadata {
    &account.metadata
}

/// Returns the dependencies of the account.
public fun deps<Config, Outcome>(account: &Account<Config, Outcome>): &Deps {
    &account.deps
}

/// Returns the intents of the account.
public fun intents<Config, Outcome>(account: &Account<Config, Outcome>): &Intents<Outcome> {
    &account.intents
}

/// Returns the config of the account.
public fun config<Config, Outcome>(account: &Account<Config, Outcome>): &Config {
    &account.config
}

// === Package functions ===

/// Returns a mutable reference to the metadata of the account.
public(package) fun metadata_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    version_witness: VersionWitness,
): &mut Metadata {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    &mut account.metadata
}

/// Returns a mutable reference to the dependencies of the account.
public(package) fun deps_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    version_witness: VersionWitness,
): &mut Deps {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    &mut account.deps
}

/// Receives an object from an account, only used in owned action lib module.
public(package) fun receive<Config, Outcome, T: key + store>(
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<T>,
): T {
    transfer::public_receive(&mut account.id, receiving)
}

/// Locks an object in the account, preventing it to be used in another intent.
public(package) fun lock_object<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    id: ID,
) {
    account.intents.lock(id);
}

/// Unlocks an object in the account, allowing it to be used in another intent.
public(package) fun unlock_object<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    id: ID,
) {
    account.intents.unlock(id);
}

/// Asserts that the function is called from the module defining the config of the account.
public(package) fun assert_is_config_module<Config, Outcome, CW: drop>(
    _account: &Account<Config, Outcome>, 
    _config_witness: CW
) {
    let account_type = type_name::get<Config>();
    let witness_type = type_name::get<CW>();
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
public fun deps_mut_for_testing<Config, Outcome>(account: &mut Account<Config, Outcome>): &mut Deps {
    &mut account.deps
}