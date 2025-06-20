# Basic Functionality of QuadraticPriceFormula Contract

This is a basic description of the quadratic price formula contract functionalities and the parameters that are needed to set up the contract.

## Basic Definitions

To understand the functionalities of the quadratic price formula contract, it is important to understand the following definitions.

### Issuance Token

Issuance tokens are tokens that are distributed from the quadratic price formula contract.

### Collateral Token

Collateral tokens are tokens that are accepted by the quadratic price formula contract as a payment for issuance tokens.

### Bonding Curve

A bonding curve is a mathematical function that determines the price of issuance tokens relative to the collateral tokens.

### Quadratic Price Formula

The quadratic price formula is a special type of bonding curve. As both describe the relations between issuance tokens and collateral tokens these terms might be used interchangeably throughout this document.

### Role Management

The underlying inverter workflow structures have the ability to add and remove roles. These roles are used to manage the access to specific functions of inverter contracts. A role can be assigned to a specific address or contract address. A function that is restricted to a role can only be called by the address that has been assigned the role.
Each workflow has to determine a Workflow Admin during its deployment. This Workflow Admin has the ability to add and remove, as well as assign roles to addresses. The restriction to the Workflow admin is a standard restriction that is used throughout the inverter workflow contracts.

## Based on the BondingCurveBase and BondingCurveBaseRedeeming contracts

Because the quadratic price formula contract is based on the bonding curve base and bonding curve base redeeming contracts, it inherits the functionalities of both contracts. These functionalities are described in the following sections.

### Buy

The buy function allows users to buy issuance tokens from the quadratic price formula contract by providing collateral tokens. The collateral tokens are specified in the token() field of the quadratic price formula contract.

### Sell

The sell function allows users to sell issuance tokens back to the quadratic price formula contract in exchange for issuance tokens. The collateral tokens are specified in the token() field of the quadratic price formula contract.

### CalculatePurchaseReturn

This function calculates the amount of issuance tokens that can be purchased with the provided collateral tokens.

### CalculateSaleReturn

This function calculates the amount of collateral tokens that will be received for selling the provided issuance tokens.

### Open and Close Buy

The buy functionality can be restricted by the Workflow Admin to be enabled (open) or disabled (closed) for all users. This means the buy functionality is essentially paused.

### Open and Close Sell

The sell functionality can be restricted by the Workflow Admin to be enabled (open) or disabled (closed) for all users. This means the sell functionality is essentially paused.

## Project Fee Collection

The bonding curve contract is able to collect project fees in collateral tokens from users that use the buy and sell functions. The fees are taken as a percentage of the incoming/outgoing collateral tokens and are stored in the contract itself for later withdrawal. The workflow admin can set the fees via the setBuyFee and setSellFee functions respectively. To withdraw the fees the withdrawProjectCollateralFee() function can be used.

## The Quadratic Price Formula Contract and its Parameters

The key point that distinguishes this contract from the base contracts is the use of the QuadraticPriceFormula to determine the price of the distributed tokens. In the following, the parameters that are needed to set up the contract are described.

### IssuanceToken

The address of the issuance token that the BondingCurve contract will distribute/issue. The BondingCurve contract will determine the price of the issuance token relative to the collateral token based on the formula contract.

### AcceptedToken (Collateral Token)

The address of the token that is accepted as collateral by the BondingCurve contract. User will have to provide this token to the BondingCurve contract to purchase the issuance token.

### Formula address

The address of the formula contract that is used to calculate the price of the issuance token. This contract will have to implement the IQuadraticPriceFormula interface and the ERC165 interface to be compatible with the BondingCurve contract.

### Capital Required

@todo ???? What do i add here exactly?

Used in the calculation of the price of the bonding curve token.

### Base Price Multiplier

@todo ???? What do i add here exactly?

Used in the calculation of the price of the bonding curve token.

### buyFee

The fee that is charged for the buying of the issuance token.
The fee is collected from the collateral token that is provided by the user.
A value of 10_000 is 100%, so for example a value of 100 is 1%.

### sellFee

The fee that is charged for the selling of the bonding curve token.
The fee is collected from the collateral token that is returned to the user.
The value of 10_000 is 100%, so for example a value of 100 is 1%.

### buyIsOpen

This Value determines whether the buy functionality is open or closed for all users.
As it is a boolean value, it can be either true or false.
True means the buy functionality is open, false means it is closed.

### sellIsOpen

This Value determines whether the sell functionality is open or closed for all users.
As it is a boolean value, it can be either true or false.
True means the sell functionality is open, false means it is closed.

## Setup

For the BondingCurve contract setup the following contracts and parameters are needed:

### Before Workflow Deployment

Some steps have to be taken before the quadratic price formula workflow is deployed.

#### Issuance Token

The ERC20 contract of the token that the BondingCurve contract will distribute/issue.
This contract needs to be deployed before the quadratic price formula workflow is deployed, as the reference to the contract address is needed in the workflow deployment.

#### Quadratic Price Formula

The formula contract that is used to calculate the price of the issuance token.
This contract will have to implement the IQuadraticPriceFormula interface and the ERC165 interface to be compatible with the BondingCurve contract.
This contract needs to be deployed before the quadratic price formula workflow is deployed, as the reference to the contract address is needed in the workflow deployment.

### During Workflow Deployment

These steps are needed during the workflow deployment.
@todo Doesnt need anything here, but I wanted to leave it in as a reference.

#### Deployment Parameters

The following parameters need to be put in during the workflow deployment:

- **issuanceToken address**: What is the address of the issuance token?
- **acceptedToken (collateral Token) address**: What is the address of the token that is accepted as collateral by the BondingCurve contract?
- **quadratic price Formula address**: What is the address of the formula contract that is used to calculate the issuance and redeeming amount?
- **capitalRequired amount**: What is the capital that is needed to operate the protocol according to market size and conditions?
- **basePriceMultiplier value**: What is the base price multiplier in the bonding curve formula?
- **buyFee percentage**: What is the fee that is charged for the buying of the issuance token?
- **sellFee percentage**: What is the fee that is charged for the selling of the bonding curve token?
- **buyIsOpen boolean**: Is the buy functionality open or closed for all users?
- **sellIsOpen boolean**: Is the sell functionality open or closed for all users?

### After Workflow Deployment

Some steps have to be taken after the quadratic price formula workflow is deployed.

#### Issuance Token

For the setup to work the Issuance Token needs to enable and expose the Bonding Curve contract to use the mint and burn functionalities after the workflow deployment is finished.
