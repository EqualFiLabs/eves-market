// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ChainlinkETHUSDOracle} from "../../src/ChainlinkETHUSDOracle.sol";
import {IETHUSDOracle} from "../../src/interfaces/IETHUSDOracle.sol";
import {IUsdOracle} from "../../src/interfaces/IUsdOracle.sol";
import {MockETHUSDOracle} from "../../src/mocks/MockETHUSDOracle.sol";

contract ETHUSDOracleTest is Test {
    MockChainlinkETHUSDFeed internal feed;
    ChainlinkETHUSDOracle internal oracle;
    MockETHUSDOracle internal mockOracle;

    uint256 internal constant NOW = 1_700_000_000;
    uint256 internal constant MAX_STALENESS = 1 hours;
    uint256 internal constant MIN_PRICE_WAD = 100e18;
    uint256 internal constant MAX_PRICE_WAD = 10_000e18;
    uint256 internal constant SEQUENCER_GRACE_PERIOD = 1 hours;

    function setUp() public {
        vm.warp(NOW);
        feed = new MockChainlinkETHUSDFeed(8);
        feed.setRoundData(1, 2_500e8, NOW - 10 minutes, 1);
        oracle = _newOracle(address(feed), MIN_PRICE_WAD, MAX_PRICE_WAD, address(0), 0);
        mockOracle = new MockETHUSDOracle(2_500e18, MAX_STALENESS);
    }

    function test_ChainlinkAdapterNormalizesEightDecimalFeedToWad() public view {
        assertEq(oracle.ethUsdPriceWad(), 2_500e18);
        assertEq(oracle.feed(), address(feed));
        assertEq(oracle.feedDecimals(), 8);
        assertEq(oracle.maxStaleness(), MAX_STALENESS);
    }

    function test_ChainlinkAdapterReturnsEighteenDecimalFeedAsWad() public {
        MockChainlinkETHUSDFeed wadFeed = new MockChainlinkETHUSDFeed(18);
        wadFeed.setRoundData(1, 3_125e18, NOW - 1, 1);

        ChainlinkETHUSDOracle wadOracle = _newOracle(address(wadFeed), MIN_PRICE_WAD, MAX_PRICE_WAD, address(0), 0);

        assertEq(wadOracle.ethUsdPriceWad(), 3_125e18);
        assertEq(wadOracle.feedDecimals(), 18);
    }

    function test_RevertWhen_ChainlinkFeedIsZeroAddress() public {
        vm.expectRevert(ChainlinkETHUSDOracle.ZeroAddress.selector);
        _newOracle(address(0), MIN_PRICE_WAD, MAX_PRICE_WAD, address(0), 0);
    }

    function test_RevertWhen_MaxStalenessIsZero() public {
        vm.expectRevert(ChainlinkETHUSDOracle.InvalidMaxStaleness.selector);
        new ChainlinkETHUSDOracle(address(feed), 0, MIN_PRICE_WAD, MAX_PRICE_WAD, address(0), 0);
    }

    function test_RevertWhen_PriceBoundsAreInvalid() public {
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkETHUSDOracle.InvalidPriceBounds.selector, 3_000e18, 3_000e18)
        );
        _newOracle(address(feed), 3_000e18, 3_000e18, address(0), 0);
    }

    function test_RevertWhen_SequencerGracePeriodIsZeroForConfiguredFeed() public {
        MockChainlinkETHUSDFeed sequencer = new MockChainlinkETHUSDFeed(0);

        vm.expectRevert(ChainlinkETHUSDOracle.InvalidSequencerGracePeriod.selector);
        _newOracle(address(feed), MIN_PRICE_WAD, MAX_PRICE_WAD, address(sequencer), 0);
    }

    function test_RevertWhen_FeedDecimalsExceedWad() public {
        MockChainlinkETHUSDFeed highDecimalFeed = new MockChainlinkETHUSDFeed(19);

        vm.expectRevert(abi.encodeWithSelector(ChainlinkETHUSDOracle.UnsupportedFeedDecimals.selector, 19));
        _newOracle(address(highDecimalFeed), MIN_PRICE_WAD, MAX_PRICE_WAD, address(0), 0);
    }

    function test_RevertWhen_ChainlinkPriceIsZeroOrNegative() public {
        feed.setRoundData(2, 0, NOW - 10 minutes, 2);
        vm.expectRevert(IUsdOracle.InvalidPrice.selector);
        oracle.ethUsdPriceWad();

        feed.setRoundData(3, -1, NOW - 10 minutes, 3);
        vm.expectRevert(IUsdOracle.InvalidPrice.selector);
        oracle.ethUsdPriceWad();
    }

    function test_RevertWhen_ChainlinkRoundIsIncomplete() public {
        feed.setRoundData(3, 2_500e8, NOW - 10 minutes, 2);

        vm.expectRevert(IUsdOracle.InvalidPrice.selector);
        oracle.ethUsdPriceWad();
    }

    function test_RevertWhen_ChainlinkUpdatedAtIsZeroOrFuture() public {
        feed.setRoundData(2, 2_500e8, 0, 2);
        vm.expectRevert(IUsdOracle.InvalidPrice.selector);
        oracle.ethUsdPriceWad();

        feed.setRoundData(3, 2_500e8, NOW + 1, 3);
        vm.expectRevert(IUsdOracle.InvalidPrice.selector);
        oracle.ethUsdPriceWad();
    }

    function test_RevertWhen_ChainlinkPriceIsStale() public {
        uint256 updatedAt = NOW - MAX_STALENESS - 1;
        feed.setRoundData(2, 2_500e8, updatedAt, 2);

        vm.expectRevert(abi.encodeWithSelector(IUsdOracle.StalePrice.selector, updatedAt, MAX_STALENESS));
        oracle.ethUsdPriceWad();
    }

    function test_RevertWhen_ChainlinkPriceTouchesConfiguredBounds() public {
        feed.setRoundData(2, 100e8, NOW - 10 minutes, 2);
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkETHUSDOracle.PriceOutOfBounds.selector, 100e18, MIN_PRICE_WAD, MAX_PRICE_WAD)
        );
        oracle.ethUsdPriceWad();

        feed.setRoundData(3, 10_000e8, NOW - 10 minutes, 3);
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkETHUSDOracle.PriceOutOfBounds.selector, 10_000e18, MIN_PRICE_WAD, MAX_PRICE_WAD
            )
        );
        oracle.ethUsdPriceWad();
    }

    function test_SequencerUptimeFeedAllowsPriceAfterGracePeriod() public {
        MockChainlinkETHUSDFeed sequencer = new MockChainlinkETHUSDFeed(0);
        sequencer.setRoundData(1, 0, NOW - SEQUENCER_GRACE_PERIOD - 1, 1);
        ChainlinkETHUSDOracle baseOracle =
            _newOracle(address(feed), MIN_PRICE_WAD, MAX_PRICE_WAD, address(sequencer), SEQUENCER_GRACE_PERIOD);

        assertEq(baseOracle.ethUsdPriceWad(), 2_500e18);
    }

    function test_RevertWhen_SequencerIsDown() public {
        MockChainlinkETHUSDFeed sequencer = new MockChainlinkETHUSDFeed(0);
        sequencer.setRoundData(1, 1, NOW - SEQUENCER_GRACE_PERIOD - 1, 1);
        ChainlinkETHUSDOracle baseOracle =
            _newOracle(address(feed), MIN_PRICE_WAD, MAX_PRICE_WAD, address(sequencer), SEQUENCER_GRACE_PERIOD);

        vm.expectRevert(ChainlinkETHUSDOracle.SequencerDown.selector);
        baseOracle.ethUsdPriceWad();
    }

    function test_RevertWhen_SequencerGracePeriodIsActive() public {
        MockChainlinkETHUSDFeed sequencer = new MockChainlinkETHUSDFeed(0);
        sequencer.setRoundData(1, 0, NOW - 30 minutes, 1);
        ChainlinkETHUSDOracle baseOracle =
            _newOracle(address(feed), MIN_PRICE_WAD, MAX_PRICE_WAD, address(sequencer), SEQUENCER_GRACE_PERIOD);

        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkETHUSDOracle.SequencerGracePeriodActive.selector, NOW - 30 minutes, SEQUENCER_GRACE_PERIOD
            )
        );
        baseOracle.ethUsdPriceWad();
    }

    function test_MockOracleReturnsConfigurablePrice() public {
        assertEq(mockOracle.ethUsdPriceWad(), 2_500e18);

        mockOracle.setPriceWad(3_000e18);

        assertEq(mockOracle.ethUsdPriceWad(), 3_000e18);
    }

    function test_MockOracleSupportsConfigurableInvalidPriceFailure() public {
        mockOracle.setInvalidPrice(true);

        vm.expectRevert(IUsdOracle.InvalidPrice.selector);
        mockOracle.ethUsdPriceWad();
    }

    function test_MockOracleRejectsZeroPrice() public {
        mockOracle.setPriceWad(0);

        vm.expectRevert(IUsdOracle.InvalidPrice.selector);
        mockOracle.ethUsdPriceWad();
    }

    function test_MockOracleSupportsConfigurableStalePriceFailure() public {
        mockOracle.setStalePrice(true);

        vm.expectRevert(abi.encodeWithSelector(IUsdOracle.StalePrice.selector, NOW, MAX_STALENESS));
        mockOracle.ethUsdPriceWad();
    }

    function test_MockOracleRejectsStaleUpdatedAt() public {
        uint256 updatedAt = NOW - MAX_STALENESS - 1;
        mockOracle.setUpdatedAt(updatedAt);

        vm.expectRevert(abi.encodeWithSelector(IUsdOracle.StalePrice.selector, updatedAt, MAX_STALENESS));
        mockOracle.ethUsdPriceWad();
    }

    function _newOracle(
        address feed_,
        uint256 minPriceWad_,
        uint256 maxPriceWad_,
        address sequencerUptimeFeed_,
        uint256 sequencerGracePeriod_
    ) internal returns (ChainlinkETHUSDOracle) {
        return new ChainlinkETHUSDOracle(
            feed_,
            MAX_STALENESS,
            minPriceWad_,
            maxPriceWad_,
            sequencerUptimeFeed_,
            sequencerGracePeriod_
        );
    }
}

contract MockChainlinkETHUSDFeed {
    uint8 public immutable decimals;
    uint80 internal roundId;
    int256 internal answer;
    uint256 internal updatedAt;
    uint80 internal answeredInRound;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setRoundData(uint80 roundId_, int256 answer_, uint256 updatedAt_, uint80 answeredInRound_) external {
        roundId = roundId_;
        answer = answer_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId_, int256 answer_, uint256 startedAt_, uint256 updatedAt_, uint80 answeredInRound_)
    {
        return (roundId, answer, updatedAt, updatedAt, answeredInRound);
    }
}
