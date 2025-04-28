import numpy as np
import matplotlib.pyplot as plt
from dataclasses import dataclass
from typing import List, Tuple
import math

@dataclass
class Epoch:
    fixed_price: float
    issuance_threshold: float
    current_issuance: float = 0
    is_price_discovery: bool = False
    discovery_volume: float = 0
    discovery_price: float = 0

class UniswapV4HookSimulation:
    def __init__(
        self,
        initial_price: float,
        issuance_threshold: float,
        discovery_volume_limit: float,
        price_volatility_limit: float
    ):
        self.epochs: List[Epoch] = []
        self.current_epoch = Epoch(
            fixed_price=initial_price,
            issuance_threshold=issuance_threshold
        )
        self.epochs.append(self.current_epoch)
        
        self.discovery_volume_limit = discovery_volume_limit
        self.price_volatility_limit = price_volatility_limit
        self.total_collateral = 0
        self.price_history = []
        self.issuance_history = []
        
    def calculate_required_collateral(self) -> float:
        """Calculate the required collateral based on current issuance and price"""
        if self.current_epoch.is_price_discovery:
            # In price discovery, use the discovered price or floor price
            price = max(
                self.current_epoch.discovery_price,
                self.current_epoch.fixed_price * (1 - self.price_volatility_limit)
            )
        else:
            price = self.current_epoch.fixed_price
            
        return self.current_epoch.current_issuance * price
    
    def verify_backing_requirement(self) -> bool:
        """Verify if current collateral meets backing requirements"""
        required_collateral = self.calculate_required_collateral()
        return self.total_collateral >= required_collateral
    
    def simulate_mint(self, amount: float) -> Tuple[bool, str]:
        """Simulate minting tokens"""
        if not self.verify_backing_requirement():
            return False, "Insufficient backing"
            
        if self.current_epoch.is_price_discovery:
            if self.current_epoch.discovery_volume >= self.discovery_volume_limit:
                return False, "Discovery volume limit reached"
                
            # Simulate price impact in discovery phase
            price_impact = amount * 0.001  # 0.1% price impact
            self.current_epoch.discovery_price = self.current_epoch.fixed_price * (1 + price_impact)
            self.current_epoch.discovery_volume += amount
            
            # Check if price discovery should end
            if self.current_epoch.discovery_volume >= self.discovery_volume_limit:
                self._end_price_discovery()
                
        else:
            self.current_epoch.current_issuance += amount
            
            # Check if we should start price discovery
            if self.current_epoch.current_issuance >= self.current_epoch.issuance_threshold:
                self._start_price_discovery()
                
        self.total_collateral += amount * self.current_epoch.fixed_price
        self.price_history.append(self.current_epoch.fixed_price)
        self.issuance_history.append(self.current_epoch.current_issuance)
        return True, "Success"
    
    def _start_price_discovery(self):
        """Start price discovery phase"""
        self.current_epoch.is_price_discovery = True
        self.current_epoch.discovery_price = self.current_epoch.fixed_price
        self.current_epoch.discovery_volume = 0
        
    def _end_price_discovery(self):
        """End price discovery phase and start new epoch"""
        # Create new epoch with discovered price
        new_price = self.current_epoch.discovery_price
        new_epoch = Epoch(
            fixed_price=new_price,
            issuance_threshold=self.current_epoch.issuance_threshold
        )
        self.epochs.append(new_epoch)
        self.current_epoch = new_epoch

def run_simulation():
    # Initialize simulation
    sim = UniswapV4HookSimulation(
        initial_price=1.0,
        issuance_threshold=1000,
        discovery_volume_limit=500,
        price_volatility_limit=0.1  # 10% max price movement
    )
    
    # Simulate a series of mints
    mint_amounts = np.random.normal(100, 20, 50)  # Random mint amounts
    
    for amount in mint_amounts:
        success, message = sim.simulate_mint(amount)
        if not success:
            print(f"Mint failed: {message}")
            break
    
    # Plot results
    plt.figure(figsize=(12, 6))
    
    # Plot price history
    plt.subplot(1, 2, 1)
    plt.plot(sim.price_history)
    plt.title('Token Price Over Time')
    plt.xlabel('Transaction')
    plt.ylabel('Price')
    
    # Plot issuance history
    plt.subplot(1, 2, 2)
    plt.plot(sim.issuance_history)
    plt.title('Total Issuance Over Time')
    plt.xlabel('Transaction')
    plt.ylabel('Issuance')
    
    plt.tight_layout()
    plt.show()
    
    # Print final state
    print("\nFinal State:")
    print(f"Total Epochs: {len(sim.epochs)}")
    print(f"Current Price: {sim.current_epoch.fixed_price}")
    print(f"Current Issuance: {sim.current_epoch.current_issuance}")
    print(f"Total Collateral: {sim.total_collateral}")
    print(f"Required Collateral: {sim.calculate_required_collateral()}")
    print(f"Backing Requirement Met: {sim.verify_backing_requirement()}")

if __name__ == "__main__":
    run_simulation() 