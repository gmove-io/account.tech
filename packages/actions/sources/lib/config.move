/// This module allows to manage Account settings.
/// The actions are related to the modifications of all the fields of the Account (except Proposals).
/// All these fields are encapsulated in the `Account` struct and each managed in their own module.
/// They are only accessible mutably via [core-deps-only] functions defined in account.move which are used here only.
/// 
/// The members and thresholds modifications are grouped under a single proposal because they often go by pair.
/// The threshold modification must be executed at the end to ensure they are reachable.
/// The proposal also verifies the validity of the new values upon creation (e.g. threshold not higher than total weight).
/// 
/// Dependencies are all the packages and their versions that the account depends on (including this one).
/// The allowed dependencies are defined in the `Extensions` struct and are maintained by Kraken team.
/// Account users can choose to use any version of any package and must explicitly migrate to the new version.
/// This is closer to a trustless model where anyone with the UpgradeCap could update the dependencies maliciously.

module account_actions::config;

// === Imports ===

use std::{
    type_name::TypeName,
    string::String,
};
use account_protocol::{
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
    deps::{Self, Deps},
    metadata,
};
use account_extensions::extensions::Extensions;
use account_actions::{
    version,
    upgrade_policies,
};

// === Errors ===

#[error]
const EMetadataNotSameLength: vector<u8> = b"The keys and values are not the same length";
#[error]
const EMetadataNameMissing: vector<u8> = b"New metadata must set a name for the Account";
#[error]
const ENameCannotBeEmpty: vector<u8> = b"Name cannot be empty";
#[error]
const ENoExtensionOrUpgradeCap: vector<u8> = b"No extension or upgrade cap for this package";

// === Structs ===

/// [ACTION] struct wrapping the deps account field into an action
public struct ConfigDepsAction has store {
    deps: Deps,
}

// === Public functions ===

public fun edit_metadata<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    keys: vector<String>,
    values: vector<String>,
) {
    auth.verify(account.addr());

    assert!(keys.length() == values.length(), EMetadataNotSameLength);
    assert!(keys[0] == b"name".to_string(), EMetadataNameMissing);
    assert!(values[0] != b"".to_string(), ENameCannotBeEmpty);

    *account.metadata_mut(version::current()) = metadata::from_keys_values(keys, values);
}

// must be called in intent modules

public fun new_config_deps<Config, Outcome, W: drop>(
    intent: &mut Intent<Outcome>,
    account: &Account<Config, Outcome>,
    extensions: &Extensions,
    names: vector<String>,
    packages: vector<address>,
    mut versions: vector<u64>,
    witness: W,
) {    
    let mut deps = deps::new(extensions);

    names.zip_do!(packages, |name, package| {
        let version = versions.remove(0);

        if (extensions.is_extension(name, package, version)) {
            deps.add(extensions, name, package, version);
        } else if (upgrade_policies::is_package_managed(account, package)) {
            let cap = upgrade_policies::borrow_cap(account, package);
            deps.add_with_upgrade_cap(cap, name, package, version);
        } else abort ENoExtensionOrUpgradeCap;
    });

    intent.add_action(ConfigDepsAction { deps }, witness);
}

public fun do_config_deps<Config, Outcome, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W,
) {
    let action: &ConfigDepsAction = account.process_action(executable, version, witness);    
    *account.deps_mut(version) = action.deps;
}

public fun delete_config_deps(expired: &mut Expired) {
    let ConfigDepsAction { .. } = expired.remove_action();
}
