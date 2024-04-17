// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {TaxMan, ITaxMan} from "src/external/taxation/TaxMan.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract TaxManTest is Test {
    // SuT
    TaxMan tax;

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
    event DefaultCollateralFeeSet(uint fee);
    event DefaultIssuanceFeeSet(uint fee);
    event CollateralWorkflowFeeSet(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    );
    event IssuanceWorkflowFeeSet(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    );

    function setUp() public {
        tax = new TaxMan();
        tax.init(
            address(this),
            defaultProtocolTreasury,
            defaultCollateralFee,
            defaultIssuanceFee
        );
        INVALID_FEE = tax.BPS() + 1;
    }

    //--------------------------------------------------------------------------
    // Test: SupportsInterface

    function testSupportsInterface() public {
        assertTrue(tax.supportsInterface(type(ITaxMan).interfaceId));
    }

    //--------------------------------------------------------------------------
    // Test: Modifier

    function testValidAddress(address adr) public {
        if (adr == address(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(ITaxMan.TaxMan__InvalidAddress.selector)
            );
        }
        tax.setDefaultProtocolTreasury(adr);
    }

    function testValidFee(uint amt) public {
        if (amt > tax.BPS()) {
            vm.expectRevert(
                abi.encodeWithSelector(ITaxMan.TaxMan__InvalidFee.selector)
            );
        }

        tax.setDefaultCollateralFee(amt);
    }

    //--------------------------------------------------------------------------
    // Test: Init

    function testInit() public {
        assertEq(tax.owner(), address(this));
        assertEq(tax.getDefaultProtocolTreasury(), defaultProtocolTreasury);
        assertEq(tax.getDefaultCollateralFee(), defaultCollateralFee);
        assertEq(tax.getDefaultIssuanceFee(), defaultIssuanceFee);
    }

    function testInitModifierInPosition() public {
        //initializer
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        tax.init(
            address(this),
            defaultProtocolTreasury,
            defaultCollateralFee,
            defaultIssuanceFee
        );

        tax = new TaxMan();
        //validAddress(owner)
        vm.expectRevert(
            abi.encodeWithSelector(ITaxMan.TaxMan__InvalidAddress.selector)
        );
        tax.init(
            address(0),
            defaultProtocolTreasury,
            defaultCollateralFee,
            defaultIssuanceFee
        );

        // validAddress(_defaultProtocolTreasury)
        vm.expectRevert(
            abi.encodeWithSelector(ITaxMan.TaxMan__InvalidAddress.selector)
        );
        tax.init(
            address(this), address(0), defaultCollateralFee, defaultIssuanceFee
        );

        //validFee(_defaultCollateralFee)
        vm.expectRevert(
            abi.encodeWithSelector(ITaxMan.TaxMan__InvalidFee.selector)
        );
        tax.init(
            address(this),
            defaultProtocolTreasury,
            INVALID_FEE,
            defaultIssuanceFee
        );

        //validFee(_defaultIssuanceFee)
        vm.expectRevert(
            abi.encodeWithSelector(ITaxMan.TaxMan__InvalidFee.selector)
        );
        tax.init(
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
        tax.getDefaultProtocolTreasury();
    }

    function testGetWorkflowTreasuries(bool shouldBeSet, address workflow)
        public
    {
        address expectedAddress = defaultProtocolTreasury;
        if (shouldBeSet) {
            expectedAddress = alternativeTreasury;
            tax.setWorkflowTreasuries(workflow, alternativeTreasury);
        }

        assertEq(tax.getWorkflowTreasuries(workflow), expectedAddress);
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
            tax.setCollateralWorkflowFee(
                workflow, module, functionSelec, true, alternativeCollateralFee
            );
        }

        assertEq(
            tax.getCollateralWorkflowFee(workflow, module, functionSelec),
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
            tax.setIssuanceWorkflowFee(
                workflow, module, functionSelec, true, alternativeIssuanceFee
            );
        }

        assertEq(
            tax.getIssuanceWorkflowFee(workflow, module, functionSelec),
            expectedFee
        );
    }

    function testGetCollateralWorkflowFeeAndTreasury() public {
        //Trivial
        tax.getCollateralWorkflowFeeAndTreasury(
            address(0), address(0), bytes4("0")
        );
    }

    function testGetIssuanceWorkflowFeeAndTreasury() public {
        //Trivial
        tax.getIssuanceWorkflowFeeAndTreasury(
            address(0), address(0), bytes4("0")
        );
    }

    //--------------------------------------------------------------------------
    // Test: Setter Functions

    function testSetDefaultProtocolTreasury(address adr) public {
        vm.assume(adr != address(0));

        vm.expectEmit(true, true, true, true);
        emit DefaultProtocolTreasurySet(adr);

        tax.setDefaultProtocolTreasury(adr);
        assertEq(tax.getDefaultProtocolTreasury(), adr);
    }

    function testSetDefaultProtocolTreasuryModifierInPosition() public {
        //onlyOwner
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0)
            )
        );
        vm.prank(address(0));
        tax.setDefaultProtocolTreasury(address(0x1));

        //validAddress(_defaultProtocolTreasury)
        vm.expectRevert(
            abi.encodeWithSelector(ITaxMan.TaxMan__InvalidAddress.selector)
        );

        tax.setDefaultProtocolTreasury(address(0));
    }

    function testSetWorkflowTreasuries(address workflow, address adr) public {
        vm.assume(adr != address(0));

        vm.expectEmit(true, true, true, true);
        emit WorkflowTreasurySet(workflow, adr);

        tax.setWorkflowTreasuries(workflow, adr);
        assertEq(tax.getWorkflowTreasuries(workflow), adr);
    }

    function testSetWorkflowTreasuriesModifierInPosition() public {
        //onlyOwner
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0)
            )
        );
        vm.prank(address(0));
        tax.setWorkflowTreasuries(address(0x1), address(0x1));

        //validAddress(treasury)
        vm.expectRevert(
            abi.encodeWithSelector(ITaxMan.TaxMan__InvalidAddress.selector)
        );

        tax.setWorkflowTreasuries(address(0x1), address(0));
    }

    //---------------------------
    // Fees

    function testDefaultCollateralFeey(uint fee) public {
        vm.assume(fee <= tax.BPS());

        vm.expectEmit(true, true, true, true);
        emit DefaultCollateralFeeSet(fee);

        tax.setDefaultCollateralFee(fee);
        assertEq(tax.getDefaultCollateralFee(), fee);
    }

    function testSetDefaultCollateralFeeModifierInPosition() public {
        //onlyOwner
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0)
            )
        );
        vm.prank(address(0));
        tax.setDefaultCollateralFee(0);

        //validFee(_defaultCollateralFee)
        vm.expectRevert(
            abi.encodeWithSelector(ITaxMan.TaxMan__InvalidFee.selector)
        );

        tax.setDefaultCollateralFee(INVALID_FEE);
    }

    function testDefaultIssuanceFeey(uint fee) public {
        vm.assume(fee <= tax.BPS());

        vm.expectEmit(true, true, true, true);
        emit DefaultIssuanceFeeSet(fee);

        tax.setDefaultIssuanceFee(fee);
        assertEq(tax.getDefaultIssuanceFee(), fee);
    }

    function testSetDefaultIssuanceFeeModifierInPosition() public {
        //onlyOwner
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0)
            )
        );
        vm.prank(address(0));
        tax.setDefaultIssuanceFee(0);

        //validFee(_defaultIssuanceFee)
        vm.expectRevert(
            abi.encodeWithSelector(ITaxMan.TaxMan__InvalidFee.selector)
        );

        tax.setDefaultIssuanceFee(INVALID_FEE);
    }

    function testSetCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) public {
        vm.assume(fee <= tax.BPS());

        vm.expectEmit(true, true, true, true);
        emit CollateralWorkflowFeeSet(
            workflow, module, functionSelector, set, fee
        );

        tax.setCollateralWorkflowFee(
            workflow, module, functionSelector, set, fee
        );

        if (set) {
            assertEq(
                tax.getCollateralWorkflowFee(workflow, module, functionSelector),
                fee
            );
        } else {
            assertEq(
                tax.getCollateralWorkflowFee(workflow, module, functionSelector),
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
        tax.setCollateralWorkflowFee(
            address(0x1), address(0x1), bytes4("1"), true, 0
        );

        //validFee(fee)
        vm.expectRevert(
            abi.encodeWithSelector(ITaxMan.TaxMan__InvalidFee.selector)
        );

        tax.setCollateralWorkflowFee(
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
        vm.assume(fee <= tax.BPS());

        vm.expectEmit(true, true, true, true);
        emit IssuanceWorkflowFeeSet(
            workflow, module, functionSelector, set, fee
        );

        tax.setIssuanceWorkflowFee(workflow, module, functionSelector, set, fee);

        if (set) {
            assertEq(
                tax.getIssuanceWorkflowFee(workflow, module, functionSelector),
                fee
            );
        } else {
            assertEq(
                tax.getIssuanceWorkflowFee(workflow, module, functionSelector),
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
        tax.setIssuanceWorkflowFee(
            address(0x1), address(0x1), bytes4("1"), true, 0
        );

        //validFee(fee)
        vm.expectRevert(
            abi.encodeWithSelector(ITaxMan.TaxMan__InvalidFee.selector)
        );

        tax.setIssuanceWorkflowFee(
            address(0x1), address(0x1), bytes4("1"), true, INVALID_FEE
        );
    }
}
