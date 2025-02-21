<a href="https://inverter.network" target="_blank"><img align="right" width="150" height="150" top="100" src="./assets/logo_circle.svg"></a>

# Inverter Network Smart Contracts
*Inverter is the pioneering web3 protocol for token economies, enabling conditional token issuance, dynamic utility management, and token distribution. Build, customize, and innovate with Inverter's modular logic and extensive web3 interoperability.*

## Installation

The Inverter Network smart contracts are developed using the [foundry toolchain](https://getfoundry.sh)

1. Clone the repository
2. `cd` into the repository
3. Run `make install` to install contract dependencies
4. (_Optional_) Run `source dev.env` to set up environment variables

## Usage

Common tasks are executed through a `Makefile`. The most common commands are:
* `make build` to compile the project.
* `make test` to run the test suite.
  * Note: _Some of our tests  require a working Sepolia RPC URL, as we test certain contracts via fork testing. We implemented fallbacks for these particular test cases in the code directly, so they will work even without any RPC set in the environment. In the unlikely case that the tests do not work without RPC, please set a working one via `export SEPOLIA_RPC_URL=https://rpc-url-here`._
* `make pre-commit` to ensure all of the development requirements are met, such as
  * the Foundry Formatter has been run.
  * the scripts are all working.
  * the tests all run without any issues.

Additionally, the `Makefile` supports a help command, i.e. `make help`.

```
$ make help
> build                    Build project
> clean                    Remove build artifacts
> test                     Run whole testsuite
> update                   Update dependencies
> [...]
```

## Documentation
The protocol is based on our [technical specification](https://docs.google.com/document/d/1j6WXBZzyYCOfO36ZYvKkgqrO2UAcy0kW5eJeZousn7E), which outlines its architecture and is the foundation of the implementation. Our documentation can be found [here](https://docs.inverter.network).

## Dependencies
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [OpenZeppelin Upgradeable-Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable)
- [UMAProtocol](https://github.com/UMAprotocol/protocol) (_for the [KPIRewarder Staking Module](./src/modules/logicModule/LM_PC_KPIRewarder_v2.sol)_)

## Contributing
You are considering to contribute to our protocol? Awesome - please refer to our [Contribution Guidelines](./CONTRIBUTING.md) to find our about the processes we established to ensure highest quality within our codebase.

## Security
Our [Security Policy](./SECURITY.md) provides details about our Security Guidelines, audits, and more. If you have discovered a potential security vulnerability within the Inverter Protocol, please report it to us by emailing [security@inverter.network](mailto:security@inverter.network).

-----
_Disclaimer: This is experimental software and is provided on an "as is" and "as available" basis. We do not give any warranties and will not be liable for any loss incurred through any use of this codebase._
