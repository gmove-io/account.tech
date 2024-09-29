# Kraken - Account Abstraction on Sui

![kraken_banner](./assets/kraken_banner.png)

## Project Overview

### Abstract

This project aims to provide the account abstraction layer of Sui, enabling asset and protocol managers to interact with dApps, execute payments, administer packages, and more with enhanced security.

Our vision is to create a robust infrastructure that not only supports a wide array of applications but also enables the development of our own suite of secure and friendly platforms.

### Goals

Kraken's (Multisig) Accounts are built from the ground up for teams and developers. The protocol provides all functionalities needed to manage on-chain projects, assets and funds. Parameters are fully customizable with members, weights, roles and thresholds management.

The primary goal is to enable a broad spectrum of on-chain interactions, surpassing the limitations of existing solutions (poor user and developer experience, unflexible parameters, limited in features, closed and inextensible, etc). 

Businesses should be able to handle all their processes on-chain with ease and in all safety. That is why Kraken Accounts will support all existing Sui objects.

The protocol is also easily integrable with 3rd party packages enabling the creation and management of custom actions and proposals. This project will eventually include different front-ends as well as a [Typescript SDK](https://github.com/gmove-io/kraken-sdk) and a CLI to streamline operations.

### Features

- **On chain Registration**: Create a User profile object to track your multisigs on-chain. Add a username and profile picture to be displayed on the front-ends. Send and receive invites to join multisigs on-chain. 
- **Configuration**: Set up the Multisig's name, roles and thresholds, and members with their weight and roles. For each proposal, define an expiration epoch and schedule an execution time. Explicitly migrate to new versions of the Kraken Extensions to benefit from new features built by the Good Move team and the community.
- **Asset Management**: Manage and send coins or any other object type owned by an Account in a natural way. Containerize and spend coins with Treasuries, and NFTs with Kiosks. Transfer and de/list NFTs from/to the Account's Kiosks. Easily hide spam objects owned by a Multisig.
- **Payment Streams**: Pay people by creating streams that will send an amount of coin to an address at regular frequency. Cancel the payment at any time. Make a delivery by enabling a recipient to claim a payment from an escrow. Retrieve the payment if you made a mistake and if it hasn't been claimed.
- **Currency Management**: Lock a TreasuryCap and enable/disable the minting and/or burning of Coins. Update its CoinMetadata. Send and airdrop minted coins.
- **Access Control**: Define any action in your own module and securely manage its execution via the Account. Check out the [examples](./package/examples/sources/access_control.move).
- **Package Upgrades**: Lock your UpgradeCaps in your Account to enforce agreement on the code to be published. Any rule(s) can be defined for an UpgradeLock. An optional time-lock built-in policy is provided by default to protect your users. The SDK will facilite the display of upcoming upgrades on your dapp.
- **Validator Monitoring**: Safely manage your validator. (TODO)
- **Interact with dApps**: Easily interact with dApps on Sui that are integrated to the Multisig. Stake, Swap, Lend your assets, and more. (TODO)

## Architecture

![account_architecture_graph](./assets/account_architecture_graph.png)

### Core Packages 

The Move code has been designed to be highly modular. There are 4 packages but there could be many more, including from external contributors. 

The first one is `AccountProtocol` managing the multisig `Account` object and the proposal process. The `Account` object encapsulates 4 custom types managing its dependencies, members, thresholds & roles, and proposals.

These fields can be accessed mutably from the core packages only. Core Packages are `AccountProtocol` and `AccountActions`. The latter defines proposals to modify `Account` fields.

### Extensions

Since `AccountProtocol` is a dependency of `AccountActions` but we also want to ensure that `Account` fields defined in `AccountProtocol` can be mutated only in `AccountActions`, it creates a dependency cycle. To solve this issue we needed a third package.

This is where `AccountExtensions` comes into play. This package provides an `Extensions` shared object managing all the packages that `Account` objects can use, with their versioning.  In there, `AccountProtocol` and `AccountActions` are defined as core packages and granted special permissions. With this pattern, we replicate the behavior of `public(package)` but across multiple packages.

The `Extensions` object will also be used to dynamically add new dependencies without ever needing to upgrade the core packages. Accounts can opt-in to use any version of any package allowed in `Extensions`. The imported extensions are tracked in the Account's `Deps` type.

By enforcing each `Account` to explicitly migrate to newly upgraded packages and allowed extensions, the system is made trustless.

### Module Structure

Each module may define none or multiple actions and/or proposals. Each Proposal has an associated `NameProposal` witness type used for many checks (see below). Public functions are divided in three parts: 

- member functions can be executed without proposals by all members of the Account.
- proposal functions are used to create proposals and execute actions upon approval.
- action functions are the library functions and can be used to compose proposals.

### Authentification

Each proposal stores a special Auth type constructed from an associated witness (struct with drop and copy abilities) and an optional name. This Auth is used to enforce the correct and complete execution of the proposal, verify the `Account` dependency (allowed package and version), facilitate parsing on front-ends and define roles.  

These roles can be added to members who can then bypass the global threshold if the role threshold is reached. Members have weights enabling super admins and more.

### Object handling

An `Account` can possess and interact with objects in two different ways.

Using transfer to object (tto), we replicated the behavior of classic Sui accounts, enabling Accounts to receive, own and interact any kind of object.

Then we separate managed assets, which are special and standardized objects from the Sui Framework and more. Those are attached as dynamic fields to `Account` objects allowing us to abstract, secure and provide granular control to many processes such as upgrading packages, managing a Coin, handling access control (instead of AdminCaps), etc.

This design allows us to manage the packages with a special `Account` object which is instatiated upon deployment and uses this access control mechanism.

## Usage

![proposal_flow_graph](./assets/proposal_flow_graph.png)

### Proposal Flow

1. Proposals are created via `propose_` functions within modules, by stacking one or more predefined actions.
2. Members of the Account can approve the proposal by calling `account::approve_proposal`. Optionally, members can `account::remove_approval`. This increases the `global_weight` field of the Proposal and the `role_weight` field if the member posseses the role.
3. Once the threshold is reached, the proposal is executed by calling the `execute_proposal` function, returning an `Executable` hot potato wrapping the action bag and `Auth`.
4. Actions are executed by passing the `Executable hot potato` to the `execute_` function of the module.
5. Finally, all actions and the `Executable` hot potato must be destroyed via `complete_` functions within the same module as the proposal was created (if it hasn't been consumed during execution).

### Actions

Actions are struct with `store` only ability. These actions are meant to be stacked in proposals and executed sequentially. They all have a similar interface to handle their lifecycle, which is used to compose proposals. 

Actions are created by passing a `Proposal` and are destroyed from within the `Executable`. This way we ensure they can't be dropped or stored and must be executed as expected.

The `account` module defines a common interface for adding actions to a Proposal which is stored in the `Account` VecMap. The keys are supposed to be unique human-readable identifiers to display on the frontends.

### Integration

Anyone can define custom actions and proposals in their own package or separate library! Please refer to the [examples](./examples/) for some use cases.

Create a new proposal by defining a `propose_actions()` function that will instantiate a Proposal containing the actions of your choice. Then write a `execute_actions()` function that will execute the actions according to their logic. Add a `complete_actions()` function to destroy the actions and the `Executable` hot potato if it can't be done during the precedent step (if you need to loop over `execute_actions()` for instance).

Create new actions by defining structs with store only ability carrying the data you need. These actions are instantiated via `new_action()` functions that takes a mutable reference to the proposal. Then they are executed by calling `action()` with the `Executable` hot potato as argument. Finally the action execution should be validated and destroyed by calling `destroy_action()`.

### Modules

The project is splitted in multiple packages to improve the security. Indeed, the core packages have no external dependency so they are less vulnerable and don't necessitate regular upgrades because of third party packages. 

Furthermore, the `AccountProtocol` shouldn't need to be upgraded since its functionalities will not change except with a major evolution of the protocol. `AccountActions` will be upgraded to add new features and `AccountExtensions` could be made immutable.

`AccountActions` consists of several modules, with built-in actions and proposals, each handling different aspects of the multisig functionality:

1. **Config**: Enables the modification of the Account settings such as member addition or removal, threshold changes, roles addition, and name update, as well as the Account dependency management.

2. **Currency**: Allows creators to lock a TreasuryCap and limit its permissions. Members can mint coins and use them in transfers or payments.

3. **Kiosk**: Handles the creation of a Kiosk, which is a container for NFTs owned by the Account. The Kiosk module can be used to move NFTs between the Account and other Kiosks. NFTs can listed and delisted from the Kiosk and profits can be withdrawn. Each Kiosk has a matching role that can be assign to members.

4. **Owned**: Manages access to objects owned by the multisig, allowing them to be withdrawn or borrowed through proposals. Withdrawn objects can be used in transfers and payments.

5. **Payments**: Defines APIs for creating payments streams and escrows for a Coin that are used in other modules like `owned`, `currency` and `treasury`. The payment is done by sending an amount of the coin to the recipient at a regular interval until the balance is empty. Alternatively, the Coin could be manually claimed. Paid or escrowed coins can be cancelled and retrieved by members as long as they have not been sent or claimed.

6. **Transfers**: Defines APIs for transferring objects from an Account. These objects are retrieved by withdrawing them from owned, spending them from treasury, minting them from currency, or anything else you want to define.

7. **Treasury**: Allows members to open containers for Coins and assign members to them via roles. Coins held there can be transferred, paid and more using the Spend action.

8. **Upgrade Policies**: Secure UpgradeCaps by locking them into the Multisig and define custom rules for the UpgradeLock. It provides a default TimeLock rule. Members can propose to upgrade and restrict their packages.

## Additional Information

### Considerations

Currently, only the transaction digest is accessible within Move. Since it includes the gas object, we can't use it to execute arbitrary move call via the smart contract multisig.

[A SIP](https://github.com/sui-foundation/sips/pull/37) has been submitted by our team to propose to expose more data from the transaction context on chain.    

### Contributing

Contributions are welcome! If you have suggestions for improvements or new features, please open an issue or submit a pull request. Please feel free to reach out [on Twitter](https://twitter.com/BL0CKRUNNER) if you have any question.

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


![kraken_logo](./assets/kraken_logo.jpg)
