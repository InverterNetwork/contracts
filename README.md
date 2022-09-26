<a href="https://byterocket.com" target="_blank"><img align="right" width="150" height="150" top="100" src="./assets/logo.png"></a>

# Inverter Smart Contracts

> A new funding primitive to enable multiple actors within a decentralized network to collaborate on proposals. You can find more information in the [GitBook](https://inverter-network.gitbook.io/inverter-network-docs/inverter-overview/introduction-to-inverter).

## Installation

The Proposel Inverter smart contracts are developed using the [foundry toolchain](https://getfoundry.sh).

1. Clone the repository
2. `cd` into the repository
3. Run `make install` to install contract dependencies
4. (_Optional_) Run `source dev.env` to setup environment variables

## Usage

Common tasks are executed through a `Makefile`.

The `Makefile` supports a help command, i.e. `make help`.

```
$ make help
> build                    Build project
> clean                    Remove build artifacts
> test                     Run whole testsuite
> update                   Update dependencies
> [...]
```

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [OpenZeppelin Upgradeable-Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable)

## Safety

This is experimental software and is provided on an "as is" and
"as available" basis.

We do not give any warranties and will not be liable for any loss incurred
through any use of this codebase.
