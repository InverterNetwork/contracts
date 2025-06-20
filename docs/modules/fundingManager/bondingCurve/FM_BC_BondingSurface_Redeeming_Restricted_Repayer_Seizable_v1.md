# Basic Functionality of the Quadratic Price Formula Redeeming Restricted Repayer Seizable Contract

This is a basic description of the quadratic price formula redeeming restricted repayer seizable contract functionalities and the parameters that are needed to set up the contract.

## Basic Functionality of the underlying Quadratic Price Formula Redeeming Contract

Because the Quadratic Price Formula Redeeming Restricted Repayer Seizable Contract is based on the Quadratic Price Formula Redeeming Contract, it inherits the functionalities of this contract. These functionalities are described in the linked document:
[FM_BC_QuadraticPrice_Redeeming_v2.md](FM_BC_QuadraticPrice_Redeeming_v2.md)

## Added Functionalities

This contract adds further functionalities to the underlying Quadratic Price Formula Redeeming Contract:

### Added Roles

This contract adds the following roles to specify the access to the functions of the contract more granularly:

- Risk Manager
- Cover Manager
- Curve Interaction Role

All of these roles can be assigned by the Workflow Admin to a specific address or contract address.

### Set Curve Parameters

With the setCapitalRequired() and setBasePriceMultiplier() functions, the parameters of the quadratic price Formula can be changed even after the contract has been deployed. This was not possible before.

### Seize

This function allows the Cover Manager to seize collateral tokens from the quadratic price formula contract. This is restricted to a percentage of the collateral tokens that are held in the contract. This percentage can be set via the adjustSeize function that is also restricted to the Cover Manager.

### Repayment

This functionality allows a predetermined address, a so called LiquidityVaultController, to transfer collateral tokens out of the quadratic price formula contract. The LiquidityVaultController works similar to a role in this instance, as it is a address that can be assigned by the Cover Manager via the setLiquidityVaultController function. The transferal of collateral is done by calling the transferRepayment function.

### Access Restricted Buy and Sell Functions

This contract allows for a more granular access to the buy and sell functionalities. In addition to the full restriction to both functions, the covermanager can also restrict the access to the buy and sell functions to the Curve Interaction Role via the restrictBuyAndSell and unrestrictBuyAndSell functions. This restriction is an additional layer on top of the access restriction of the underlying Quadratic Price Formula Redeeming Contract.

### TokenVault fee collection

Instead of storing the fees in the contract directly, like in the underlying Quadratic Price Formula Redeeming Contract, the fees are sent to a TokenVault address after collection. The TokenVault itself can be any address, but we recommend to use the TokenVault_v1 contract that can be deployed alongside the quadratic price formula contract during workflow deployment. This address has to be set via the setTokenVault function by the workflow admin after the deployment of the quadratic price formula contract.

## Setup

For the Quadratic Price Formula Redeeming Restricted Repayer Seizable Contract setup the following contracts and parameters are needed:

### Quadratic Price Formula Redeeming Contract

As the Quadratic Price Formula Redeeming Restricted Repayer Seizable Contract is based on the Quadratic Price Formula Redeeming Contract, this contract needs the same basic setup as the Quadratic Price Formula Redeeming Contract:

See [FM_BC_QuadraticPrice_Redeeming_v2.md](FM_BC_QuadraticPrice_Redeeming_v2.md)

The Setup differs in the following steps.

### Before Workflow Deployment

These steps are needed before the quadratic price formula workflow is deployed.

@todo Doesnt need anything here, but I wanted to leave it in as a reference.

### During Workflow Deployment

These steps are needed during the workflow deployment.

#### Deployment Parameters

These parameters mus be known in addition to the ones needed for the quadratic price formula redeeming contract setup.

- **LiquidityVaultController address**: What is the address that can use the transferRepayment function
- **buy and sell restriction value**\_ Is the buy and sell functionality restricted to the Curve User role?
- **Seize percentage**: What is the percentage of the collateral tokens that can be seized by the Cover Manager?

#### Creation of the Tokenvault (optinal)

This is an optional step, as the tokenvault can be set as any address. However, we recommend to use the TokenVault_v1 contract that can be deployed alongside the quadratic price formula contract during workflow deployment.
@todo reference?

### After Workflow Deployment

These steps are needed after the quadratic price formula workflow is deployed.

#### TokenVault

After the deployment of the quadratic price formula contract, the TokenVault address needs to be set. This can be done by the wokflow admin by calling the setTokenVault function.

#### Added Roles

After the deployment of the quadratic price formula contract, the following roles need to be assigned to specific addresses, to access all the functionalities of the contract. This can be done by the workflow admin by calling the grantModuleRole or grantModuleRoleBatched functions in the quadratic price formula contract. Both functions require the bytecode of the role as well as the address to which the role should be assigned.

The roles that need to be assigned are:

- **Risk Manager** which bytecode can be looked up via the RISK_MANAGER_ROLE() function.
- **Cover Manager** which bytecode can be looked up via the COVER_MANAGER_ROLE() function.
- **Curve User** which bytecode can be looked up via the CURVE_INTERACTION_ROLE() function.
