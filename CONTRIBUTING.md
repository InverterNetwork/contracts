<img align="right" width="150" height="150" top="100" src="./assets/logo_circle.svg">

# Contribution Guidelines

Thanks for your interest in improving the Inverter Network contracts! Your contributions play a vital role in enhancing the robustness and usability of the protocol. Open-source projects like ours thrive on community collaboration, and every contribution, big or small, pushes us closer to our shared vision.

## Using GitHub Issues
GitHub issues are an essential tool for collaboration and tracking in our project. If you're an external contributor and come across something that isn't working as expected or have suggestions, concerns, or any other reasons to reach out:

- **Open a New Issue**: Please create a new issue detailing the problem, enhancement, or suggestion. Be as descriptive as possible, providing steps to reproduce (if applicable), expected, and actual behavior.
- **Issue Triage by the Team**: Once an issue is opened, our team will tag and prioritize it accordingly. We use various tags to classify and manage issues effectively.
- **Good First Issues**: If you're new to the project and looking for a place to start, look for issues tagged with "good first issue". These are typically more straightforward tasks that are a great way to familiarize yourself with the codebase and contribute.
Remember, every issue opened helps improve the project, and your feedback is invaluable to us!

## Branching System

We operate using a two-branch-system:
- **main**: This is our stable branch. The contents of this branch are deployed to our live networks.
- **dev**: Development and feature integration happens here. The contents of this branch are deployed on our testnet.

## Workflow
1. Create feature branches from `dev` when working on any new feature or bug fix.
   - External contributors may need to fork the repository first and work from there.
2. Once your feature is complete, create a PR to merge from your feature branch into `dev`.
   - We require multiple reviews from our side as a prerequisite to merging into `dev`.
3. When ready to release to `main`, the team will create a PR from `dev` to `main`.
   - Our process for merging from `dev` to `main` requires multiple internal as well as external reviews (via an audit).

## Criteria for Pull Requests

### General Remarks
When working on the Inverter Network contracts, please keep in mind the following principles:
- **Keep It Simple, Stupid (KISS)**: The KISS principle states that simplicity should be a key goal in design and unnecessary complexity should be avoided. Ensure that your code is easy to understand, concise, and without redundant or unnecessary parts. Simple code is easier to review, debug, and maintain in the long run.
- **Modularity**: Our contracts have been developed with a modular approach. This modular structure allows us to maintain clarity in design, fosters code reuse, and simplifies testing. When adding to or modifying the codebase, ensure that you respect this modularity. Components should have a single responsibility and communicate through well-defined interfaces. If a function or a contract is becoming too complex or trying to handle too many things, consider splitting it into smaller, more focused components.

By following these principles, you ensure that the Inverter Network contracts remain robust, maintainable, and easy to comprehend for all contributors, both current and future. 

### Merging into `dev`
Your PR should have:
- Full test coverage of the new feature, following the style of the existing tests.
  - This including adapting the E2E tests accordingly if the feature requires it.
- Updated deployment scripts (if necessary).
- Proper code comments.
- Ensure the GitHub Continuous Integration (CI) and Linter checks pass without errors.
  - A good way to locally verify this, is via running the `make pre-commit` command (more details in our <a href="./README.md" target="_blank">README.md</a>).

### Merging into `main`
Your PR should have:
- Everything listed in the requirements for `dev` (fully tested, updated deployment scripts, code comments, etc.)
- Full documentation coverage.
- Review of the requirements (according to the following section) by the developers and QA.

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
Whenever these branches are updated, it triggers a redeployment on the corresponding blockchain network. Currently, these redeployments are done manually. The latest deployment details will be in the <a href="https://github.com/InverterNetwork/deployments" target="_blank">deployments repository</a>.

* **Minor Changes**: Only the affected contract will be redeployed if the update is a minor change or a bug fix.
* **Fundamental Changes**: If there's a significant feature addition or a substantial change, a full redeployment will be executed to ensure all components are in sync.

This deployment strategy ensures that our contracts are always up-to-date and tested in real-world scenarios.

-----
_Disclaimer: Originally adapted from the [ethers-rs contributing guide](https://github.com/gakonst/ethers-rs/blob/master/CONTRIBUTING.md)._

