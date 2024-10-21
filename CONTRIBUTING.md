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

## Git Fork Workflow

### Prerequisites

Before getting started, ensure you have the following:

- A [GitHub](https://github.com/) account.
- [Git](https://git-scm.com/) installed on your local machine.

---

### Step 1: Fork the Repository

Forking the repository creates a personal copy under your GitHub account, where you can freely work without affecting the original repository.

1. Go to the [Inverter Network Contracts repository](https://github.com/InverterNetwork/contracts).
2. Click on the **Fork** button at the top-right corner of the page.
3. This will create a copy of the repository under your own GitHub account.

---

### Step 2: Clone Your Fork Locally

After forking the repository, you’ll need to clone your copy to your local machine to start working on it.

1. Open your terminal and clone the forked repository. Replace `YOURUSERNAME` with your GitHub username:

   ```bash
   git clone git@github.com:YOURUSERNAME/contracts.git
   ```

2. Navigate to the cloned repository:

   ```bash
   cd contracts
   ```

3. Set up your remotes to track the original repository:

   ```bash
   git remote add upstream https://github.com/InverterNetwork/contracts.git
   ```

4. Verify the remotes are set up correctly:

   ```bash
   git remote -v
   ```

   You should see the following output:

   ```bash
   origin    git@github.com:YOURUSERNAME/contracts.git (fetch)
   origin    git@github.com:YOURUSERNAME/contracts.git (push)
   upstream  https://github.com/InverterNetwork/contracts.git (fetch)
   upstream  https://github.com/InverterNetwork/contracts.git (push)
   ```

---

### Step 3: Create a Feature Branch

The `dev` branch is the most up-to-date development branch where all feature branches should be created from.

1. Ensure you are on the `dev` branch

```bash
git checkout dev
```

2. Pull latest changes from upstream `dev` branch

```bash
git pull upstream dev
```

3. Create a new branch for your feature
   to create a new branch, replace `feature-branch-name` with your branch name (use a descriptive name or issue number):

```bash
git checkout -b feature-branch-name
```

---

### Step 4: Make your Changes

Now that you’re on your feature branch, you can make changes to the code. After making your changes, stage and commit them as you normally would. Example CLI commands to all changes made:

```bash
git add .
git commit -m "Your commit message describing the changes"
```

---

### Step 5: Push Your Feature Branch to Your Fork

Once you’ve made your changes and committed them, push the feature branch to your fork on GitHub.

```bash
git push origin feature-branch-name
```

---

### Step 6: Create a Pull Request

After pushing your changes to your fork, you can create a pull request (PR) to merge your changes into the dev branch of the Inverter Network Contracts repository.

1. Go to your fork on GitHub (https://github.com/YOURUSERNAME/contracts).
2. Click on the Compare & pull request button next to the branch you just pushed.
3. Ensure the base repository is InverterNetwork/contracts and the base branch is `dev`.
4. Choose the _community_contribution_pr_request_template.md_ file as the template.
5. Add a title and description for your PR, explaining what changes you’ve made.
6. Submit the pull request.
7. Once the PR is created, the maintainers will review your code and either approve it or suggest changes.

### Keep Your Fork Up to Date

To keep your fork in sync with the `upstream` repository, periodically fetch and merge changes from upstream into your `dev` branch.

1. Fetch the latest changes from the upstream repository:

```bash
git fetch upstream
```

2. Merge the upstream dev branch into your local dev branch:

```bash
git checkout dev
git pull upstream dev
```

3. Push any updates to your fork:

```bash
git push origin dev
```

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

- **Minor Changes**: Only the affected contract will be redeployed if the update is a minor change or a bug fix.
- **Fundamental Changes**: If there's a significant feature addition or a substantial change, a full redeployment will be executed to ensure all components are in sync.

This deployment strategy ensures that our contracts are always up-to-date and tested in real-world scenarios.

---

_Disclaimer: Originally adapted from the [ethers-rs contributing guide](https://github.com/gakonst/ethers-rs/blob/master/CONTRIBUTING.md)._
