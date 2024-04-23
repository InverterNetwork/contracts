// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {FeeManager, IFeeManager} from "src/external/fees/FeeManager.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract FeeManagerTest is Test {
    // SuT
    FeeManager feeMan;

    //State
    address defaultProtocolTreasury = address(0x111111);
    address alternativeTreasury = address(0x222222);

    uint defaultCollateralFee = 101; //1,01%
    uint defaultIssuanceFee = 102; //1,02%

    uint alternativeCollateralFee = 103; //1,01%
    uint alternativeIssuanceFee = 104; //1,02%

    uint INVALID_FEE;

    //Events
    event DefaultProtocolTreasurySet(address defaultProtocolTreasury);
    event WorkflowTreasurySet(address workflow, address treasury);
    event DefaultCollateralFeeSet(uint feeMan);
    event DefaultIssuanceFeeSet(uint feeMan);
    event CollateralWorkflowFeeSet(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint feeMan
    );
    event IssuanceWorkflowFeeSet(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint feeMan
    );

    function setUp() public {
        feeMan = new FeeManager();
        feeMan.init(
            address(this),
            defaultProtocolTreasury,
            defaultCollateralFee,
            defaultIssuanceFee
        );
        INVALID_FEE = feeMan.BPS() + 1;
    }

    //--------------------------------------------------------------------------
    // Test: SupportsInterface

    function testSupportsInterface() public {
        assertTrue(feeMan.supportsInterface(type(IFeeManager).interfaceId));
    }

    //--------------------------------------------------------------------------
    // Test: Modifier

    function testValidAddress(address adr) public {
        if (adr == address(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IFeeManager.FeeManager__InvalidAddress.selector
                )
            );
        }
        feeMan.setDefaultProtocolTreasury(adr);
    }

    function testValidFee(uint amt) public {
        if (amt > feeMan.BPS()) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IFeeManager.FeeManager__InvalidFee.selector
                )
            );
        }

        feeMan.setDefaultCollateralFee(amt);
    }

    //--------------------------------------------------------------------------
    // Test: Init

    function testInit() public {
        assertEq(feeMan.owner(), address(this));
        assertEq(feeMan.getDefaultProtocolTreasury(), defaultProtocolTreasury);
        assertEq(feeMan.getDefaultCollateralFee(), defaultCollateralFee);
        assertEq(feeMan.getDefaultIssuanceFee(), defaultIssuanceFee);
    }

    function testInitModifierInPosition() public {
        //initializer
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        feeMan.init(
            address(this),
            defaultProtocolTreasury,
            defaultCollateralFee,
            defaultIssuanceFee
        );

        feeMan = new FeeManager();
        //validAddress(owner)
        vm.expectRevert(
            abi.encodeWithSelector(
                IFeeManager.FeeManager__InvalidAddress.selector
            )
        );
        feeMan.init(
            address(0),
            defaultProtocolTreasury,
            defaultCollateralFee,
            defaultIssuanceFee
        );

        // validAddress(_defaultProtocolTreasury)
        vm.expectRevert(
            abi.encodeWithSelector(
                IFeeManager.FeeManager__InvalidAddress.selector
            )
        );
        feeMan.init(
            address(this), address(0), defaultCollateralFee, defaultIssuanceFee
        );

        //validFee(_defaultCollateralFee)
        vm.expectRevert(
            abi.encodeWithSelector(IFeeManager.FeeManager__InvalidFee.selector)
        );
        feeMan.init(
            address(this),
            defaultProtocolTreasury,
            INVALID_FEE,
            defaultIssuanceFee
        );

        //validFee(_defaultIssuanceFee)
        vm.expectRevert(
            abi.encodeWithSelector(IFeeManager.FeeManager__InvalidFee.selector)
        );
        feeMan.init(
            address(this),
            defaultProtocolTreasury,
            defaultCollateralFee,
            INVALID_FEE
        );
    }

    //--------------------------------------------------------------------------
    // Test: Getter Functions

    function testGetDefaultProtocolTreasury() public {
        //Trivial
        feeMan.getDefaultProtocolTreasury();
    }

    function testGetWorkflowTreasuries(bool shouldBeSet, address workflow)
        public
    {
        address expectedAddress = defaultProtocolTreasury;
        if (shouldBeSet) {
            expectedAddress = alternativeTreasury;
            feeMan.setWorkflowTreasuries(workflow, alternativeTreasury);
        }

        assertEq(feeMan.getWorkflowTreasuries(workflow), expectedAddress);
    }

    function testGetCollateralWorkflowFee(
        bool shouldBeSet,
        address workflow,
        address module,
        bytes4 functionSelec
    ) public {
        uint expectedFee = defaultCollateralFee;
        if (shouldBeSet) {
            expectedFee = alternativeCollateralFee;
            feeMan.setCollateralWorkflowFee(
                workflow, module, functionSelec, true, alternativeCollateralFee
            );
        }

        assertEq(
            feeMan.getCollateralWorkflowFee(workflow, module, functionSelec),
            expectedFee
        );
    }

    function testGetIssuanceWorkflowFee(
        bool shouldBeSet,
        address workflow,
        address module,
        bytes4 functionSelec
    ) public {
        uint expectedFee = defaultIssuanceFee;
        if (shouldBeSet) {
            expectedFee = alternativeIssuanceFee;
            feeMan.setIssuanceWorkflowFee(
                workflow, module, functionSelec, true, alternativeIssuanceFee
            );
        }

        assertEq(
            feeMan.getIssuanceWorkflowFee(workflow, module, functionSelec),
            expectedFee
        );
    }

    function testGetCollateralWorkflowFeeAndTreasury() public {
        //Trivial
        feeMan.getCollateralWorkflowFeeAndTreasury(
            address(0), address(0), bytes4("0")
        );
    }

    function testGetIssuanceWorkflowFeeAndTreasury() public {
        //Trivial
        feeMan.getIssuanceWorkflowFeeAndTreasury(
            address(0), address(0), bytes4("0")
        );
    }

    //--------------------------------------------------------------------------
    // Test: Setter Functions

    function testSetDefaultProtocolTreasury(address adr) public {
        vm.assume(adr != address(0));

        vm.expectEmit(true, true, true, true);
        emit DefaultProtocolTreasurySet(adr);

        feeMan.setDefaultProtocolTreasury(adr);
        assertEq(feeMan.getDefaultProtocolTreasury(), adr);
    }

    function testSetDefaultProtocolTreasuryModifierInPosition() public {
        //onlyOwner
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0)
            )
        );
        vm.prank(address(0));
        feeMan.setDefaultProtocolTreasury(address(0x1));

        //validAddress(_defaultProtocolTreasury)
        vm.expectRevert(
            abi.encodeWithSelector(
                IFeeManager.FeeManager__InvalidAddress.selector
            )
        );

        feeMan.setDefaultProtocolTreasury(address(0));
    }

    function testSetWorkflowTreasuries(address workflow, address adr) public {
        vm.assume(adr != address(0));

        vm.expectEmit(true, true, true, true);
        emit WorkflowTreasurySet(workflow, adr);

        feeMan.setWorkflowTreasuries(workflow, adr);
        assertEq(feeMan.getWorkflowTreasuries(workflow), adr);
    }

    function testSetWorkflowTreasuriesModifierInPosition() public {
        //onlyOwner
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0)
            )
        );
        vm.prank(address(0));
        feeMan.setWorkflowTreasuries(address(0x1), address(0x1));

        //validAddress(treasury)
        vm.expectRevert(
            abi.encodeWithSelector(
                IFeeManager.FeeManager__InvalidAddress.selector
            )
        );

        feeMan.setWorkflowTreasuries(address(0x1), address(0));
    }

    //---------------------------
    // Fees

    function testDefaultCollateralFeey(uint fee) public {
        vm.assume(fee <= feeMan.BPS());

        vm.expectEmit(true, true, true, true);
        emit DefaultCollateralFeeSet(fee);

        feeMan.setDefaultCollateralFee(fee);
        assertEq(feeMan.getDefaultCollateralFee(), fee);
    }

    function testSetDefaultCollateralFeeModifierInPosition() public {
        //onlyOwner
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0)
            )
        );
        vm.prank(address(0));
        feeMan.setDefaultCollateralFee(0);

        //validFee(_defaultCollateralFee)
        vm.expectRevert(
            abi.encodeWithSelector(IFeeManager.FeeManager__InvalidFee.selector)
        );

        feeMan.setDefaultCollateralFee(INVALID_FEE);
    }

    function testDefaultIssuanceFeey(uint fee) public {
        vm.assume(fee <= feeMan.BPS());

        vm.expectEmit(true, true, true, true);
        emit DefaultIssuanceFeeSet(fee);

        feeMan.setDefaultIssuanceFee(fee);
        assertEq(feeMan.getDefaultIssuanceFee(), fee);
    }

    function testSetDefaultIssuanceFeeModifierInPosition() public {
        //onlyOwner
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0)
            )
        );
        vm.prank(address(0));
        feeMan.setDefaultIssuanceFee(0);

        //validFee(_defaultIssuanceFee)
        vm.expectRevert(
            abi.encodeWithSelector(IFeeManager.FeeManager__InvalidFee.selector)
        );

        feeMan.setDefaultIssuanceFee(INVALID_FEE);
    }

    function testSetCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) public {
        vm.assume(fee <= feeMan.BPS());

        vm.expectEmit(true, true, true, true);
        emit CollateralWorkflowFeeSet(
            workflow, module, functionSelector, set, fee
        );

        feeMan.setCollateralWorkflowFee(
            workflow, module, functionSelector, set, fee
        );

        if (set) {
            assertEq(
                feeMan.getCollateralWorkflowFee(
                    workflow, module, functionSelector
                ),
                fee
            );
        } else {
            assertEq(
                feeMan.getCollateralWorkflowFee(
                    workflow, module, functionSelector
                ),
                defaultCollateralFee
            );
        }
    }

    function testSetCollateralWorkflowFeeModifierInPosition() public {
        //onlyOwner
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0)
            )
        );
        vm.prank(address(0));
        feeMan.setCollateralWorkflowFee(
            address(0x1), address(0x1), bytes4("1"), true, 0
        );

        //validFee(feeMan)
        vm.expectRevert(
            abi.encodeWithSelector(IFeeManager.FeeManager__InvalidFee.selector)
        );

        feeMan.setCollateralWorkflowFee(
            address(0x1), address(0x1), bytes4("1"), true, INVALID_FEE
        );
    }

    function testSetIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) public {
        vm.assume(fee <= feeMan.BPS());

        vm.expectEmit(true, true, true, true);
        emit IssuanceWorkflowFeeSet(
            workflow, module, functionSelector, set, fee
        );

        feeMan.setIssuanceWorkflowFee(
            workflow, module, functionSelector, set, fee
        );

        if (set) {
            assertEq(
                feeMan.getIssuanceWorkflowFee(
                    workflow, module, functionSelector
                ),
                fee
            );
        } else {
            assertEq(
                feeMan.getIssuanceWorkflowFee(
                    workflow, module, functionSelector
                ),
                defaultIssuanceFee
            );
        }
    }

    function testSetIssuanceWorkflowFeeModifierInPosition() public {
        //onlyOwner
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0)
            )
        );
        vm.prank(address(0));
        feeMan.setIssuanceWorkflowFee(
            address(0x1), address(0x1), bytes4("1"), true, 0
        );

        //validFee(feeMan)
        vm.expectRevert(
            abi.encodeWithSelector(IFeeManager.FeeManager__InvalidFee.selector)
        );

        feeMan.setIssuanceWorkflowFee(
            address(0x1), address(0x1), bytes4("1"), true, INVALID_FEE
        );
    }
}
