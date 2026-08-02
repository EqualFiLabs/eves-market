// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {CurveCLOBFacet} from "../../src/facets/CurveCLOBFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {FeeRouterFacet} from "../../src/facets/FeeRouterFacet.sol";
import {MarketFactoryFacet} from "../../src/facets/MarketFactoryFacet.sol";
import {MarketViewFacet} from "../../src/facets/MarketViewFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {EveUSDC} from "../../src/EveUSDC.sol";
import {SEveUSDCVault} from "../../src/SEveUSDCVault.sol";

import {DiamondFixture, StateProbeFacet} from "./DiamondFixtures.sol";
import {MockConditionalTokens} from "./MockConditionalTokens.sol";
import {MockEveToken} from "./MockEveToken.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

abstract contract VaultFeeRoutingFixture is DiamondFixture {
    uint256 internal constant USDC_UNIT = 1e6;
    uint256 internal constant EVEUSDC_UNIT = 1e18;
    uint256 internal constant USDC_TO_EVEUSDC_SCALE = 1e12;
    uint256 internal constant FEE_BPS_DENOMINATOR = 10_000;
    uint256 internal constant MAKER_FEE_BPS = 8_500;
    uint256 internal constant CREATOR_FEE_BPS = 500;
    uint256 internal constant PROTOCOL_FEE_BPS = 1_000;

    uint128 internal constant DEFAULT_CREATION_FEE = 50e18;
    uint128 internal constant DEFAULT_CREATION_BOND_EVE = 100e18;
    uint16 internal constant DEFAULT_FILL_FEE_RATE = 500;
    uint72 internal constant DEFAULT_FLAT_PRICE = 500_000_000;
    uint128 internal constant DEFAULT_MAKER_INVENTORY = 10_000e18;
    uint128 internal constant DEFAULT_FILL_COLLATERAL = 4_200e18;

    address internal creator;
    address internal maker;
    address internal taker;
    address internal treasury;
    address internal staker;
    address internal vaultFeeRecipient;

    MockConditionalTokens internal conditionalTokens;
    MockUSDC internal usdc;
    EveUSDC internal eveUSDC;
    MockEveToken internal eveToken;
    SEveUSDCVault internal vault;

    MarketFactoryFacet internal marketFactoryFacet;
    MarketViewFacet internal marketViewFacet;
    CurveCLOBFacet internal curveCLOBFacet;
    FeeRouterFacet internal feeRouterFacet;

    function setUp() public virtual override {
        super.setUp();

        creator = makeAddr("vault-creator");
        maker = makeAddr("vault-maker");
        taker = makeAddr("vault-taker");
        treasury = makeAddr("vault-treasury");
        staker = makeAddr("vault-staker");
        vaultFeeRecipient = makeAddr("vault-fee-recipient");

        conditionalTokens = new MockConditionalTokens();
        usdc = new MockUSDC();
        eveUSDC = new EveUSDC(address(usdc), address(this), address(this));
        eveToken = new MockEveToken();
        vault = new SEveUSDCVault(address(eveUSDC), owner, vaultFeeRecipient, 0, address(diamond));

        marketFactoryFacet = new MarketFactoryFacet();
        marketViewFacet = new MarketViewFacet();
        curveCLOBFacet = new CurveCLOBFacet();
        feeRouterFacet = new FeeRouterFacet();

        _addFacet(address(marketFactoryFacet), _marketFactorySelectors());
        _addFacet(address(marketViewFacet), _marketViewSelectors());
        _addCurveFacets();
        _addFacet(address(feeRouterFacet), _feeRouterSelectors());

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(address(conditionalTokens));
        OwnershipFacet(address(diamond)).setCollateralToken(address(eveUSDC));
        OwnershipFacet(address(diamond)).setEveToken(address(eveToken));
        OwnershipFacet(address(diamond)).setResolutionBondConfig(address(eveToken), 0.1 ether, 0.5 ether);
        OwnershipFacet(address(diamond)).setEveTreasury(treasury);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(DEFAULT_FILL_FEE_RATE);
        OwnershipFacet(address(diamond)).setMarketCreationFee(DEFAULT_CREATION_FEE);
        OwnershipFacet(address(diamond)).setMarketCreationBond(DEFAULT_CREATION_BOND_EVE);
        OwnershipFacet(address(diamond)).setMarketCreationBatchCap(24);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(true);
        OwnershipFacet(address(diamond)).setDurationParams(1 hours, 90 days);
        OwnershipFacet(address(diamond)).setDisputeWindow(2 hours);
        OwnershipFacet(address(diamond)).setCreatorSettleGrace(1 days);
        OwnershipFacet(address(diamond)).setOpenResolutionTimeout(2 days);
        OwnershipFacet(address(diamond)).setMaxEscalation(2);
        vm.stopPrank();

        eveToken.mint(creator, 20_000e18);
        _wrapFor(creator, 10_000_000e6);
        _wrapFor(maker, 10_000_000e6);
        _wrapFor(taker, 10_000_000e6);
        _wrapFor(staker, 10_000_000e6);

        vm.prank(creator);
        eveUSDC.approve(address(diamond), type(uint256).max);
        vm.prank(creator);
        eveToken.approve(address(diamond), type(uint256).max);
        vm.prank(maker);
        eveUSDC.approve(address(diamond), type(uint256).max);
        vm.prank(taker);
        eveUSDC.approve(address(diamond), type(uint256).max);
        vm.prank(staker);
        eveUSDC.approve(address(vault), type(uint256).max);
    }

    function _marketFactorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = bytes4(
            keccak256(
                "createMarket((string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
            )
        );
        selectors[1] = IMarketFactoryFacet.createMarkets.selector;
        selectors[2] = bytes4(
            keccak256(
                "createMarketGroup(((string,string,uint8,string,(uint8,string,string,string,string,bytes32)),((string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)),(string,string,int32,uint8))[]))"
            )
        );
        selectors[3] = MarketFactoryFacet.syncMarketState.selector;
        selectors[4] = bytes4(
            keccak256(
                "createMarketWithCollateralProfile(uint8,(string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
            )
        );
        selectors[5] = bytes4(keccak256("createMarket(string,string,string,uint64,uint64,uint128,bool)"));
        selectors[6] = bytes4(
            keccak256(
                "createMarketGroup(string,(string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32))[])"
            )
        );
        selectors[7] = bytes4(
            keccak256("createMarketWithCollateralProfile(uint8,string,string,string,uint64,uint64,uint128,bool)")
        );
        selectors[8] = bytes4(
            keccak256(
                "createMarketGroupFromExisting(((string,string,uint8,string,(uint8,string,string,string,string,bytes32)),(bytes32,(string,string,int32,uint8))[]))"
            )
        );
        selectors[9] = bytes4(keccak256("addMarketsToGroup(bytes32,(bytes32,(string,string,int32,uint8))[])"));
    }

    function _marketViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](19);
        selectors[0] = IMarketFactoryFacet.getMarketPositions.selector;
        selectors[1] = IMarketFactoryFacet.getMarketInfo.selector;
        selectors[2] = IMarketFactoryFacet.getMarketSummaries.selector;
        selectors[3] = IMarketFactoryFacet.getMarketConfig.selector;
        selectors[4] = IMarketFactoryFacet.getUserMarketPositions.selector;
        selectors[5] = IMarketFactoryFacet.getMarketMetadata.selector;
        selectors[6] = IMarketFactoryFacet.getPositionMetadata.selector;
        selectors[7] = IMarketFactoryFacet.positionTokenURI.selector;
        selectors[8] = IMarketFactoryFacet.computeMarketId.selector;
        selectors[9] = IMarketFactoryFacet.getMarketTokenInfo.selector;
        selectors[10] = IMarketFactoryFacet.getCollateralProfile.selector;
        selectors[11] = IMarketFactoryFacet.getCollateralProfileParimutuelConfig.selector;
        selectors[12] = IMarketFactoryFacet.getCollateralProfileParlayUnderwritingFee.selector;
        selectors[13] = IMarketFactoryFacet.computeProfileMarketId.selector;
        selectors[14] = IMarketFactoryFacet.getMarketDisplay.selector;
        selectors[15] = IMarketFactoryFacet.getMarketExternalRef.selector;
        selectors[16] = IMarketFactoryFacet.getMarketGroup.selector;
        selectors[17] = IMarketFactoryFacet.getMarketGroupMarkets.selector;
        selectors[18] = IMarketFactoryFacet.getGroupMarketDisplay.selector;
    }

    function _addCurveFacets() internal {
        _addFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        _addFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        _addFacet(address(curveCLOBFacet), _curveTradeSelectors());
        _addFacet(address(new CurveViewFacet()), _curveViewSelectors());
        _addFacet(address(new BookFacet()), _bookSelectors());
        _addFacet(address(new BookOrderFacet()), _bookOrderSelectors());
    }

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
        selectors[1] = ICurveInventoryFacet.mergeInventory.selector;
    }

    function _curveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ICurveLifecycleFacet.postCurve.selector;
        selectors[1] = ICurveLifecycleFacet.postBidCurve.selector;
        selectors[2] = ICurveLifecycleFacet.postBidCurvesBatch.selector;
        selectors[3] = ICurveLifecycleFacet.postBidCurveWithUSDC.selector;
    }

    function _curveTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
        selectors[1] = ICurveTradeFacet.fillBest.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[1] = ICurveViewFacet.previewCurveQuote.selector;
        selectors[2] = ICurveViewFacet.previewBestExecution.selector;
        selectors[3] = ICurveViewFacet.getCurveInfo.selector;
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookAdminFacet.createBook.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
    }

    function _feeRouterSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = FeeRouterFacet.claimCreatorFees.selector;
        selectors[1] = FeeRouterFacet.claimMakerFees.selector;
        selectors[2] = FeeRouterFacet.previewMakerFees.selector;
        selectors[3] = FeeRouterFacet.getMakerMarketAccounting.selector;
        selectors[4] = FeeRouterFacet.configureMarketMakerRewards.selector;
        selectors[5] = FeeRouterFacet.fundMarketMakerRewards.selector;
        selectors[6] = FeeRouterFacet.claimMarketMakerRewards.selector;
        selectors[7] = FeeRouterFacet.previewMarketMakerRewards.selector;
    }

    function _wrapFor(address account, uint256 amount) internal {
        usdc.mint(account, amount);

        vm.startPrank(account);
        usdc.approve(address(eveUSDC), amount);
        eveUSDC.wrap(amount, account);
        vm.stopPrank();
    }

    function _configureVaultRouting(address stakingVault, uint16 vaultFeeBps) internal {
        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setStakingVault(stakingVault);
        OwnershipFacet(address(diamond))
            .setOrderbookFeeSplit(
                uint16(MAKER_FEE_BPS), uint16(CREATOR_FEE_BPS), uint16(PROTOCOL_FEE_BPS - vaultFeeBps), vaultFeeBps
            );
        vm.stopPrank();
    }

    function _depositStake(uint256 assets) internal returns (uint256 shares) {
        vm.prank(staker);
        shares = vault.deposit(assets, staker);
    }

    function _createTradingMarket(string memory question, uint64 duration)
        internal
        returns (bytes32 marketId, uint64 expiryTime)
    {
        expiryTime = uint64(block.timestamp) + duration;

        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                question, "vault-routing", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true
            );
    }

    function _splitFromMaker(bytes32 marketId, uint128 collateralAmount) internal returns (uint128 sharesMinted) {
        vm.prank(maker);
        sharesMinted = ICurveInventoryFacet(address(diamond)).splitInventory(marketId, collateralAmount);
    }

    function _approvePositions(address account) internal {
        vm.prank(account);
        conditionalTokens.setApprovalForAll(address(diamond), true);
    }

    function _postCurveFromMaker(
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes
    ) internal returns (uint256 curveId) {
        vm.prank(maker);
        curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(
                marketId,
                isYesSide,
                volume,
                startPrice,
                endPrice,
                durationMinutes,
                0,
                LibEveMarket.PositionTokenType.CTF
            );
    }

    function _fillCurveFromTaker(uint256 curveId, uint128 collateralIn)
        internal
        returns (uint128 sharesOut, uint128 fee, uint128 price)
    {
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares, uint128 previewFee, uint128 previewPrice,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, collateralIn);

        vm.prank(taker);
        sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, collateralIn, 0, generation, commitment);

        assertEq(sharesOut, previewShares);
        fee = previewFee;
        price = previewPrice;
    }

    function _createFilledMarket(string memory question, uint16 vaultRevenueBps)
        internal
        returns (bytes32 marketId, uint256 curveId, uint128 fee)
    {
        _configureVaultRouting(address(vault), vaultRevenueBps);
        (marketId,) = _createTradingMarket(question, 7 days);
        _splitFromMaker(marketId, DEFAULT_MAKER_INVENTORY);
        _approvePositions(maker);
        curveId =
            _postCurveFromMaker(marketId, true, DEFAULT_MAKER_INVENTORY, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (, fee,) = _fillCurveFromTaker(curveId, DEFAULT_FILL_COLLATERAL);
    }

    function _makerShare(uint128 fee) internal pure returns (uint128) {
        return uint128((uint256(fee) * MAKER_FEE_BPS) / FEE_BPS_DENOMINATOR);
    }

    function _creatorShare(uint128 fee) internal pure returns (uint128) {
        return uint128((uint256(fee) * CREATOR_FEE_BPS) / FEE_BPS_DENOMINATOR);
    }

    function _protocolShare(uint128 fee) internal pure returns (uint128) {
        return fee - _makerShare(fee) - _creatorShare(fee);
    }

    function _vaultShare(uint128 fee, uint16 vaultFeeBps) internal pure returns (uint128) {
        return uint128((uint256(fee) * vaultFeeBps) / FEE_BPS_DENOMINATOR);
    }

    function _treasuryShare(uint128 fee, uint16 vaultFeeBps) internal pure returns (uint128) {
        return fee - _makerShare(fee) - _creatorShare(fee) - _vaultShare(fee, vaultFeeBps);
    }

    function _marketConfig() internal view returns (MarketFactoryTypes.MarketConfigView memory) {
        return IMarketFactoryFacet(address(diamond)).getMarketConfig();
    }

    function _storedMarketFees(bytes32 marketId)
        internal
        view
        returns (
            uint128 creatorFeesEscrowed,
            uint128 protocolFeesAccrued,
            bool creatorFeesClaimed,
            bool creatorFeeEligible
        )
    {
        return StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
    }
}
