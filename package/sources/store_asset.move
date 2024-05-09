/// This module leverages the access_owned api and allows to deposit and withdraw assets from a Multisig.
/// It uses Dynamic Fields to store and sort assets initially owned by the Multisig.
/// The assets are stored in the Multisig's as Balances (for Coin) or ObjectTables (for other Objects).
/// These assets can be withdrawn (and returned in PTB) or transferred to another address.

module sui_multisig::store_asset {
    use std::debug::print;
    use std::string::{Self, String};
    use std::type_name;
    use sui::transfer::Receiving;
    use sui::dynamic_field as df;
    use sui_multisig::access_owned::{Self, Access};
    use sui_multisig::multisig::Multisig;

    // === Errors ===

    const EDifferentLength: u64 = 1;
    const EWithdrawAllAssetsBefore: u64 = 2;
    const EVaultAlreadyExists: u64 = 3;
    const EDepositAllAssetsBefore: u64 = 4;

    // action to be held in a Proposal
    public struct Deposit has store {
        // sub action - owned objects to access
        request_access: Access,
        // names for deposited assets
        names: vector<String>,
        // descriptions for deposited assets
        descriptions: vector<String>,
    }

    // action to be held in a Proposal
    public struct Withdraw has store {
        // assets to withdraw
        assets: vector<Stored>,
    }

    // struct representing an asset to withdraw from the treasury
    public struct Stored has store {
        // TypeName of the object in String
        asset_type: String,
        // amount of the coin to withdraw, can be anything if not Coin
        amount: u64,
        // key of the object to withdraw, can be anything if Coin
        key: String,
    }

    // generic struct used to wrap assets with additional metadata for frontends
    public struct Vault<C: store> has store {
        // what is this asset. e.g. staking upgrade cap
        name: String,
        // what is it used for. e.g. upgrade staking with timelock
        description: String,
        // a container for the asset (Balance for coins, Tables for NFTs, Option for cap)
        container: C,
    }

    // === Multisig functions ===

    // step 1: propose to retrieve owned objects and store them in the multisig via dof
    public fun propose_deposit(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        object_ids: vector<ID>,
        object_names: vector<String>,
        object_descriptions: vector<String>,
        ctx: &mut TxContext
    ) {
        assert!(
            object_ids.length() == object_names.length() &&
            object_ids.length() == object_descriptions.length(),
            EDifferentLength
        );
        // create a new access with the objects to withdraw (none to borrow)
        let request_access = access_owned::new_access(vector[], object_ids);
        let action = Deposit { 
            request_access, 
            names: object_names, 
            descriptions: object_descriptions 
        };
        multisig.create_proposal(
            action,
            name,
            expiration,
            description,
            ctx
        );
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: in the PTB loop over deposit functions in the different assets module according to asset PREFIX

    // step 5: destroy the action
    public fun complete_deposit(action: Deposit) {
        let Deposit { request_access, names, descriptions } = action;
        request_access.complete();
        assert!(names.is_empty() && descriptions.is_empty(), EDepositAllAssetsBefore);
    }

    // step 1: propose to withdraw objects and coins from the multisig
    public fun propose_withdraw(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        asset_types: vector<String>, // TypeName of the object
        amounts: vector<u64>, // amount if fungible
        keys: vector<String>, // key if non-fungible (to find in the Table)
        ctx: &mut TxContext
    ) {
        let action = new_withdraw(asset_types, amounts, keys);
        multisig.create_proposal(
            action,
            name,
            expiration,
            description,
            ctx
        );
    }
    
    // step 5: destroy the action if vector of Stored has been emptied
    public fun complete_withdraw(action: Withdraw) {
        let Withdraw { assets } = action;
        assert!(assets.is_empty(), EWithdrawAllAssetsBefore);
        assets.destroy_empty();
    }

    // === Package functions ===

    public(package) fun new_withdraw(
        mut asset_types: vector<String>, // TypeName of the object
        mut amounts: vector<u64>, // amount if fungible
        mut keys: vector<String>, // key if non-fungible (to find in the Table)
    ): Withdraw {
        assert!(
            asset_types.length() == amounts.length() &&
            asset_types.length() == keys.length(),
            EDifferentLength
        );

        let mut assets = vector[];
        while (!asset_types.is_empty()) {
            let asset_type = asset_types.pop_back();
            let amount = amounts.pop_back();
            let key = keys.pop_back();
            assets.push_back(Stored { asset_type, amount, key });
        };

        Withdraw { assets }
    }

    public(package) fun pop_from_deposit<A: key + store>(
        action: &mut Deposit, 
        multisig: &mut Multisig, 
        received: Receiving<A>
    ): (String, String, A) {
        let name = action.names.pop_back();
        let description = action.descriptions.pop_back();
        let owned = action.request_access.pop_owned();
        let asset = access_owned::take(multisig, owned, received);

        (name, description, asset)
    }

    public(package) fun pop_from_withdraw(
        action: &mut Withdraw,
    ): (String, u64, String) {
        let Stored { asset_type, amount, key } = action.assets.pop_back();

        (asset_type, amount, key)
    }

    public(package) fun create_vault<A, C: store>(
        multisig: &mut Multisig, 
        name: String,
        description: String,
        container: C
    ) {

        let vault = Vault<C> { name, description, container };

        assert!(!df::exists_(multisig.uid_mut(), type_name::get<A>()), EVaultAlreadyExists);
        df::add(multisig.uid_mut(), type_name::get<A>(), vault);
    }

    public(package) fun borrow_container_mut<A, C: store>(
        multisig: &mut Multisig,
    ): &mut C {
        let vault: &mut Vault<C> = df::borrow_mut(multisig.uid_mut(), type_name::get<A>());
        &mut vault.container
    }

    public(package) fun vault_key<T>(prefix: vector<u8>): String {
        let mut key = string::utf8(prefix);
        key.append(string::from_ascii(type_name::get<T>().into_string()));

        key
    }
}

