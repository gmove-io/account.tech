# Kraken - Account Abstraction on Sui

![kraken_logo](https://github.com/gmove-io/kraken/assets/92447129/258838ae-bab1-4f80-975a-a1d36c553280)

## Overview

The Kraken project aims to provide a versatile ecosystem of apps with native and smart-contract based multisig mechanisms at its center, tailored for both teams and individuals on the Sui blockchain.

This package implements a multisig-like smart contract based system on the Sui blockchain. A multisig is a mechanism that requires multiple parties to agree on actions before they can be executed. This adds an additional layer of security and is recommended for managing treasuries and smart contracts.

## Goals

The Kraken's Smart Multisig is built from the ground up for teams and developers. The product provides all functionalities needed to manage multiple projects and funds.
A fully featured Account Abstraction solution with social recovery for individuals will be built on top using zkLogin, native multisig, transfer to object and any other features replicating the behavior of a classic account. We call it the Kraken's Smart Account.

The primary goal is to enable a broad spectrum of on-chain interactions, surpassing the limitations of existing solutions. It will also be easily integrable with 3rd party packages enabling the creation and management of custom proposals. This project will eventually include different front-ends as well as an SDK and a CLI to streamline operations.

## Features

- **Configuration**: Set up the Multisig's name, members, threshold, proposal expiration and scheduled execution. Send on-chain invites to newly added members.
- **Asset Management**: Manage and send your coins or any other object types just like with classic accounts. Transfer and de/list NFTs from/to the Multisig's Kiosk. Easily hide spam objects owned by a Multisig.
- **Payment Streams**: Pay people by creating streams that will send an amount of coin to an address at regular frequency.
- **Access Control**: Define any actions in your own module and securely manage their access via the Multisig. Check out the [examples](TODO:).
- **Package Upgrades**: Lock your UpgradeCaps in your Multisig to enforce agreement on the code to be published. Optionally follow a time-lock built-in policy to protect your users. Helpers will be provided to display upcoming upgrades on your dapp
- **Interact with dApps**: Easily interact with dApps on Sui that are integrated to the Multisig. Stake, Swap, Lend your assets, and more. (TODO)

## Modules

The project consists of several modules, each handling different aspects of the multisig functionality:

1. **Multisig**: Core module managing the multisig and proposals. It handles the creation of multisig wallets, adding and removing members, and managing proposals for executing actions.

2. **Account**: Handles the creation of a non-transferable account for each user to track their Multisigs. Allows members to send on-chain invites to new members.

3. **Config**: Enables the modification of multisig settings such as member addition or removal, threshold changes and name update.

4. **Owned**: Manages access to objects owned by the multisig, allowing them to be withdrawn or borrowed through proposals.

5. **Coin Operations**: Handles the merging and splitting of coins in the multisig. Can be used to prepare a Proposal with coins with the exact amount needed.

6. **Transfers**: Allows the transfer of assets owned in the multisig treasury. Objects can also be delivered, meaning the recipient has to claim the objects otherwise the Multisig can retrieve them.

7. **Payments**: Handles the creation of a payment stream for a coin. The payment is done by sending an amount of the coin to the recipient at a regular interval until the balance is empty. It can be cancelled by the multisig member.

8. **Kiosk**: Handles the creation of a Kiosk, which is a container for NFTs owned by the Multisig. The Kiosk module can be used to move NFTs between the Multisig and other Kiosks. NFTs can listed and delisted from the Kiosk and profits can be withdrawn.

9. **Move Call**: Facilitates the enforcement of calling the appropriate functions. The action can also include to borrow or withdraw objects (such as a Cap).

10. **Upgrade Policies**: Secure UpgradeCaps by locking them into the Multisig and defining an optional time-lock policy.

## Flow
The multisig module define a common interface for all actions which are attached to a Proposal type stored in a VecMap. The keys are supposed to be human-readable identifiers to display on the frontends.

Modules may define none or multiple actions, which are structs with store ability meant to be attached to a Proposal. For each of these actions, a `propose_` function using `multisig::create_proposal` is provided to add a Proposal for this action to the Multisig.

When a Proposal is added to the Multisig, at least `threshold` members have to `multisig::approve_proposal` before it can be executed. Once a Proposal is executed, the action is returned to be used in the module defining it. Optionally, members can `multisig::remove_approval`.

Actions are executed by an "action-named" function, sometimes several times and must be destroy via a `complete_` function if it hasn't been consumed during execution.

## Contributing

Contributions are welcome! If you have suggestions for improvements or new features, please open an issue or submit a pull request. Please feel free to reach out [on Twitter](https://twitter.com/BL0CKRUNNER) if you have any questions.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
