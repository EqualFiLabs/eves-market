// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {IFeeRouterFacet} from "../interfaces/IFeeRouterFacet.sol";

contract FeeRouterFacet is IFeeRouterFacet {
    using SafeERC20 for IERC20;

    uint16 internal constant MAX_REWARD_RATE_BPS = 10_000;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function claimCreatorFees(bytes32 marketId) external nonReentrant {
        LibEveMarket.Market storage market = _loadMarket(marketId);

        if (market.state != LibEveMarket.MarketState.Resolved) {
            revert Errors.MarketNotResolved(marketId);
        }
        if (msg.sender != market.creator) {
            revert Errors.NotMarketCreator(msg.sender, market.creator);
        }
        if (!market.creatorFeeEligible) {
            revert Errors.CreatorNotEligible(marketId);
        }
        if (market.creatorFeesClaimed) {
            revert Errors.AlreadyClaimed(marketId, msg.sender);
        }

        uint128 amount = market.creatorFeesEscrowed;
        if (amount == 0) {
            revert Errors.NoFeesAccrued(marketId);
        }

        market.creatorFeesClaimed = true;
        market.creatorFeesEscrowed = 0;

        IERC20(market.collateralToken).safeTransfer(msg.sender, amount);
        emit Events.CreatorFeesClaimed(marketId, amount);
    }

    function claimMakerFees(bytes32 marketId) external nonReentrant {
        LibEveMarket.Market storage market = _loadMarket(marketId);

        uint128 accrued = market.makerFeesAccrued[msg.sender];
        uint128 claimed = market.makerFeesClaimed[msg.sender];
        uint128 claimable = accrued - claimed;

        market.makerFeesClaimed[msg.sender] = accrued;

        if (claimable != 0) {
            IERC20(market.collateralToken).safeTransfer(msg.sender, claimable);
        }

        emit Events.MakerFeesClaimed(marketId, msg.sender, claimable);
    }

    function configureMarketMakerRewards(bytes32 marketId, uint16 rewardRateBps) external {
        LibEveMarket.Market storage market = _loadMarket(marketId);
        _enforceMarketRewardController(market);

        if (market.marketType != LibEveMarket.MarketType.CLOB) {
            revert Errors.NotCLOBMarket(marketId);
        }
        if (rewardRateBps == 0 || rewardRateBps > MAX_REWARD_RATE_BPS) {
            revert Errors.InvalidAmount(rewardRateBps);
        }
        if (market.makerRewardsRemaining != 0) {
            revert Errors.InvalidAmount(market.makerRewardsRemaining);
        }

        market.makerRewardRateBps = rewardRateBps;

        emit Events.MarketMakerRewardsConfigured(marketId, market.collateralToken, rewardRateBps);
    }

    function fundMarketMakerRewards(bytes32 marketId, uint128 amount) external nonReentrant {
        LibEveMarket.Market storage market = _loadMarket(marketId);

        if (market.makerRewardRateBps == 0) {
            revert Errors.InvalidAmount(0);
        }
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }

        market.makerRewardsRemaining += amount;

        IERC20(market.collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        emit Events.MarketMakerRewardsFunded(
            marketId, msg.sender, market.collateralToken, amount, market.makerRewardsRemaining
        );
    }

    function claimMarketMakerRewards(bytes32 marketId) external nonReentrant {
        LibEveMarket.Market storage market = _loadMarket(marketId);

        uint128 claimable = market.makerRewardsClaimable[msg.sender];
        market.makerRewardsClaimable[msg.sender] = 0;

        if (claimable != 0) {
            IERC20(market.collateralToken).safeTransfer(msg.sender, claimable);
        }

        emit Events.MarketMakerRewardsClaimed(marketId, msg.sender, market.collateralToken, claimable);
    }

    function claimBookCreatorFees(bytes32 bookId) external nonReentrant {
        LibEveMarket.Book storage book = _loadBookFeeAccount(bookId);

        if (msg.sender != book.creator) {
            revert Errors.NotMarketCreator(msg.sender, book.creator);
        }

        uint128 amount = book.creatorFeesEscrowed;
        if (amount == 0) {
            revert Errors.NoFeesAccrued(bookId);
        }

        book.creatorFeesClaimed = true;
        book.creatorFeesEscrowed = 0;

        IERC20(book.quoteToken).safeTransfer(msg.sender, amount);
        emit Events.BookCreatorFeesClaimed(bookId, msg.sender, amount);
    }

    function claimBookMakerFees(bytes32 bookId) external nonReentrant {
        LibEveMarket.Book storage book = _loadBookFeeAccount(bookId);

        uint128 accrued = book.makerFeesAccrued[msg.sender];
        uint128 claimed = book.makerFeesClaimed[msg.sender];
        uint128 claimable = accrued - claimed;

        book.makerFeesClaimed[msg.sender] = accrued;

        if (claimable != 0) {
            IERC20(book.quoteToken).safeTransfer(msg.sender, claimable);
        }

        emit Events.BookMakerFeesClaimed(bookId, msg.sender, claimable);
    }

    function previewMakerFees(bytes32 marketId, address maker)
        external
        view
        returns (uint128 accrued, uint128 claimed, uint128 claimable)
    {
        LibEveMarket.Market storage market = _loadMarket(marketId);

        accrued = market.makerFeesAccrued[maker];
        claimed = market.makerFeesClaimed[maker];
        claimable = accrued - claimed;
    }

    function getMakerMarketAccounting(bytes32 marketId, address maker)
        external
        view
        returns (uint128 quoteVolume, uint128 accrued, uint128 claimed, uint128 claimable)
    {
        LibEveMarket.Market storage market = _loadMarket(marketId);

        quoteVolume = market.makerQuoteVolume[maker];
        accrued = market.makerFeesAccrued[maker];
        claimed = market.makerFeesClaimed[maker];
        claimable = accrued - claimed;
    }

    function previewMarketMakerRewards(bytes32 marketId, address maker)
        external
        view
        returns (address rewardToken, uint16 rewardRateBps, uint128 rewardsRemaining, uint128 claimable)
    {
        LibEveMarket.Market storage market = _loadMarket(marketId);

        rewardToken = market.collateralToken;
        rewardRateBps = market.makerRewardRateBps;
        rewardsRemaining = market.makerRewardsRemaining;
        claimable = market.makerRewardsClaimable[maker];
    }

    function previewBookMakerFees(bytes32 bookId, address maker)
        external
        view
        returns (uint128 accrued, uint128 claimed, uint128 claimable)
    {
        LibEveMarket.Book storage book = _loadBookFeeAccount(bookId);

        accrued = book.makerFeesAccrued[maker];
        claimed = book.makerFeesClaimed[maker];
        claimable = accrued - claimed;
    }

    function getMakerBookAccounting(bytes32 bookId, address maker)
        external
        view
        returns (uint128 quoteVolume, uint128 accrued, uint128 claimed, uint128 claimable)
    {
        LibEveMarket.Book storage book = _loadBookFeeAccount(bookId);

        quoteVolume = book.makerQuoteVolume[maker];
        accrued = book.makerFeesAccrued[maker];
        claimed = book.makerFeesClaimed[maker];
        claimable = accrued - claimed;
    }

    function _loadMarket(bytes32 marketId) internal view returns (LibEveMarket.Market storage market) {
        market = LibEveMarket.store().markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
    }

    function _loadBookFeeAccount(bytes32 bookId) internal view returns (LibEveMarket.Book storage book) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        book = state.books[bookId];
        if (book.bookId != bookId) {
            revert Errors.BookNotFound(bookId);
        }
        if (book.marketId != bytes32(0) && !state.comboMarkets[book.marketId].exists) {
            revert Errors.InvalidAmount(uint256(book.marketId));
        }
    }

    function _enforceMarketRewardController(LibEveMarket.Market storage market) internal view {
        address owner = LibDiamond.contractOwner();
        if (msg.sender != market.creator && msg.sender != owner) {
            revert Errors.NotMarketCreator(msg.sender, market.creator);
        }
    }
}
