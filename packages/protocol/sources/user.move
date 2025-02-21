/// Users have a non-transferable User account object used to track Accounts in which they are a member.
/// Each account type can define a way to send on-chain invites to Users.
/// Invited users can accept or refuse the invite, to add the Account id to their User account or not.
/// Alternatively, Account interfaces can define rules allowing users to join an Account without invite.
/// This avoid the need for an indexer as all data can be easily found on-chain.

module account_protocol::user;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use sui::{
    vec_map::{Self, VecMap},
    table::{Self, Table},
};
use account_protocol::account::Account;

// === Errors ===

const ENotEmpty: u64 = 0;
const EAlreadyHasUser: u64 = 1;
const EAccountNotFound: u64 = 2;
const EAccountTypeDoesntExist: u64 = 3;
const EWrongUserId: u64 = 4;
const EAccountAlreadyRegistered: u64 = 5;

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

/// Invite object issued by an Account to a user
public struct Invite has key { 
    id: UID, 
    // Account that issued the invite
    account_addr: address,
    // Account type
    account_type: String,
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

/// Must remove all Accounts before, for consistency
public fun destroy(registry: &mut Registry, user: User, ctx: &mut TxContext) {
    let User { id, accounts, .. } = user;
    assert!(accounts.is_empty(), ENotEmpty);

    id.delete();
    registry.users.remove(ctx.sender());
}

/// Invited user can register the Account in his User account
public fun accept_invite(user: &mut User, invite: Invite) {
    let Invite { id, account_addr, account_type } = invite;
    id.delete();
    
    if (user.accounts.contains(&account_type)) {
        assert!(!user.accounts[&account_type].contains(&account_addr), EAccountAlreadyRegistered);
        user.accounts.get_mut(&account_type).push_back(account_addr);
    } else {
        user.accounts.insert(account_type, vector<address>[account_addr]);
    }
}

/// Deletes the invite object
public fun refuse_invite(invite: Invite) {
    let Invite { id, .. } = invite;
    id.delete();
}

// === Config-only functions ===

public fun add_account<Config, Outcome, CW: drop>(
    user: &mut User, 
    account: &Account<Config, Outcome>, 
    config_witness: CW,
) {
    account.assert_is_config_module(config_witness);
    let account_type = type_name::get<Config>().into_string().to_string();

    if (user.accounts.contains(&account_type)) {
        assert!(!user.accounts[&account_type].contains(&account.addr()), EAccountAlreadyRegistered);
        user.accounts.get_mut(&account_type).push_back(account.addr());
    } else {
        user.accounts.insert(account_type, vector<address>[account.addr()]);
    }
}

public fun remove_account<Config, Outcome, CW: drop>(
    user: &mut User, 
    account: &Account<Config, Outcome>, 
    config_witness: CW,
) {
    account.assert_is_config_module(config_witness);
    let account_type = type_name::get<Config>().into_string().to_string();

    assert!(user.accounts.contains(&account_type), EAccountTypeDoesntExist);
    let (exists, idx) = user.accounts[&account_type].index_of(&account.addr());
    
    assert!(exists, EAccountNotFound);
    user.accounts.get_mut(&account_type).swap_remove(idx);

    if (user.accounts[&account_type].is_empty())
        (_, _) = user.accounts.remove(&account_type);
}

/// Invites can be sent by an Account member (upon Account creation for instance)
public fun send_invite<Config, Outcome, CW: drop>(
    account: &Account<Config, Outcome>, 
    recipient: address, 
    config_witness: CW,
    ctx: &mut TxContext,
) {
    account.assert_is_config_module(config_witness);
    let account_type = type_name::get<Config>().into_string().to_string();

    transfer::transfer(Invite { 
        id: object::new(ctx), 
        account_addr: account.addr(),
        account_type,
    }, recipient);
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