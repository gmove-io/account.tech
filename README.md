# Sui Multisig

## Overview

This project implements a multisig-like system on the Sui blockchain. A multisig is a mechanism that requires multiple parties to agree on transactions before they can be executed. This adds an additional layer of security and is useful for managing shared funds.

## Goals

This package aims to provide a versatile implementation of a multisig mechanism tailored for both teams and individuals on the Sui blockchain. The primary goal is to enable a broad spectrum of on-chain interactions, surpassing the limitations of existing solutions. This project will eventually include both an SDK and a CLI to streamline operations. For those interested in developing a frontend, please feel free to reach out via DM on Twitter: [BL0CKRUNNER](https://twitter.com/BL0CKRUNNER).

## Modules

The project consists of several modules, each handling different aspects of the multisig functionality:

1. **Multisig**: Core module managing the multisig and proposals. It handles the creation of multisig wallets, adding and removing members, and managing proposals for executing actions.

2. **Manage**: Allows for the management of multisig settings such as member addition or removal and threshold changes.

3. **Access Owned**: Manages access to objects owned by the multisig, allowing them to be withdrawn or borrowed through proposals.

4. **Treasury**: Leverages the `access_owned` API to manage deposits and withdrawals of assets from the multisig treasury.

5. **Move Call**: Facilitates the enforcement of calling the appropriate functions to borrow or return the requested objects (such as a Cap). Taken objects can be used in the following commands of the PTB.


## Features

- **Access Control**: Securely manage access to functions in a package via a Cap owned by the Multisig.
- **Asset Management**: Sort coins and any other object types. Deposit non-spam assets only and safely transfer or withdraw objects held in the treasury.

## Contributing

Contributions are welcome! If you have suggestions for improvements or new features, please open an issue or submit a pull request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
