# House Protocol - Project Brief

## Overview

House Protocol is a crypto-economic protocol built on the Inverter stack designed to support the proliferation of cultural assets through the $HOUSE token ecosystem.

## Core Value Proposition

Utilize crypto-economic mechanisms to create sustainable funding and value accrual for cultural assets (sports teams, artistic projects, community initiatives) while providing token holders with:

- Built-in price floor appreciation over time
- Liquidity access without selling positions (credit facility)
- Permissionless launching of cultural asset tokens

## Protocol Architecture

### Primary Components

- **$HOUSE Token**: Main protocol token with discrete bonding curve price discovery
- **Pre-sale Phase**: Permissioned institutional investor round at fixed stable coin price
- **Primary Issuance Market (PIM)**: Public minting/redeeming via Discrete Bonding Curve post pre-sale
- **Credit Facility**: Borrow against locked $HOUSE tokens without liquidation risk
- **Endowment Token Ecosystem**: Cultural asset tokens using same mechanisms as $HOUSE

### Key Innovation: Discrete Bonding Curve

Unlike traditional smooth bonding curves, House Protocol uses **step-function pricing** where:

- Price increases occur at discrete supply intervals (steps)
- Each segment can have different pricing characteristics (flat vs sloped)
- Enables more predictable pricing behavior and gas-optimized calculations
- Supports complex multi-phase launch strategies

## Technical Implementation - Inverter Stack Modules

### Core Modules to Build

1. **FM_BC_Discrete** (Funding Manager - Discrete Bonding Curve)

   - Manages token minting and redeeming based on curve mathematics
   - Handles collateral reserves and virtual supply tracking
   - Supports curve reconfiguration with mathematical invariance checks

2. **DiscreteCurveMathLib_v1** ✅ **[COMPLETED]**

   - Pure mathematical functions for all curve calculations
   - Gas-optimized with packed storage (75% storage reduction)
   - Type-safe implementation with comprehensive validation

3. **DynamicFeeCalculator**

   - Calculates dynamic fees based on system state
   - Separate exchangeable module for future fee logic updates
   - Supports mint, redeem, and loan origination fee calculations

4. **LM_PC_Credit_Facility** (Logic Module - Credit Facility)

   - Enables borrowing against locked issuance tokens
   - No liquidation risk (floor price only increases)
   - Integration with fee calculator for dynamic origination fees

5. **Rebalancing Modules**
   - **LM_PC_Shift**: Liquidity rebalancing (reserve-invariant curve reconfiguration)
   - **LM_PC_Elevator**: Revenue injection for floor price elevation

### Economic Mechanisms

#### Discrete Bonding Curve Mechanics

- **Step-based pricing**: Tokens sold in discrete batches at fixed prices per step
- **Segment configuration**: Multiple segments with different slope characteristics
- **Reserve backing**: Mathematical guarantee of collateral backing for all issued tokens
- **Invariance preservation**: Curve reconfigurations maintain reserve consistency

#### Floor Price Appreciation

Two primary mechanisms raise the minimum token price over time:

1. **Revenue Injection**: Protocol fees injected as additional collateral
2. **Liquidity Rebalancing**: Redistribute existing collateral to raise floor segments

#### Dynamic Fee System

Fees adjust based on real-time system conditions:

- **Minting/Redeeming fees**: Based on premium above/below floor price
- **Origination fees**: Based on credit facility utilization rates
- **Fee collection**: Revenue feeds back into floor price elevation

## Target User Journey

### Phase 1: Pre-sale (Institutional)

1. Whitelisted institutional investors purchase $HOUSE at fixed price
2. Funds collected provide initial collateral backing for bonding curve
3. Determines exact shape of first curve segment based on total raised

### Phase 2: Public Launch

1. Discrete bonding curve initialized with pre-sale collateral
2. Public users mint/redeem $HOUSE tokens via curve pricing
3. Protocol collects fees on transactions

### Phase 3: Ecosystem Growth

1. Revenue injection gradually raises floor price
2. Credit facility allows liquidity access without selling
3. Cultural asset creators launch endowment tokens using same mechanics

## Business Model & Sustainability

### Revenue Sources

- Transaction fees on minting and redeeming
- Origination fees from credit facility loans
- Potential fees from endowment token launches

### Value Accrual Mechanism

- Collected fees injected as additional collateral backing
- Floor price increases benefit all token holders
- Creates positive feedback loop: higher floor → more attractive investment → more usage → more fees

### Network Effects

- Each new cultural asset token increases protocol usage
- Shared infrastructure reduces launch costs for creators
- Growing ecosystem attracts more institutional pre-sale participation

## Success Metrics & KPIs

### Protocol Health

- Floor price appreciation rate over time
- Transaction volume and fee generation
- Credit facility utilization rates
- Number of cultural asset tokens launched

### User Experience

- Cost efficiency of minting/redeeming vs alternatives
- Credit facility borrowing costs vs traditional lending
- Cultural asset funding success rates

## Competitive Advantages

### Technical

- **Gas-optimized mathematics**: 75% storage reduction with packed segments
- **Predictable pricing**: Discrete steps vs volatile smooth curves
- **Modular architecture**: Leverages proven Inverter stack
- **Type-safe implementation**: Prevents costly integration errors

### Economic

- **Built-in price support**: Floor price appreciation mechanism
- **Capital efficiency**: Credit facility unlocks liquidity without selling
- **Permissionless expansion**: Community-driven cultural asset token creation
- **Institutional bridge**: Pre-sale structure attracts professional investors

## Risk Assessment & Mitigations

### Technical Risks - ✅ **LARGELY MITIGATED**

- **Mathematical complexity**: Solved with production-ready DiscreteCurveMathLib_v1
- **Gas efficiency**: Proven with optimized algorithms and storage patterns
- **Integration complexity**: Clear patterns established from math library implementation

### Economic Risks

- **Floor price mechanism failure**: Multiple backup mechanisms (injection + rebalancing)
- **Credit facility over-utilization**: Dynamic fees and borrowing limits
- **Insufficient demand for cultural assets**: Protocol works with single asset ($HOUSE)

### Regulatory Risks

- **Asset classification uncertainty**: Designed with compliance features (asset freezing)
- **Cross-chain regulatory differences**: Modular deployment supports jurisdiction-specific configurations

## Development Roadmap

### Phase 1: Core Infrastructure ✅ **FOUNDATION COMPLETE**

- [x] **DiscreteCurveMathLib_v1**: Production-ready mathematical foundation
- [ ] **FM_BC_Discrete**: Core funding manager with minting/redeeming
- [ ] **DynamicFeeCalculator**: Configurable fee calculation module

### Phase 2: Advanced Features

- [ ] **Credit Facility**: Lending against locked tokens
- [ ] **Floor Price Mechanisms**: Revenue injection and rebalancing modules
- [ ] **Cross-chain Integration**: Token bridging capabilities

### Phase 3: Ecosystem Launch

- [ ] **Pre-sale Implementation**: Institutional investor onboarding
- [ ] **Public Launch**: Bonding curve activation
- [ ] **Cultural Asset Framework**: Endowment token creation tools

## Technology Stack

### Smart Contract Platform

- **Blockchain**: Ethereum L1 and/or Unichain (pending bridging requirements)
- **Language**: Solidity ^0.8.19
- **Framework**: Inverter Network modular architecture

### Key Dependencies

- **Mathematical precision**: OpenZeppelin Math library for overflow protection
- **Access control**: Inverter AUT_Roles for permission management
- **Virtual accounting**: Inverter VirtualSupplyBase contracts for state tracking

## Success Criteria

### Technical Milestones

- ✅ Mathematical foundation complete and gas-optimized
- 🎯 Core minting/redeeming functionality operational
- 🎯 Dynamic fee system responsive to market conditions
- 🎯 Floor price elevation mechanisms functional

### Economic Milestones

- 🎯 Successful pre-sale execution with institutional participation
- 🎯 Sustainable transaction volume post-public launch
- 🎯 Demonstrable floor price appreciation over time
- 🎯 Credit facility achieving target utilization rates

### Ecosystem Milestones

- 🎯 First cultural asset endowment token successfully launched
- 🎯 Cross-chain functionality enabling multi-network participation
- 🎯 Community adoption of permissionless token creation tools

## Conclusion

House Protocol represents an innovative approach to sustainable funding for cultural assets through crypto-economic mechanisms. With a solid technical foundation now complete (DiscreteCurveMathLib_v1), the project is well-positioned for accelerated development toward a production launch.

The combination of discrete bonding curve mechanics, built-in price appreciation, and capital-efficient credit facilities creates a compelling value proposition for both cultural asset creators and token holders. The modular Inverter stack architecture provides flexibility for future enhancements while maintaining security and gas efficiency.

**Current Status**: Technical foundation complete, ready for core module development phase.
