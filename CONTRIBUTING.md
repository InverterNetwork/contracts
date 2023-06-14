<img align="right" width="150" height="150" top="100" src="./assets/logo_circle.svg">

# Contributing to the Inverter Network Contracts

Thanks for your interest in improving the Inverter Network contracts!

## Resolving an Issue

Pull requests are the way concrete changes are made to the code, documentation,
and dependencies of the Inverter Network.

Even tiny pull requests, like fixing wording, are greatly appreciated.
Before making a large change, it is usually a good idea to first open an issue
describing the change to solicit feedback and guidance. This will increase the
likelihood of the PR getting merged.

Please also make sure to run our pre-commit hook before creating a PR:

```bash
make pre-commit
```

This hook will update gas and code coverage metrics, and format the code.

_DISCLAIMER: Adapted from the [ethers-rs contributing guide](https://github.com/gakonst/ethers-rs/blob/master/CONTRIBUTING.md)._
