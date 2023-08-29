<img align="right" width="150" height="150" top="100" src="./assets/logo_circle.svg">

# Contributing to the Inverter Network Contracts

Thanks for your interest in improving the Inverter Network contracts! Your contributions play a vital role in enhancing the robustness and usability of the network. Open-source projects like ours thrive on community collaboration, and every contribution, big or small, pushes us closer to our shared vision.

## Using GitHub Issues
GitHub issues are an essential tool for collaboration and tracking in our project. If you're an external contributor and come across something that isn't working as expected or have suggestions, concerns, or any other reasons to reach out:

- **Open a New Issue**: Please create a new issue detailing the problem, enhancement, or suggestion. Be as descriptive as possible, providing steps to reproduce (if applicable), expected, and actual behavior.
- **Issue Triage by the Team**: Once an issue is opened, our team will tag and prioritize it accordingly. We use various tags to classify and manage issues effectively.
- **Good First Issues**: If you're new to the project and looking for a place to start, look for issues tagged with "good first issue". These are typically more straightforward tasks that are a great way to familiarize yourself with the codebase and contribute.
Remember, every issue opened helps improve the project, and your feedback is invaluable to us!

## Branching System

We operate using a two-branch-system:
- **main**: This is our stable branch. Releases are made from this branch.
- **dev**: Development and feature integration happens here.

## Workflow
1. Create feature branches from `dev` when working on any new feature or bug fix.
2. Once your feature is complete, create a PR to merge from your feature branch into `dev`.
3. When ready to release to `main`, the team will create a PR from `dev` to `main`.
4. External contributors are welcome to create PRs that merge into `dev`.

## Criteria for Pull Requests

### Merging into `dev`
Your PR should have:
- Full test coverage of the new feature.
- Updated deployment scripts (if necessary).
- Proper code comments.
- Ensure the GitHub Continuous Integration (CI) and Linter checks pass without errors.

### Merging into `main`
Your PR should have:
- Everything listed in the requirements for `dev` (fully tested, updated deployment scripts, code comments, etc.)
- Full documentation coverage in the wiki. Draft the documentation in the PR comments.
- Review of the requirements (according to the following section) by the developers and QA

### Requirements Verification
For feature implementations that are guided by an SRS document or a similar specification:

- The developer creating the PR must ensure the implementation adheres to the documented requirements.
- While it's ideal to verify these requirements during the review process for merging into the `dev` branch, it's mandatory for merges into the `main` branch due to our development approach.
- PRs to the `main` branch are also where external feedback is particularly valued.
- The developer creating the PR is responsible for providing clear references to the specific requirements in the SRS document. This can be done by either:
  - Pasting the relevant portions of the SRS into the PR comments.
  - Providing a direct link to the SRS document or its specific section.

This ensures that reviewers can efficiently evaluate the correctness of the implementation against the defined requirements.

## Deployment Criteria
Whenever these branches are updated, it triggers a redeployment on the corresponding blockchain network. Currently, these redeployments are done manually. The latest deployment details will be in the <a href="./README.md" target="_blank">README.md</a> file.

**Minor Changes**: Only the affected contract will be redeployed if the update is a minor change or a bug fix.
**Fundamental Changes**: If there's a significant feature addition or a substantial change, a full redeployment will be executed to ensure all components are in sync.
This deployment strategy ensures that our contracts are always up-to-date and tested in real-world scenarios.

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

This hook will update gas and code coverage metrics, format the code, run the tests, and verify that all scripts work as expected.

_DISCLAIMER: Originally adapted from the [ethers-rs contributing guide](https://github.com/gakonst/ethers-rs/blob/master/CONTRIBUTING.md)._
