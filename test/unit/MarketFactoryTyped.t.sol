// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {CurveTradingFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract MarketFactoryTypedTest is CurveTradingFixture {
    struct TypedMarketSetup {
        bytes32 clobMarketId;
        bytes32 parimutuelMarketId;
        MockConditionalTokens parimutuelPositionToken;
    }

    function test_CLOBMarketCreationStoresTypeAndPositionToken() public {
        (bytes32 marketId,,) = _createTradingMarket("typed clob storage", "market-factory-typed", 7 days);

        (uint8 marketType, address positionToken) =
            StateProbeFacet(address(diamond)).getStoredMarketTypeAndPositionToken(marketId);

        assertEq(marketType, uint8(LibEveMarket.MarketType.CLOB));
        assertEq(positionToken, address(conditionalTokens));
    }

    function test_GetUserMarketPositionsQueriesPositionTokenPerMarketType() public {
        TypedMarketSetup memory setup = _setupTypedMarkets();
        bytes32[] memory marketIds = _marketIdList(setup.clobMarketId, setup.parimutuelMarketId);

        (uint256[] memory yesBalances, uint256[] memory noBalances) =
            IMarketFactoryFacet(address(diamond)).getUserMarketPositions(maker, marketIds);

        assertEq(yesBalances.length, 2);
        assertEq(noBalances.length, 2);
        assertEq(yesBalances[0], 77);
        assertEq(noBalances[0], 77);
        assertEq(yesBalances[1], 321);
        assertEq(noBalances[1], 123);
    }

    function test_GetMarketSummariesQueriesPositionTokenPerMarketType() public {
        TypedMarketSetup memory setup = _setupTypedMarkets();
        bytes32[] memory marketIds = _marketIdList(setup.clobMarketId, setup.parimutuelMarketId);

        MarketFactoryTypes.MarketSummary[] memory summaries =
            IMarketFactoryFacet(address(diamond)).getMarketSummaries(maker, marketIds);

        assertEq(summaries.length, 2);
        assertEq(summaries[0].marketInfo.marketId, setup.clobMarketId);
        assertEq(summaries[0].yesBalance, 77);
        assertEq(summaries[0].noBalance, 77);
        assertEq(summaries[1].marketInfo.marketId, setup.parimutuelMarketId);
        assertEq(summaries[1].yesBalance, 321);
        assertEq(summaries[1].noBalance, 123);
    }

    function _setupTypedMarkets() internal returns (TypedMarketSetup memory setup) {
        (setup.clobMarketId,,) = _createTradingMarket("typed clob balance", "market-factory-typed", 7 days);
        _splitFrom(maker, setup.clobMarketId, 77);

        (setup.parimutuelMarketId,,) = _createTradingMarket("typed parimutuel balance", "market-factory-typed", 8 days);
        setup.parimutuelPositionToken = new MockConditionalTokens();

        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(setup.parimutuelMarketId);
        setup.parimutuelPositionToken.mintPosition(maker, yesPositionId, 321);
        setup.parimutuelPositionToken.mintPosition(maker, noPositionId, 123);

        ResolutionHarnessFacet(address(diamond))
            .setMarketTypeAndPositionToken(
                setup.parimutuelMarketId,
                uint256(uint8(LibEveMarket.MarketType.PARIMUTUEL)),
                address(setup.parimutuelPositionToken)
            );

        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), 0);
        assertEq(conditionalTokens.balanceOf(maker, noPositionId), 0);
    }

    function _marketIdList(bytes32 firstMarketId, bytes32 secondMarketId)
        internal
        pure
        returns (bytes32[] memory marketIds)
    {
        marketIds = new bytes32[](2);
        marketIds[0] = firstMarketId;
        marketIds[1] = secondMarketId;
    }
}
