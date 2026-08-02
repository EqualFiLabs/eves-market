// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOInsuranceFund} from "../../src/MLOInsuranceFund.sol";
import {IMLOInsuranceFund} from "../../src/interfaces/IMLOInsuranceFund.sol";
import {CollateralTestBase} from "../helpers/CollateralTestBase.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract InsuranceRiskManager {}

contract FeeChargingCollateral is ERC20 {
    uint256 internal feeBps;

    constructor() ERC20("Fee Charging Collateral", "FEE") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function setFeeBps(uint256 newFeeBps) external {
        require(newFeeBps <= 10_000, "invalid fee");
        feeBps = newFeeBps;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0) || feeBps == 0) {
            super._update(from, to, value);
            return;
        }
        uint256 fee = (value * feeBps) / 10_000;
        super._update(from, to, value - fee);
        if (fee != 0) super._update(from, address(0), fee);
    }
}

contract InsuranceGovernance {
    address public owner;

    constructor(address initialOwner) {
        owner = initialOwner;
    }

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "not owner");
        owner = newOwner;
    }
}

contract MLOInsuranceFundTest is CollateralTestBase {
    MLOInsuranceFund internal fund;
    InsuranceGovernance internal governance;
    bytes32 internal bucketId;

    function setUp() public override {
        super.setUp();
        owner = makeAddr("insurance-owner");
        riskManager = address(new InsuranceRiskManager());
        bucketId = keccak256("insured-bucket");
        governance = new InsuranceGovernance(owner);
        fund = new MLOInsuranceFund(address(collateral), address(governance), riskManager);
    }

    function test_PermissionlessSponsorPermanentlyAddsInsurance() public {
        _seedCollateral(alice, 10e18);
        vm.startPrank(alice);
        collateral.approve(address(fund), 10e18);
        fund.sponsor(10e18);
        vm.stopPrank();

        assertEq(fund.availableInsurance(), 10e18);
        assertEq(fund.totalSponsored(), 10e18);
        assertEq(collateral.balanceOf(address(fund)), 10e18);
    }

    function test_FundingRevenueAndDrawRemainBucketAttributed() public {
        _seedCollateral(riskManager, 12e18);
        vm.startPrank(riskManager);
        collateral.approve(address(fund), 12e18);
        fund.notifyFundingRevenue(bucketId, 12e18);
        fund.draw(bucketId, bob, 5e18);
        vm.stopPrank();

        assertEq(fund.totalFundingRevenue(), 12e18);
        assertEq(fund.bucketFundingRevenue(bucketId), 12e18);
        assertEq(fund.totalDrawn(), 5e18);
        assertEq(fund.bucketDrawn(bucketId), 5e18);
        assertEq(fund.availableInsurance(), 7e18);
        assertEq(collateral.balanceOf(bob), 5e18);
    }

    function test_RevertWhen_UnauthorizedCallerRecordsOrDraws() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMLOInsuranceFund.NotRiskManager.selector, alice));
        fund.notifyFundingRevenue(bucketId, 1);
        vm.expectRevert(abi.encodeWithSelector(IMLOInsuranceFund.NotRiskManager.selector, alice));
        fund.draw(bucketId, alice, 1);
        vm.stopPrank();
    }

    function test_RevertWhen_DrawExceedsAvailableInsurance() public {
        vm.prank(riskManager);
        vm.expectRevert(abi.encodeWithSelector(IMLOInsuranceFund.InsufficientInsurance.selector, 1, 0));
        fund.draw(bucketId, bob, 1);
    }

    function test_OwnerCanRotateRiskManagerButCannotWithdrawInsurance() public {
        address nextRiskManager = address(new InsuranceRiskManager());
        vm.prank(owner);
        fund.setRiskManager(nextRiskManager);
        assertEq(fund.riskManager(), nextRiskManager);
    }

    function test_GovernanceHandoffRevokesFormerInsuranceAuthority() public {
        address newOwner = makeAddr("new-insurance-owner");
        address nextRiskManager = address(new InsuranceRiskManager());
        vm.prank(owner);
        governance.transferOwnership(newOwner);

        assertEq(fund.owner(), newOwner);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMLOInsuranceFund.NotOwner.selector, owner));
        fund.setRiskManager(nextRiskManager);

        vm.prank(newOwner);
        fund.setRiskManager(nextRiskManager);
        assertEq(fund.riskManager(), nextRiskManager);
    }

    function testFuzz_GovernanceDerivedAuthorityTracksOwnerHandoff(address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != owner);
        address nextRiskManager = address(new InsuranceRiskManager());
        vm.prank(owner);
        governance.transferOwnership(newOwner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMLOInsuranceFund.NotOwner.selector, owner));
        fund.setRiskManager(nextRiskManager);
        vm.prank(newOwner);
        fund.setRiskManager(nextRiskManager);

        assertEq(fund.owner(), newOwner);
        assertEq(fund.riskManager(), nextRiskManager);
    }

    function test_RevertWhen_FeeChargingAssetCreditsLessThanSponsored() public {
        FeeChargingCollateral feeAsset = new FeeChargingCollateral();
        MLOInsuranceFund feeFund = new MLOInsuranceFund(address(feeAsset), address(governance), riskManager);
        feeAsset.mint(alice, 100e18);
        feeAsset.setFeeBps(100);

        vm.startPrank(alice);
        feeAsset.approve(address(feeFund), 100e18);
        vm.expectRevert(abi.encodeWithSelector(IMLOInsuranceFund.NonExactTransfer.selector, 100e18, 100e18, 99e18));
        feeFund.sponsor(100e18);
        vm.stopPrank();

        assertEq(feeFund.availableInsurance(), 0);
        assertEq(feeFund.totalSponsored(), 0);
    }

    function test_RevertWhen_FeeChargingAssetShortsDrawReceiver() public {
        FeeChargingCollateral feeAsset = new FeeChargingCollateral();
        MLOInsuranceFund feeFund = new MLOInsuranceFund(address(feeAsset), address(governance), riskManager);
        feeAsset.mint(alice, 10e18);
        vm.startPrank(alice);
        feeAsset.approve(address(feeFund), 10e18);
        feeFund.sponsor(10e18);
        vm.stopPrank();
        feeAsset.setFeeBps(1_000);

        vm.prank(riskManager);
        vm.expectRevert(abi.encodeWithSelector(IMLOInsuranceFund.NonExactTransfer.selector, 10e18, 10e18, 9e18));
        feeFund.draw(bucketId, bob, 10e18);

        assertEq(feeFund.availableInsurance(), 10e18);
        assertEq(feeFund.totalDrawn(), 0);
        assertEq(feeAsset.balanceOf(bob), 0);
    }
}
