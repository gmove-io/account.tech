# Kraken - a Sui Multisig

## Overview

This project implements a multisig-like smart contract based system on the Sui blockchain. A multisig is a mechanism that requires multiple parties to agree on actions before they can be executed. This adds an additional layer of security and is useful for managing shared funds and packages.

A fully featured Account Abstraction solution for individuals will be built on top using zkLogin, transfer to object and any other features replicating the behavior of a classic account. The product for teams will be expanded with every feature needed to manage multiple projects and funds.

## Goals

This package aims to provide a versatile implementation of a multisig mechanism tailored for both teams and individuals on the Sui blockchain. The primary goal is to enable a broad spectrum of on-chain interactions, surpassing the limitations of existing solutions. It is also easily integrable with packages to create and execute custom proposals. 

This project will eventually include both an SDK and a CLI to streamline operations. Frontends such as a webapp, extension and mobile app should eventually be developped.

## Modules

The project consists of several modules, each handling different aspects of the multisig functionality:

1. **Multisig**: Core module managing the multisig and proposals. It handles the creation of multisig wallets, adding and removing members, and managing proposals for executing actions.

2. **Config**: Enables the modification of multisig settings such as member addition or removal, threshold changes and name update.

3. **Owned**: Manages access to objects owned by the multisig, allowing them to be withdrawn or borrowed through proposals.

5. **Transfer**: Allows the transfer of assets owned in the multisig treasury.

6. **Coin Operations**: Handles the merging and splitting of coins in the multisig. Can be used to prepare a Proposal with coins with the exact amount needed.

7. **Move Call**: Facilitates the enforcement of calling the appropriate functions. The action can also include to borrow or withdraw objects (such as a Cap).


## Features

- **Configuration**: Set up members, threshold, proposal expiration and scheduled execution.
- **Access Control**: Securely manage access to functions in your package via a Cap owned by the Multisig.
- **Asset Management**: Manage and send your coins or any other object types just like with classic accounts. Easily hide spam objects owned by a Multisig.
- **Custom Proposals**: Define any actions in your module and easily manage them via the Multisig. Check out the [examples](TODO:).
- **Package Upgrades**: Lock your UpgradeCaps in your Multisig to enforce agreement on the code to be published. Optionally follow a time-lock built-in policy to protect your users. Helpers will be provided to display upcoming upgrades on your dapp
- **Interact with dApps**: Easily interact with dApps on Sui that are integrated to the Multisig. Stake, Swap, Lend your assets, and more. (TODO)

## Contributing

Contributions are welcome! If you have suggestions for improvements or new features, please open an issue or submit a pull request. Please feel free to reach out [on Twitter](https://twitter.com/BL0CKRUNNER) if you have any questions.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
