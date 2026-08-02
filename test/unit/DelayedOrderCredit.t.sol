// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DelayedOrderFacet} from "../../src/facets/DelayedOrderFacet.sol";
import {LibDelayedOrder} from "../../src/libraries/LibDelayedOrder.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {DelayedOrderTypes} from "../../src/types/DelayedOrderTypes.sol";
import {TestBase} from "../helpers/TestBase.sol";

interface IDelayedOrderCreditFacet {
    function withdrawQuoteCredit(address token, uint128 amount) external;
    function withdrawBaseCredit(uint8 assetType, address token, uint256 tokenId, uint128 amount) external;
    function getQuoteCredit(address owner, address token)
        external
        view
        returns (DelayedOrderTypes.CreditBalanceView memory credit);
    function getBaseCredit(address owner, uint8 assetType, address token, uint256 tokenId)
        external
        view
        returns (DelayedOrderTypes.CreditBalanceView memory credit);
}

interface IDelayedOrderCreditSeederFacet {
    function creditQuoteFixture(address owner, address token, uint128 amount) external;
    function creditBaseFixture(address owner, uint8 assetType, address token, uint256 tokenId, uint128 amount) external;
}

contract DelayedOrderCreditSeederFacet {
    function creditQuoteFixture(address owner, address token, uint128 amount) external {
        LibDelayedOrder.creditQuote(owner, token, amount);
    }

    function creditBaseFixture(address owner, uint8 assetType, address token, uint256 tokenId, uint128 amount)
        external
    {
        LibDelayedOrder.creditBase(owner, LibEveMarket.BookAssetType(assetType), token, tokenId, amount);
    }
}

contract DelayedOrderCreditTest is TestBase {
    uint128 internal constant CREDIT_AMOUNT = 250e6;
    uint256 internal constant POSITION_ID = 42;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        diamond.registerFacet(address(new DelayedOrderFacet()), _delayedOrderCreditSelectors());
        diamond.registerFacet(address(new DelayedOrderCreditSeederFacet()), _creditSeederSelectors());
        vm.stopPrank();
    }

    function test_WithdrawQuoteCreditThroughDelayedOrderFacet() public {
        vm.prank(maker);
        usdc.transfer(address(diamond), CREDIT_AMOUNT);
        IDelayedOrderCreditSeederFacet(address(diamond)).creditQuoteFixture(taker, address(usdc), CREDIT_AMOUNT);

        uint256 takerBefore = usdc.balanceOf(taker);

        vm.prank(taker);
        IDelayedOrderCreditFacet(address(diamond)).withdrawQuoteCredit(address(usdc), CREDIT_AMOUNT);

        assertEq(usdc.balanceOf(taker), takerBefore + CREDIT_AMOUNT);
        assertEq(IDelayedOrderCreditFacet(address(diamond)).getQuoteCredit(taker, address(usdc)).withdrawable, 0);
    }

    function test_WithdrawBaseCreditThroughDelayedOrderFacet() public {
        conditionalTokens.mintPosition(address(diamond), POSITION_ID, CREDIT_AMOUNT);
        IDelayedOrderCreditSeederFacet(address(diamond))
            .creditBaseFixture(
                taker, uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), POSITION_ID, CREDIT_AMOUNT
            );

        vm.prank(taker);
        IDelayedOrderCreditFacet(address(diamond))
            .withdrawBaseCredit(
                uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), POSITION_ID, CREDIT_AMOUNT
            );

        assertEq(conditionalTokens.balanceOf(taker, POSITION_ID), CREDIT_AMOUNT);
        assertEq(
            IDelayedOrderCreditFacet(address(diamond))
            .getBaseCredit(taker, uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), POSITION_ID)
            .withdrawable,
            0
        );
    }

    function _delayedOrderCreditSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IDelayedOrderCreditFacet.withdrawQuoteCredit.selector;
        selectors[1] = IDelayedOrderCreditFacet.withdrawBaseCredit.selector;
        selectors[2] = IDelayedOrderCreditFacet.getQuoteCredit.selector;
        selectors[3] = IDelayedOrderCreditFacet.getBaseCredit.selector;
    }

    function _creditSeederSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IDelayedOrderCreditSeederFacet.creditQuoteFixture.selector;
        selectors[1] = IDelayedOrderCreditSeederFacet.creditBaseFixture.selector;
    }
}
