# Notes

## Critical Findings

- calculateReserveForSupply doesn't seem to be able to handle partially filled steps
- therefore the fuzz test for calculatePurchaseReturn is failing (it uses the output of calculateReserveForSupply for assertion)
