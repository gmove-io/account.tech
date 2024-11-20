/// Users have a non-transferable User account object used to track Accounts in which they are a member.
/// They can also set a username and profile picture to be displayed on the various frontends.
/// Account members can send on-chain invites to new members. 
/// Alternatively, multisig Account creators can share an invite link to new members that can join the Account without invite.
/// Invited users can accept or refuse the invite, to add the Account id to their User account or not.
/// This avoid the need for an indexer as all data can be easily found on-chain.

module account_config::user;

// === Imports ===

use std::string::String;
use sui::{
    vec_map::{Self, VecMap},
    table::{Self, Table},
};

// === Errors ===

#[error]
const ENotEmpty: vector<u8> = b"User must leave all accounts before destroying their User object";
#[error]
const EAlreadyHasUser: vector<u8> = b"User already has a User object";
#[error]
const EAccountNotFound: vector<u8> = b"Account not found in User";
#[error]
const EAccountTypeDoesntExist: vector<u8> = b"Account type doesn't exist in User";
#[error]
const EWrongUserId: vector<u8> = b"The User ID for caller in Registry does not match the User object";
#[error]
const EAccountAlreadyRegistered: vector<u8> = b"Account ID already registered for this type";

// === Struct ===

/// Shared object enforcing one account maximum per user
public struct Registry has key {
    id: UID,
    // address to User ID mapping
    users: Table<address, ID>,
}

/// Non-transferable user account for tracking Accounts
public struct User has key {
    id: UID,
    // account type to list of accounts that the user has joined
    accounts: VecMap<String, vector<address>>,
}

// === Public functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(Registry {
        id: object::new(ctx),
        users: table::new(ctx),
    });
}

/// Creates a soulbound User account (1 per address)
public fun new(ctx: &mut TxContext): User {
    User {
        id: object::new(ctx),
        accounts: vec_map::empty(),
    }
}

// === [MEMBER] Public functions ===

public(package) fun add_account(user: &mut User, account_addr: address, account_type: String) {
    if (user.accounts.contains(&account_type)) {
        assert!(!user.accounts[&account_type].contains(&account_addr), EAccountAlreadyRegistered);
        user.accounts.get_mut(&account_type).push_back(account_addr);
    } else {
        user.accounts.insert(account_type, vector<address>[account_addr]);
    }
}

public(package) fun remove_account(user: &mut User, account_addr: address, account_type: String) {
    assert!(user.accounts.contains(&account_type), EAccountTypeDoesntExist);
    let (exists, idx) = user.accounts[&account_type].index_of(&account_addr);
    
    assert!(exists, EAccountNotFound);
    user.accounts.get_mut(&account_type).swap_remove(idx);

    if (user.accounts[&account_type].is_empty())
        (_, _) = user.accounts.remove(&account_type);
}

/// Can transfer the User object only if the other address has no User object yet
public fun transfer(registry: &mut Registry, user: User, recipient: address, ctx: &mut TxContext) {
    assert!(!registry.users.contains(recipient), EAlreadyHasUser);
    // if the sender is not in the registry, then the User has been just created
    if (registry.users.contains(ctx.sender())) {
        let id = registry.users.remove(ctx.sender());
        assert!(id == object::id(&user), EWrongUserId); // should never happen
    };

    registry.users.add(recipient, object::id(&user));
    transfer::transfer(user, recipient);
}

/// Must leave all Accounts before, for consistency
public fun destroy(registry: &mut Registry, user: User, ctx: &mut TxContext) {
    let User { id, accounts, .. } = user;
    assert!(accounts.is_empty(), ENotEmpty);

    id.delete();
    registry.users.remove(ctx.sender());
}

// === View functions ===    

public fun users(registry: &Registry): &Table<address, ID> {
    &registry.users
}

public fun ids_for_type(user: &User, account_type: String): vector<address> {
    user.accounts[&account_type]
}

public fun all_ids(user: &User): vector<address> {
    let mut map = user.accounts;
    let mut ids = vector<address>[];

    while (!map.is_empty()) {
        let (_, vec) = map.pop();
        ids.append(vec);
    };

    ids
}

// === Test functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}