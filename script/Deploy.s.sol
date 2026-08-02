// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {stdJson} from "../lib/forge-std/src/StdJson.sol";

import {EveMarketDiamond} from "../src/EveMarketDiamond.sol";
import {EveUSDC} from "../src/EveUSDC.sol";
import {Faucet} from "../src/Faucet.sol";
import {MakerLendingRouter} from "../src/MakerLendingRouter.sol";
import {SEveUSDCLending} from "../src/SEveUSDCLending.sol";
import {SEveUSDCVault} from "../src/SEveUSDCVault.sol";
import {CanonicalWETH9} from "../src/mocks/CanonicalWETH9.sol";
import {BondManagerFacet} from "../src/facets/BondManagerFacet.sol";
import {BondTokenGateFacet} from "../src/facets/BondTokenGateFacet.sol";
import {CurveCLOBFacet} from "../src/facets/CurveCLOBFacet.sol";
import {CurveInventoryFacet} from "../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../src/facets/CurveViewFacet.sol";
import {DelayedOrderFacet} from "../src/facets/DelayedOrderFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {FeeRouterFacet} from "../src/facets/FeeRouterFacet.sol";
import {MarketFactoryFacet} from "../src/facets/MarketFactoryFacet.sol";
import {MarketSettlementFacet} from "../src/facets/MarketSettlementFacet.sol";
import {MarketViewFacet} from "../src/facets/MarketViewFacet.sol";
import {MultiOutcomeOrderbookFacet} from "../src/facets/MultiOutcomeOrderbookFacet.sol";
import {MultiOutcomeOrderbookViewFacet} from "../src/facets/MultiOutcomeOrderbookViewFacet.sol";
import {ComboBranchFacet} from "../src/facets/native/ComboBranchFacet.sol";
import {ComboCoreFacet} from "../src/facets/native/ComboCoreFacet.sol";
import {ComboSettlementFacet} from "../src/facets/native/ComboSettlementFacet.sol";
import {ComboViewFacet} from "../src/facets/native/ComboViewFacet.sol";
import {NativeBinaryPositionFacet} from "../src/facets/native/NativeBinaryPositionFacet.sol";
import {ComboMarketFacet} from "../src/facets/native/ComboMarketFacet.sol";
import {OBRResolutionFacet} from "../src/facets/OBRResolutionFacet.sol";
import {OwnershipFacet} from "../src/facets/OwnershipFacet.sol";
import {ParimutuelFacet} from "../src/facets/ParimutuelFacet.sol";
import {ResolverJuryFacet} from "../src/facets/ResolverJuryFacet.sol";
import {ResolverRegistryFacet} from "../src/facets/ResolverRegistryFacet.sol";
import {ParlayAdminFacet} from "../src/facets/parlay/ParlayAdminFacet.sol";
import {ParlayBookFacet} from "../src/facets/parlay/ParlayBookFacet.sol";
import {ParlayBudgetFacet} from "../src/facets/parlay/ParlayBudgetFacet.sol";
import {ParlayMulticallFacet} from "../src/facets/parlay/ParlayMulticallFacet.sol";
import {ParlaySettlementFacet} from "../src/facets/parlay/ParlaySettlementFacet.sol";
import {ParlayUnderwritingFacet} from "../src/facets/parlay/ParlayUnderwritingFacet.sol";
import {ParlayViewFacet} from "../src/facets/parlay/ParlayViewFacet.sol";
import {BookFacet} from "../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../src/facets/BookTradeFacet.sol";
import {BookViewFacet} from "../src/facets/BookViewFacet.sol";
import {TradeRouterFacet} from "../src/facets/TradeRouterFacet.sol";
import {VaultRouterFacet} from "../src/facets/VaultRouterFacet.sol";
import {IBondManagerFacet} from "../src/interfaces/IBondManagerFacet.sol";
import {IBondTokenGateFacet} from "../src/interfaces/IBondTokenGateFacet.sol";
import {IBookAdminFacet} from "../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../src/interfaces/ICurveViewFacet.sol";
import {IFeeRouterFacet} from "../src/interfaces/IFeeRouterFacet.sol";
import {IMarketFactoryFacet} from "../src/interfaces/IMarketFactoryFacet.sol";
import {IMarketSettlementFacet} from "../src/interfaces/IMarketSettlementFacet.sol";
import {IMultiOutcomeOrderbookFacet} from "../src/interfaces/IMultiOutcomeOrderbookFacet.sol";
import {IComboBranchFacet} from "../src/interfaces/IComboBranchFacet.sol";
import {IComboCoreFacet} from "../src/interfaces/IComboCoreFacet.sol";
import {IComboSettlementFacet} from "../src/interfaces/IComboSettlementFacet.sol";
import {IComboViewFacet} from "../src/interfaces/IComboViewFacet.sol";
import {INativeBinaryPositionFacet} from "../src/interfaces/INativeBinaryPositionFacet.sol";
import {IComboMarketFacet} from "../src/interfaces/IComboMarketFacet.sol";
import {IOBRResolutionFacet} from "../src/interfaces/IOBRResolutionFacet.sol";
import {IParimutuelFacet} from "../src/interfaces/IParimutuelFacet.sol";
import {IResolverJuryFacet} from "../src/interfaces/IResolverJuryFacet.sol";
import {IResolverRegistryFacet} from "../src/interfaces/IResolverRegistryFacet.sol";
import {ITradeRouter} from "../src/interfaces/ITradeRouter.sol";
import {IVaultRouter} from "../src/interfaces/IVaultRouter.sol";
import {ResolverJuryInit} from "../src/init/ResolverJuryInit.sol";
import {LibEveUSDCUnits} from "../src/libraries/LibEveUSDCUnits.sol";
import {LibEveMarket} from "../src/libraries/LibEveMarket.sol";
import {ParlayTypes} from "../src/types/ParlayTypes.sol";
import {OwnershipConfigTypes} from "../src/types/OwnershipConfigTypes.sol";
import {ParimutuelShareToken} from "../src/tokens/ParimutuelShareToken.sol";
import {EveIdentity} from "../src/tokens/EveIdentity.sol";
import {EveETH} from "../src/tokens/EveETH.sol";
import {EvesPositionManager} from "../src/tokens/EvesPositionManager.sol";
import {ParlayTicketToken} from "../src/tokens/ParlayTicketToken.sol";
import {MockEveToken} from "../test/helpers/MockEveToken.sol";
import {MockUSDC} from "../test/helpers/MockUSDC.sol";
import {MarketFactoryTypes} from "../src/types/MarketFactoryTypes.sol";

contract DeployScript is Script {
    using SafeERC20 for IERC20;
    using stdJson for string;

    string internal constant DEFAULT_CONDITIONAL_TOKENS_ARTIFACT_PATH =
        "../../conditional-tokens-contracts/out/ConditionalTokens.sol/ConditionalTokens.json";
    uint8 internal constant EVE_ETH_PROFILE_ID = 1;

    struct DeploymentConfig {
        address owner;
        address conditionalTokens;
        string conditionalTokensArtifactPath;
        address collateralToken;
        address eveToken;
        address eveTreasury;
        address stakingVault;
        address evesPositionManager;
        address parimutuelShareToken;
        address parlayTicketToken;
        address parlayFeeRecipient;
        uint128 parlayUnderwritingFee;
        uint16 parlayVaultFeeBps;
        uint16 parlayFeeRecipientBps;
        uint16 orderbookEntryFeeBps;
        uint16 orderbookMakerFeeBps;
        uint16 orderbookCreatorFeeBps;
        uint16 orderbookProtocolFeeBps;
        uint16 orderbookVaultFeeBps;
        uint16 spotTradeFeeBps;
        uint16 spotMakerFeeBps;
        uint16 spotProtocolFeeBps;
        uint16 spotVaultFeeBps;
        uint16 comboTradeFeeBps;
        uint16 comboMakerFeeBps;
        uint16 comboCreatorFeeBps;
        uint16 comboProtocolFeeBps;
        uint16 comboVaultFeeBps;
        uint16 parimutuelEntryFeeBps;
        uint16 parimutuelCreatorFeeBps;
        uint16 parimutuelProtocolFeeBps;
        uint16 parimutuelVaultFeeBps;
        uint128 parimutuelMinEntry;
        uint64 parimutuelEpochWindowCap;
        uint16 marketCreationBatchCap;
        uint128 parimutuelCreationSeedAmount;
        uint128 marketCreationFee;
        uint128 spotBookCreationFee;
        uint128 comboMarketCreationFee;
        uint128 marketCreationBond;
        address bondToken;
        uint128 resolutionBondL1;
        uint128 resolutionBondL2;
        uint64 minMarketDuration;
        uint64 maxMarketDuration;
        uint64 disputeWindow;
        uint64 creatorSettleGrace;
        uint64 openResolutionTimeout;
        uint8 maxEscalation;
        bool permissionlessCreationEnabled;
        uint64 delayedOrderProtectionDelayBlocks;
        uint64 delayedOrderExecutionGraceBlocks;
        uint24 delayedOrderRestingDurationMinutes;
        uint16 delayedOrderProcessorFeeShareBps;
        uint8 delayedOrderProcessingMode;
    }

    struct Deployment {
        address diamond;
        address conditionalTokens;
        address diamondCutFacet;
        address diamondLoupeFacet;
        address ownershipFacet;
        address marketFactoryFacet;
        address marketViewFacet;
        address curveInventoryFacet;
        address curveLifecycleFacet;
        address curveCLOBFacet;
        address curveViewFacet;
        address delayedOrderFacet;
        address bookFacet;
        address bookOrderFacet;
        address bookTradeFacet;
        address bookViewFacet;
        address bondManagerFacet;
        address bondTokenGateFacet;
        address obrResolutionFacet;
        address resolverRegistryFacet;
        address resolverJuryFacet;
        address eveIdentity;
        address feeRouterFacet;
        address marketSettlementFacet;
        address multiOutcomeOrderbookFacet;
        address multiOutcomeOrderbookViewFacet;
        address nativeBinaryPositionFacet;
        address comboCoreFacet;
        address comboSettlementFacet;
        address comboBranchFacet;
        address comboViewFacet;
        address comboMarketFacet;
        address evesPositionManager;
        address parimutuelFacet;
        address parimutuelShareToken;
        address parlayAdminFacet;
        address parlayUnderwritingFacet;
        address parlayBudgetFacet;
        address parlaySettlementFacet;
        address parlayBookFacet;
        address parlayViewFacet;
        address parlayMulticallFacet;
        address parlayTicketToken;
        address tradeRouterFacet;
        address vaultRouterFacet;
    }

    struct FullDeploymentConfig {
        DeploymentConfig market;
        address usdcToken;
        address eveUSDC;
        address seveUsdcLending;
        address makerLendingRouter;
        address eveUsdcOnramp;
        address eveUsdcOfframp;
        address feeRecipient;
        uint16 aumFeeBps;
        uint16 lendingMaxLtvBps;
        uint16 lendingOriginationFeeBps;
        uint16 lendingExtensionFeeBps;
        uint16 lendingFeeRecipientBps;
        uint32 lendingMinDurationSeconds;
        uint32 lendingMaxDurationSeconds;
        uint32 lendingGracePeriodSeconds;
        uint256 initialUsdcMint;
        uint256 initialEveMint;
        uint256 initialVaultBootstrap;
        address faucetOwner;
        address wethToken;
        address eveETH;
        uint128 eveEthPayoutUnit;
        uint128 eveEthMarketCreationFee;
        uint128 eveEthParimutuelCreationSeedAmount;
        uint128 eveEthParimutuelMinEntry;
        uint128 eveEthParlayUnderwritingFee;
        bool faucetUsdcEnabled;
        bool faucetEveEnabled;
        bool deployMockWeth;
        bool deployEveETH;
        bool enableEveEthMarkets;
        uint256 faucetUsdcClaimAmount;
        uint256 faucetEveClaimAmount;
        uint256 faucetUsdcFundAmount;
        uint256 faucetEveFundAmount;
    }

    struct FullDeployment {
        Deployment market;
        address usdcToken;
        address eveToken;
        address eveUSDC;
        address seveUsdcVault;
        address seveUsdcLending;
        address makerLendingRouter;
        address faucet;
        address wethToken;
        address eveETH;
    }

    function run() external returns (FullDeployment memory deployment) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address temporaryOwner = vm.addr(deployerPrivateKey);
        FullDeploymentConfig memory config = _loadFullConfigFromEnv();

        vm.startBroadcast(deployerPrivateKey);
        deployment = deployFullStack(config, temporaryOwner);
        vm.stopBroadcast();
    }

    function deployFullStack(FullDeploymentConfig memory config, address temporaryOwner)
        public
        returns (FullDeployment memory deployment)
    {
        config = _withFullConfigDefaults(config, temporaryOwner);
        _validateFullConfig(config, temporaryOwner);

        bool autoDeployUsdc = config.usdcToken == address(0) && config.eveUSDC == address(0);
        bool autoDeployEveToken = config.market.eveToken == address(0);

        deployment.usdcToken = _resolveUsdcToken(config.usdcToken, config.eveUSDC);
        deployment.eveToken = _resolveEveToken(config.market.eveToken);
        deployment.eveUSDC =
            _resolveEveUSDC(config.eveUSDC, deployment.usdcToken, config.eveUsdcOnramp, config.eveUsdcOfframp);
        deployment.wethToken = _resolveWeth(config.wethToken, config.deployMockWeth);
        deployment.eveETH = _resolveEveETH(config.eveETH, deployment.wethToken, config.deployEveETH);

        DeploymentConfig memory marketConfig = config.market;
        marketConfig.owner = temporaryOwner;
        marketConfig.collateralToken = deployment.eveUSDC;
        marketConfig.eveToken = deployment.eveToken;
        if (marketConfig.bondToken == address(0)) {
            marketConfig.bondToken = deployment.eveETH;
        }
        marketConfig.stakingVault = address(0);
        marketConfig.parlayFeeRecipient = config.feeRecipient;

        deployment.market = deploy(marketConfig, temporaryOwner);
        deployment.seveUsdcVault = _resolveSEveUSDCVault(
            config.market.stakingVault,
            deployment.eveUSDC,
            temporaryOwner,
            config.feeRecipient,
            config.aumFeeBps,
            deployment.market.diamond
        );
        deployment.seveUsdcLending =
            _resolveSEveUSDCLending(config.seveUsdcLending, deployment.seveUsdcVault, deployment.eveUSDC, temporaryOwner);
        deployment.makerLendingRouter = _resolveMakerLendingRouter(
            config.makerLendingRouter,
            deployment.usdcToken,
            deployment.eveUSDC,
            deployment.seveUsdcVault,
            deployment.seveUsdcLending,
            deployment.market.diamond,
            deployment.market.conditionalTokens
        );
        deployment.faucet = _deployAndConfigureFaucet(deployment, config);

        _configureFullStack(deployment, config);
        _mintFullStackMocks(deployment, config, autoDeployUsdc, autoDeployEveToken);
        _fundFaucet(deployment, config, autoDeployUsdc, autoDeployEveToken);
        _bootstrapVault(deployment, config);
        _verifyFullDeployment(deployment, config);
    }

    function deploy(DeploymentConfig memory config, address temporaryOwner)
        public
        returns (Deployment memory deployment)
    {
        if (bytes(config.conditionalTokensArtifactPath).length == 0) {
            config.conditionalTokensArtifactPath = DEFAULT_CONDITIONAL_TOKENS_ARTIFACT_PATH;
        }

        deployment.conditionalTokens =
            _resolveConditionalTokens(config.conditionalTokens, config.conditionalTokensArtifactPath);
        config.conditionalTokens = deployment.conditionalTokens;

        _validateConfig(config, temporaryOwner);

        deployment.diamondCutFacet = address(new DiamondCutFacet());
        deployment.diamond = address(new EveMarketDiamond(temporaryOwner, deployment.diamondCutFacet));
        deployment.diamondLoupeFacet = address(new DiamondLoupeFacet());
        deployment.ownershipFacet = address(new OwnershipFacet());
        deployment.marketFactoryFacet = address(new MarketFactoryFacet());
        deployment.marketViewFacet = address(new MarketViewFacet());
        deployment.curveInventoryFacet = address(new CurveInventoryFacet());
        deployment.curveLifecycleFacet = address(new CurveLifecycleFacet());
        deployment.curveCLOBFacet = address(new CurveCLOBFacet());
        deployment.curveViewFacet = address(new CurveViewFacet());
        deployment.delayedOrderFacet = address(new DelayedOrderFacet());
        deployment.bookFacet = address(new BookFacet());
        deployment.bookOrderFacet = address(new BookOrderFacet());
        deployment.bookTradeFacet = address(new BookTradeFacet());
        deployment.bookViewFacet = address(new BookViewFacet());
        deployment.bondManagerFacet = address(new BondManagerFacet());
        deployment.bondTokenGateFacet = address(new BondTokenGateFacet());
        deployment.obrResolutionFacet = address(new OBRResolutionFacet());
        deployment.resolverRegistryFacet = address(new ResolverRegistryFacet());
        deployment.resolverJuryFacet = address(new ResolverJuryFacet());
        deployment.eveIdentity = address(new EveIdentity(deployment.diamond, "Eve Identity", "EVE-ID"));
        deployment.feeRouterFacet = address(new FeeRouterFacet());
        deployment.marketSettlementFacet = address(new MarketSettlementFacet());
        deployment.multiOutcomeOrderbookFacet = address(new MultiOutcomeOrderbookFacet());
        deployment.multiOutcomeOrderbookViewFacet = address(new MultiOutcomeOrderbookViewFacet());
        deployment.nativeBinaryPositionFacet = address(new NativeBinaryPositionFacet());
        deployment.comboCoreFacet = address(new ComboCoreFacet());
        deployment.comboSettlementFacet = address(new ComboSettlementFacet());
        deployment.comboBranchFacet = address(new ComboBranchFacet());
        deployment.comboViewFacet = address(new ComboViewFacet());
        deployment.comboMarketFacet = address(new ComboMarketFacet());
        deployment.evesPositionManager = _resolveEvesPositionManager(config.evesPositionManager, deployment.diamond);
        config.evesPositionManager = deployment.evesPositionManager;
        deployment.parimutuelFacet = address(new ParimutuelFacet());
        deployment.parimutuelShareToken = _resolveParimutuelShareToken(config.parimutuelShareToken, deployment.diamond);
        config.parimutuelShareToken = deployment.parimutuelShareToken;
        deployment.parlayAdminFacet = address(new ParlayAdminFacet());
        deployment.parlayUnderwritingFacet = address(new ParlayUnderwritingFacet());
        deployment.parlayBudgetFacet = address(new ParlayBudgetFacet());
        deployment.parlaySettlementFacet = address(new ParlaySettlementFacet());
        deployment.parlayBookFacet = address(new ParlayBookFacet());
        deployment.parlayViewFacet = address(new ParlayViewFacet());
        deployment.parlayMulticallFacet = address(new ParlayMulticallFacet());
        deployment.parlayTicketToken = _resolveParlayTicketToken(config.parlayTicketToken, deployment.diamond);
        config.parlayTicketToken = deployment.parlayTicketToken;
        deployment.tradeRouterFacet = address(new TradeRouterFacet());
        deployment.vaultRouterFacet = address(new VaultRouterFacet());

        _addCoreFacets(deployment);
        _configureDeployment(deployment.diamond, config);

        if (config.owner != temporaryOwner) {
            OwnershipFacet(deployment.diamond).transferOwnership(config.owner);
        }

        _verifyDeployment(deployment);
        require(OwnershipFacet(deployment.diamond).owner() == config.owner, "owner mismatch");
    }

    function diamondCutSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = DiamondCutFacet.diamondCut.selector;
        selectors[1] = DiamondCutFacet.freezeFacet.selector;
        selectors[2] = DiamondCutFacet.isSelectorFrozen.selector;
    }

    function loupeSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = DiamondLoupeFacet.facets.selector;
        selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
        selectors[3] = DiamondLoupeFacet.facetAddress.selector;
    }

    function ownershipSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](48);
        selectors[0] = OwnershipFacet.transferOwnership.selector;
        selectors[1] = OwnershipFacet.owner.selector;
        selectors[2] = OwnershipFacet.setOrderbookEntryFeeBps.selector;
        selectors[3] = OwnershipFacet.setResolutionBondConfig.selector;
        selectors[4] = OwnershipFacet.setMarketCreationFee.selector;
        selectors[5] = OwnershipFacet.setMarketCreationBond.selector;
        selectors[6] = OwnershipFacet.setPermissionlessCreationEnabled.selector;
        selectors[7] = OwnershipFacet.setDefaultConditionalTokens.selector;
        selectors[8] = OwnershipFacet.setCollateralToken.selector;
        selectors[9] = OwnershipFacet.setEveToken.selector;
        selectors[10] = OwnershipFacet.setEveTreasury.selector;
        selectors[11] = OwnershipFacet.setStakingVault.selector;
        selectors[12] = OwnershipFacet.setOrderbookFeeSplit.selector;
        selectors[13] = OwnershipFacet.setParimutuelFeeSplit.selector;
        selectors[14] = OwnershipFacet.setParimutuelConfig.selector;
        selectors[15] = OwnershipFacet.setDurationParams.selector;
        selectors[16] = OwnershipFacet.setDisputeWindow.selector;
        selectors[17] = OwnershipFacet.setCreatorSettleGrace.selector;
        selectors[18] = OwnershipFacet.setOpenResolutionTimeout.selector;
        selectors[19] = OwnershipFacet.setMaxEscalation.selector;
        selectors[20] = OwnershipFacet.registerCurveProfile.selector;
        selectors[21] = OwnershipFacet.setSpotBookCreationFee.selector;
        selectors[22] = OwnershipFacet.setParimutuelEpochWindowCap.selector;
        selectors[23] = OwnershipFacet.setParimutuelEpochMultipliers.selector;
        selectors[24] = OwnershipFacet.setSpotTradeFeeBps.selector;
        selectors[25] = OwnershipFacet.setSpotFeeSplit.selector;
        selectors[26] = OwnershipFacet.setMarketCreationBatchCap.selector;
        selectors[27] = OwnershipFacet.setEvesPositionManager.selector;
        selectors[28] = OwnershipFacet.setParimutuelCreationSeedAmount.selector;
        selectors[29] = OwnershipFacet.setComboTradeFeeBps.selector;
        selectors[30] = OwnershipFacet.setComboFeeSplit.selector;
        selectors[31] = OwnershipFacet.setComboMarketCreationFee.selector;
        selectors[32] = OwnershipFacet.setCollateralProfile.selector;
        selectors[33] = OwnershipFacet.setCollateralProfileEnabled.selector;
        selectors[34] = OwnershipFacet.setCollateralProfilePayoutUnit.selector;
        selectors[35] = OwnershipFacet.setCollateralProfileMarketCreationFee.selector;
        selectors[36] = OwnershipFacet.setCollateralProfileParimutuelCreationSeedAmount.selector;
        selectors[37] = OwnershipFacet.setCollateralProfileParimutuelMinEntry.selector;
        selectors[38] = OwnershipFacet.setCollateralProfileParlayUnderwritingFee.selector;
        selectors[39] = OwnershipFacet.setResolverJuryIdentitySettings.selector;
        selectors[40] = OwnershipFacet.setResolverJuryPoolSettings.selector;
        selectors[41] = OwnershipFacet.setResolverJuryRoundSettings.selector;
        selectors[42] = OwnershipFacet.setResolverJuryEconomicsSettings.selector;
        selectors[43] = OwnershipFacet.setDelayedOrderConfig.selector;
        selectors[44] = OwnershipFacet.setDelayedOrderProcessing.selector;
        selectors[45] = OwnershipFacet.setDelayedOrderProtocolProcessor.selector;
        selectors[46] = OwnershipFacet.setMarketDelayedExecution.selector;
        selectors[47] = OwnershipFacet.setBookDelayedExecution.selector;
    }

    function delayedOrderSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = DelayedOrderFacet.submitDelayedOrder.selector;
        selectors[1] = DelayedOrderFacet.processDelayedOrders.selector;
        selectors[2] = DelayedOrderFacet.withdrawQuoteCredit.selector;
        selectors[3] = DelayedOrderFacet.withdrawBaseCredit.selector;
        selectors[4] = DelayedOrderFacet.getQuoteCredit.selector;
        selectors[5] = DelayedOrderFacet.getBaseCredit.selector;
        selectors[6] = DelayedOrderFacet.getDelayedOrder.selector;
        selectors[7] = DelayedOrderFacet.getBookQueue.selector;
        selectors[8] = DelayedOrderFacet.getDelayedOrderIdBySequence.selector;
        selectors[9] = DelayedOrderFacet.isDelayedOrderSubmissionEnabled.selector;
    }

    function marketFactorySelectors() public pure returns (bytes4[] memory selectors) {
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

    function multiOutcomeOrderbookSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IMultiOutcomeOrderbookFacet.createMultiOutcomeMarket.selector;
        selectors[1] = IMultiOutcomeOrderbookFacet.createMultiOutcomeMarketWithCollateralProfile.selector;
        selectors[2] = IMultiOutcomeOrderbookFacet.splitOutcomeSet.selector;
        selectors[3] = IMultiOutcomeOrderbookFacet.mergeOutcomeSet.selector;
        selectors[4] = IMultiOutcomeOrderbookFacet.redeemOutcome.selector;
    }

    function multiOutcomeOrderbookViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IMultiOutcomeOrderbookFacet.getMultiOutcomeMarket.selector;
        selectors[1] = IMultiOutcomeOrderbookFacet.getMultiOutcomeOutcomes.selector;
        selectors[2] = IMultiOutcomeOrderbookFacet.getOutcomePositionId.selector;
        selectors[3] = IMultiOutcomeOrderbookFacet.getMultiOutcomeBooks.selector;
        selectors[4] = IMultiOutcomeOrderbookFacet.getMultiOutcomeTopOfBook.selector;
        selectors[5] = IMultiOutcomeOrderbookFacet.getMultiOutcomeDisplay.selector;
    }

    function nativeBinaryPositionSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = INativeBinaryPositionFacet.prepareNativeBinaryCondition.selector;
        selectors[1] = INativeBinaryPositionFacet.getNativeBinaryCondition.selector;
        selectors[2] = INativeBinaryPositionFacet.splitNativeBinary.selector;
        selectors[3] = INativeBinaryPositionFacet.mergeNativeBinary.selector;
        selectors[4] = INativeBinaryPositionFacet.redeemNativeBinary.selector;
        selectors[5] = INativeBinaryPositionFacet.getNativeBinaryPayout.selector;
    }

    function comboCoreSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IComboCoreFacet.prepareComboCondition.selector;
        selectors[1] = IComboCoreFacet.splitCombo.selector;
        selectors[2] = IComboCoreFacet.mergeCombo.selector;
        selectors[3] = IComboCoreFacet.wrapCombo.selector;
        selectors[4] = IComboCoreFacet.unwrapCombo.selector;
        selectors[5] = IComboCoreFacet.getComboCondition.selector;
        selectors[6] = IComboCoreFacet.getComboLegs.selector;
    }

    function comboSettlementSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IComboSettlementFacet.compressCombo.selector;
        selectors[1] = IComboSettlementFacet.redeemCombo.selector;
        selectors[2] = IComboSettlementFacet.getComboPayout.selector;
    }

    function comboBranchSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IComboBranchFacet.splitComboOnCondition.selector;
        selectors[1] = IComboBranchFacet.mergeComboOnCondition.selector;
        selectors[2] = IComboBranchFacet.extractComboNoLeg.selector;
        selectors[3] = IComboBranchFacet.injectComboNoLeg.selector;
        selectors[4] = IComboBranchFacet.convertComboNoToYesBasket.selector;
        selectors[5] = IComboBranchFacet.mergeComboNoFromYesBasket.selector;
    }

    function comboViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IComboViewFacet.getNativePositionMetadata.selector;
        selectors[1] = IComboViewFacet.isComboCompressible.selector;
        selectors[2] = IComboViewFacet.previewComboCompression.selector;
    }

    function comboMarketSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IComboMarketFacet.createComboMarket.selector;
        selectors[1] = IComboMarketFacet.computeComboBookId.selector;
        selectors[2] = IComboMarketFacet.getComboMarket.selector;
        selectors[3] = IComboMarketFacet.getComboBook.selector;
    }

    function marketViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](14);
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
    }

    function curveInventorySelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
        selectors[1] = ICurveInventoryFacet.mergeInventory.selector;
    }

    function curveLifecycleSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](17);
        selectors[0] = ICurveLifecycleFacet.postCurve.selector;
        selectors[1] = ICurveLifecycleFacet.postCurvesBatch.selector;
        selectors[2] = ICurveLifecycleFacet.postBidCurve.selector;
        selectors[3] = ICurveLifecycleFacet.postBidCurvesBatch.selector;
        selectors[4] = ICurveLifecycleFacet.postCurvesMultiMarket.selector;
        selectors[5] = ICurveLifecycleFacet.postBidCurvesMultiMarket.selector;
        selectors[6] = ICurveLifecycleFacet.postBidCurveWithUSDC.selector;
        selectors[7] = ICurveLifecycleFacet.updateCurve.selector;
        selectors[8] = ICurveLifecycleFacet.updateCurvesBatch.selector;
        selectors[9] = ICurveLifecycleFacet.updateCurveFromNow.selector;
        selectors[10] = ICurveLifecycleFacet.updateCurvesFromNowBatch.selector;
        selectors[11] = ICurveLifecycleFacet.topUpCurvesBatch.selector;
        selectors[12] = ICurveLifecycleFacet.splitAndTopUpCurvesBatch.selector;
        selectors[13] = ICurveLifecycleFacet.topUpCurvesMultiMarket.selector;
        selectors[14] = ICurveLifecycleFacet.splitAndTopUpCurvesMultiMarket.selector;
        selectors[15] = ICurveLifecycleFacet.cancelCurve.selector;
        selectors[16] = ICurveLifecycleFacet.cancelCurvesBatch.selector;
    }

    function curveTradeSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
        selectors[1] = ICurveTradeFacet.fillBest.selector;
        selectors[2] = ICurveTradeFacet.fillBestFor.selector;
    }

    function curveViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = ICurveViewFacet.getCurveInfo.selector;
        selectors[1] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[2] = ICurveViewFacet.previewCurveQuote.selector;
        selectors[3] = ICurveViewFacet.previewBestExecution.selector;
        selectors[4] = ICurveViewFacet.getMarketTopOfBook.selector;
    }

    function bookSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IBookAdminFacet.createBook.selector;
        selectors[1] = IBookAdminFacet.computeBookId.selector;
        selectors[2] = IBookAdminFacet.getBookInfo.selector;
        selectors[3] = IBookAdminFacet.isBookMaterialized.selector;
        selectors[4] = IBookAdminFacet.getMarketSideBook.selector;
        selectors[5] = IBookAdminFacet.requestBookDecommission.selector;
        selectors[6] = IBookAdminFacet.finalizeBookDecommission.selector;
    }

    function bookOrderSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
        selectors[1] = IBookOrderFacet.postBookCurvesBatch.selector;
        selectors[2] = IBookOrderFacet.topUpBookCurvesBatch.selector;
        selectors[3] = IBookOrderFacet.reactivateBookCurve.selector;
    }

    function bookTradeSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBestFor.selector;
        selectors[2] = IBookTradeFacet.sellBookBest.selector;
        selectors[3] = IBookTradeFacet.sellBookBestFor.selector;
    }

    function bookViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookViewFacet.previewBookExecution.selector;
        selectors[1] = IBookViewFacet.getBookTopOfBook.selector;
    }

    function bondManagerSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IBondManagerFacet.slashBond.selector;
        selectors[1] = IBondManagerFacet.returnBond.selector;
        selectors[2] = IBondManagerFacet.routeBond.selector;
    }

    function bondTokenGateSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBondTokenGateFacet.lockResolutionBond.selector;
        selectors[1] = IBondTokenGateFacet.unlockResolutionBond.selector;
    }

    function obrResolutionSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = IOBRResolutionFacet.settleMarket.selector;
        selectors[1] = IOBRResolutionFacet.openResolution.selector;
        selectors[2] = IOBRResolutionFacet.disputeResolution.selector;
        selectors[3] = IOBRResolutionFacet.getResolutionHistory.selector;
        selectors[4] = IOBRResolutionFacet.finalizeResolution.selector;
        selectors[5] = IOBRResolutionFacet.getMarketStatus.selector;
        selectors[6] = IOBRResolutionFacet.settleMarketEarly.selector;
        selectors[7] = IOBRResolutionFacet.finalizeFromJury.selector;
    }

    function resolverRegistrySelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](23);
        selectors[0] = IResolverRegistryFacet.mintIdentity.selector;
        selectors[1] = IResolverRegistryFacet.setCreatorRole.selector;
        selectors[2] = IResolverRegistryFacet.setResolverRole.selector;
        selectors[3] = IResolverRegistryFacet.depositResolverStake.selector;
        selectors[4] = IResolverRegistryFacet.activateResolver.selector;
        selectors[5] = IResolverRegistryFacet.requestResolverExit.selector;
        selectors[6] = IResolverRegistryFacet.withdrawResolverStake.selector;
        selectors[7] = IResolverRegistryFacet.eveIdentity.selector;
        selectors[8] = IResolverRegistryFacet.resolverDashboard.selector;
        selectors[9] = IResolverRegistryFacet.resolverIdentity.selector;
        selectors[10] = IResolverRegistryFacet.resolverIdentityByOwner.selector;
        selectors[11] = IResolverRegistryFacet.resolverJuryConfig.selector;
        selectors[12] = IResolverRegistryFacet.identityByOwner.selector;
        selectors[13] = IResolverRegistryFacet.isEligibleResolver.selector;
        selectors[14] = IResolverRegistryFacet.hasConflict.selector;
        selectors[15] = IResolverRegistryFacet.resolverLifecycleState.selector;
        selectors[16] = IResolverRegistryFacet.creatorReputation.selector;
        selectors[17] = IResolverRegistryFacet.resolverReputation.selector;
        selectors[18] = IResolverRegistryFacet.eligibleResolverCount.selector;
        selectors[19] = IResolverRegistryFacet.activeResolverCount.selector;
        selectors[20] = IResolverRegistryFacet.resolverPoolCapacity.selector;
        selectors[21] = IResolverRegistryFacet.resolverPoolMemberAt.selector;
        selectors[22] = IResolverRegistryFacet.applyFinalityReputation.selector;
    }

    function resolverJurySelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](19);
        selectors[0] = IResolverJuryFacet.initiateDispute.selector;
        selectors[1] = IResolverJuryFacet.openRandomnessCommit.selector;
        selectors[2] = IResolverJuryFacet.commitRandomness.selector;
        selectors[3] = IResolverJuryFacet.closeRandomnessCommit.selector;
        selectors[4] = IResolverJuryFacet.revealRandomness.selector;
        selectors[5] = IResolverJuryFacet.closeRandomnessReveal.selector;
        selectors[6] = IResolverJuryFacet.selectCommittee.selector;
        selectors[7] = IResolverJuryFacet.closeCommit.selector;
        selectors[8] = IResolverJuryFacet.closeRevealAndTally.selector;
        selectors[9] = IResolverJuryFacet.openAppeal.selector;
        selectors[10] = IResolverJuryFacet.finalizeDispute.selector;
        selectors[11] = IResolverJuryFacet.applyRandomnessFallback.selector;
        selectors[12] = IResolverJuryFacet.commitVote.selector;
        selectors[13] = IResolverJuryFacet.revealVote.selector;
        selectors[14] = IResolverJuryFacet.disputeView.selector;
        selectors[15] = IResolverJuryFacet.committeeMembers.selector;
        selectors[16] = IResolverJuryFacet.outcomeTally.selector;
        selectors[17] = IResolverJuryFacet.revealedVote.selector;
        selectors[18] = IResolverJuryFacet.provisionalResult.selector;
    }

    function feeRouterSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](12);
        selectors[0] = IFeeRouterFacet.claimCreatorFees.selector;
        selectors[1] = IFeeRouterFacet.claimMakerFees.selector;
        selectors[2] = IFeeRouterFacet.previewMakerFees.selector;
        selectors[3] = IFeeRouterFacet.getMakerMarketAccounting.selector;
        selectors[4] = IFeeRouterFacet.configureMarketMakerRewards.selector;
        selectors[5] = IFeeRouterFacet.fundMarketMakerRewards.selector;
        selectors[6] = IFeeRouterFacet.claimMarketMakerRewards.selector;
        selectors[7] = IFeeRouterFacet.previewMarketMakerRewards.selector;
        selectors[8] = IFeeRouterFacet.claimBookCreatorFees.selector;
        selectors[9] = IFeeRouterFacet.claimBookMakerFees.selector;
        selectors[10] = IFeeRouterFacet.previewBookMakerFees.selector;
        selectors[11] = IFeeRouterFacet.getMakerBookAccounting.selector;
    }

    function marketSettlementSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IMarketSettlementFacet.getCTFRedemptionParams.selector;
        selectors[1] = IMarketSettlementFacet.previewCTFRedemption.selector;
        selectors[2] = IMarketSettlementFacet.previewParimutuelPayout.selector;
        selectors[3] = IMarketSettlementFacet.previewRedemption.selector;
    }

    function parimutuelSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](17);
        selectors[0] = bytes4(
            keccak256(
                "createParimutuelMarket((string,string,string,uint64,uint64,uint64,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
            )
        );
        selectors[1] = bytes4(
            keccak256(
                "createParimutuelMarketWithCollateralProfile(uint8,(string,string,string,uint64,uint64,uint64,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
            )
        );
        selectors[2] = IParimutuelFacet.buyShares.selector;
        selectors[3] = IParimutuelFacet.buySharesBatch.selector;
        selectors[4] = IParimutuelFacet.claimPayout.selector;
        selectors[5] = IParimutuelFacet.sweepParimutuelDust.selector;
        selectors[6] = IParimutuelFacet.previewPayout.selector;
        selectors[7] = IParimutuelFacet.previewEntryFee.selector;
        selectors[8] = IParimutuelFacet.getParimutuelPool.selector;
        selectors[9] = IParimutuelFacet.getParimutuelBalances.selector;
        selectors[10] = IParimutuelFacet.isParimutuelMarket.selector;
        selectors[11] = IParimutuelFacet.getParimutuelEpochWindow.selector;
        selectors[12] = IParimutuelFacet.getEpochMultiplier.selector;
        selectors[13] = IParimutuelFacet.getParimutuelEpochMultipliers.selector;
        selectors[14] = IParimutuelFacet.previewParimutuelEntry.selector;
        selectors[15] = bytes4(keccak256("createParimutuelMarket(string,string,string,uint64,uint64,uint64)"));
        selectors[16] = bytes4(
            keccak256("createParimutuelMarketWithCollateralProfile(uint8,string,string,string,uint64,uint64,uint64)")
        );
    }

    function parlayAdminSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = ParlayAdminFacet.setParlayConfig.selector;
        selectors[1] = ParlayAdminFacet.getParlayConfig.selector;
        selectors[2] = ParlayAdminFacet.emitStrategyCreated.selector;
    }

    function parlayUnderwritingSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = ParlayUnderwritingFacet.postParlayOffer.selector;
        selectors[1] = ParlayUnderwritingFacet.fillParlayOffer.selector;
        selectors[2] = ParlayUnderwritingFacet.postParlayRequest.selector;
        selectors[3] = ParlayUnderwritingFacet.fillParlayRequest.selector;
        selectors[4] = ParlayUnderwritingFacet.cancelParlayOffer.selector;
        selectors[5] = ParlayUnderwritingFacet.cancelParlayRequest.selector;
        selectors[6] = ParlayUnderwritingFacet.postParlayOfferWithCollateralProfile.selector;
        selectors[7] = ParlayUnderwritingFacet.postParlayRequestWithCollateralProfile.selector;
    }

    function parlayBudgetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](13);
        selectors[0] = ParlayBudgetFacet.createParlayBudget.selector;
        selectors[1] = ParlayBudgetFacet.fundParlayBudget.selector;
        selectors[2] = ParlayBudgetFacet.cancelParlayBudget.selector;
        selectors[3] = ParlayBudgetFacet.getParlayBudget.selector;
        selectors[4] = ParlayBudgetFacet.postParlayOfferFromBudget.selector;
        selectors[5] = ParlayBudgetFacet.postParlayRequestFromBudget.selector;
        selectors[6] = ParlayBudgetFacet.postParlayOffersFromBudgetBatch.selector;
        selectors[7] = ParlayBudgetFacet.postParlayRequestsFromBudgetBatch.selector;
        selectors[8] = ParlayBudgetFacet.createParlayBudgetWithCollateralProfile.selector;
        selectors[9] = ParlayBudgetFacet.postParlayOfferFromBudgetWithCollateralProfile.selector;
        selectors[10] = ParlayBudgetFacet.postParlayRequestFromBudgetWithCollateralProfile.selector;
        selectors[11] = ParlayBudgetFacet.postParlayOffersFromBudgetBatchWithCollateralProfile.selector;
        selectors[12] = ParlayBudgetFacet.postParlayRequestsFromBudgetBatchWithCollateralProfile.selector;
    }

    function parlaySettlementSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ParlaySettlementFacet.finalizeParlayTicketBucket.selector;
        selectors[1] = ParlaySettlementFacet.claimParlayTicket.selector;
    }

    function parlayBookSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ParlayBookFacet.createParlayTicketBook.selector;
    }

    function parlayViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = ParlayViewFacet.computeParlayTemplateId.selector;
        selectors[1] = ParlayViewFacet.computeParlayTicketId.selector;
        selectors[2] = ParlayViewFacet.getParlayTemplate.selector;
        selectors[3] = ParlayViewFacet.getParlayTemplateLeg.selector;
        selectors[4] = ParlayViewFacet.getParlayTemplatePayoutTier.selector;
        selectors[5] = ParlayViewFacet.getParlayOffer.selector;
        selectors[6] = ParlayViewFacet.getParlayRequest.selector;
        selectors[7] = ParlayViewFacet.getParlayTicketBucket.selector;
        selectors[8] = ParlayViewFacet.parlayTicketURI.selector;
    }

    function parlayMulticallSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ParlayMulticallFacet.multicall.selector;
    }

    function tradeRouterSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = ITradeRouter.buyWithEveUSDC.selector;
        selectors[1] = ITradeRouter.buyWithUSDC.selector;
        selectors[2] = ITradeRouter.sellWithEveUSDC.selector;
        selectors[3] = ITradeRouter.sellWithUSDC.selector;
        selectors[4] = ITradeRouter.previewSellBest.selector;
        selectors[5] = ITradeRouter.splitWithUSDC.selector;
        selectors[6] = ITradeRouter.buyWithCollateral.selector;
        selectors[7] = ITradeRouter.sellWithCollateral.selector;
    }

    function vaultRouterSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IVaultRouter.wrapAndDeposit.selector;
        selectors[1] = IVaultRouter.redeemAndUnwrap.selector;
        selectors[2] = IVaultRouter.wrapETHToEveETH.selector;
    }

    function verifyDeployment(Deployment memory deployment) external view {
        _verifyDeployment(deployment);
    }

    function verifyFullDeployment(FullDeployment memory deployment, FullDeploymentConfig memory config) external view {
        config = _withFullConfigDefaults(config, OwnershipFacet(deployment.market.diamond).owner());
        _verifyFullDeployment(deployment, config);
    }

    function _loadConfigFromEnv() internal view returns (DeploymentConfig memory config) {
        config.owner = vm.envAddress("INITIAL_OWNER");
        config.conditionalTokens = vm.envOr("CONDITIONAL_TOKENS", address(0));
        config.conditionalTokensArtifactPath =
            vm.envOr("CONDITIONAL_TOKENS_ARTIFACT", DEFAULT_CONDITIONAL_TOKENS_ARTIFACT_PATH);
        config.collateralToken = vm.envOr("COLLATERAL_TOKEN", address(0));
        config.eveToken = vm.envOr("EVE_TOKEN", address(0));
        config.eveTreasury = vm.envAddress("EVE_TREASURY");
        config.stakingVault = vm.envOr("STAKING_VAULT", address(0));
        config.evesPositionManager = vm.envOr("EVES_POSITION_MANAGER", address(0));
        config.parimutuelShareToken = vm.envOr("PARIMUTUEL_SHARE_TOKEN", address(0));
        config.parlayTicketToken = vm.envOr("PARLAY_TICKET_TOKEN", address(0));
        config.parlayFeeRecipient = vm.envOr("PARLAY_FEE_RECIPIENT", config.eveTreasury);
        config.parlayUnderwritingFee = uint128(vm.envOr("PARLAY_UNDERWRITING_FEE", uint256(3e18)));
        config.parlayVaultFeeBps = uint16(vm.envOr("PARLAY_FEE_VAULT_BPS", uint256(0)));
        config.parlayFeeRecipientBps = uint16(vm.envOr("PARLAY_FEE_RECIPIENT_BPS", uint256(10_000)));
        config.orderbookEntryFeeBps = uint16(vm.envOr("ORDERBOOK_ENTRY_FEE_BPS", uint256(100)));
        config.orderbookMakerFeeBps = uint16(vm.envOr("ORDERBOOK_MAKER_FEE_BPS", uint256(8_500)));
        config.orderbookCreatorFeeBps = uint16(vm.envOr("ORDERBOOK_CREATOR_FEE_BPS", uint256(400)));
        config.orderbookProtocolFeeBps = uint16(vm.envOr("ORDERBOOK_PROTOCOL_FEE_BPS", uint256(1_000)));
        config.orderbookVaultFeeBps = uint16(vm.envOr("ORDERBOOK_VAULT_FEE_BPS", uint256(100)));
        config.spotTradeFeeBps = uint16(vm.envOr("SPOT_TRADE_FEE_BPS", uint256(100)));
        config.spotMakerFeeBps = uint16(vm.envOr("SPOT_MAKER_FEE_BPS", uint256(8_500)));
        config.spotProtocolFeeBps = uint16(vm.envOr("SPOT_PROTOCOL_FEE_BPS", uint256(1_400)));
        config.spotVaultFeeBps = uint16(vm.envOr("SPOT_VAULT_FEE_BPS", uint256(100)));
        config.comboTradeFeeBps = uint16(vm.envOr("COMBO_TRADE_FEE_BPS", uint256(100)));
        config.comboMakerFeeBps = uint16(vm.envOr("COMBO_MAKER_FEE_BPS", uint256(8_500)));
        config.comboCreatorFeeBps = uint16(vm.envOr("COMBO_CREATOR_FEE_BPS", uint256(400)));
        config.comboProtocolFeeBps = uint16(vm.envOr("COMBO_PROTOCOL_FEE_BPS", uint256(1_000)));
        config.comboVaultFeeBps = uint16(vm.envOr("COMBO_VAULT_FEE_BPS", uint256(100)));
        config.parimutuelEntryFeeBps = uint16(vm.envOr("PARIMUTUEL_ENTRY_FEE_BPS", uint256(250)));
        config.parimutuelCreatorFeeBps = uint16(vm.envOr("PARIMUTUEL_CREATOR_FEE_BPS", uint256(500)));
        config.parimutuelProtocolFeeBps = uint16(vm.envOr("PARIMUTUEL_PROTOCOL_FEE_BPS", uint256(9_500)));
        config.parimutuelVaultFeeBps = uint16(vm.envOr("PARIMUTUEL_VAULT_FEE_BPS", uint256(0)));
        config.parimutuelMinEntry = uint128(vm.envOr("PARIMUTUEL_MIN_ENTRY", uint256(1e18)));
        config.parimutuelEpochWindowCap = uint64(vm.envOr("PARIMUTUEL_EPOCH_WINDOW_CAP", uint256(30 days)));
        config.marketCreationBatchCap = uint16(vm.envOr("MARKET_CREATION_BATCH_CAP", uint256(24)));
        config.parimutuelCreationSeedAmount = uint128(vm.envOr("PARIMUTUEL_CREATION_SEED_AMOUNT", uint256(0)));
        config.marketCreationFee = uint128(vm.envUint("MARKET_CREATION_FEE"));
        config.spotBookCreationFee = uint128(vm.envOr("SPOT_BOOK_CREATION_FEE", uint256(250e18)));
        config.comboMarketCreationFee = uint128(vm.envOr("COMBO_MARKET_CREATION_FEE", uint256(250e18)));
        config.marketCreationBond = uint128(vm.envUint("MARKET_CREATION_BOND_EVE"));
        config.bondToken = vm.envOr("BOND_TOKEN_ADDRESS", address(0));
        config.resolutionBondL1 = uint128(vm.envUint("RESOLUTION_BOND_L1"));
        config.resolutionBondL2 = uint128(vm.envUint("RESOLUTION_BOND_L2"));
        config.minMarketDuration = uint64(vm.envUint("MIN_MARKET_DURATION"));
        config.maxMarketDuration = uint64(vm.envUint("MAX_MARKET_DURATION"));
        config.disputeWindow = uint64(vm.envUint("DISPUTE_WINDOW"));
        config.creatorSettleGrace = uint64(vm.envUint("CREATOR_SETTLE_GRACE"));
        config.openResolutionTimeout = uint64(vm.envUint("OPEN_RESOLUTION_TIMEOUT"));
        config.maxEscalation = uint8(vm.envUint("MAX_ESCALATION"));
        config.permissionlessCreationEnabled = vm.envBool("PERMISSIONLESS_CREATION_ENABLED");
        config.delayedOrderProtectionDelayBlocks = uint64(vm.envOr("DELAYED_ORDER_PROTECTION_DELAY_BLOCKS", uint256(2)));
        config.delayedOrderExecutionGraceBlocks = uint64(vm.envOr("DELAYED_ORDER_EXECUTION_GRACE_BLOCKS", uint256(20)));
        config.delayedOrderRestingDurationMinutes =
            uint24(vm.envOr("DELAYED_ORDER_RESTING_DURATION_MINUTES", uint256(180)));
        config.delayedOrderProcessorFeeShareBps = uint16(vm.envOr("DELAYED_ORDER_PROCESSOR_FEE_SHARE_BPS", uint256(0)));
        config.delayedOrderProcessingMode = uint8(vm.envOr("DELAYED_ORDER_PROCESSING_MODE", uint256(0)));
    }

    function _loadFullConfigFromEnv() internal view returns (FullDeploymentConfig memory config) {
        config.market = _loadConfigFromEnv();
        config.usdcToken = vm.envOr("USDC_TOKEN", address(0));
        config.eveUSDC = vm.envOr("EVEUSDC_ADDRESS", address(0));
        config.seveUsdcLending = vm.envOr("SEVEUSDC_LENDING", address(0));
        config.makerLendingRouter = vm.envOr("MAKER_LENDING_ROUTER", address(0));
        config.eveUsdcOnramp = vm.envOr("EVEUSDC_ONRAMP", config.market.owner);
        config.eveUsdcOfframp = vm.envOr("EVEUSDC_OFFRAMP", config.market.owner);
        config.feeRecipient = vm.envOr("FEE_RECIPIENT", config.market.eveTreasury);
        config.aumFeeBps = uint16(vm.envOr("AUM_FEE_BPS", uint256(200)));
        config.lendingMaxLtvBps = uint16(vm.envOr("LENDING_MAX_LTV_BPS", uint256(9_500)));
        config.lendingOriginationFeeBps = uint16(vm.envOr("LENDING_ORIGINATION_FEE_BPS", uint256(100)));
        config.lendingExtensionFeeBps = uint16(vm.envOr("LENDING_EXTENSION_FEE_BPS", uint256(50)));
        config.lendingFeeRecipientBps = uint16(vm.envOr("LENDING_FEE_RECIPIENT_BPS", uint256(0)));
        config.lendingMinDurationSeconds = uint32(vm.envOr("LENDING_MIN_DURATION_SECONDS", uint256(1 days)));
        config.lendingMaxDurationSeconds = uint32(vm.envOr("LENDING_MAX_DURATION_SECONDS", uint256(400 days)));
        config.lendingGracePeriodSeconds = uint32(vm.envOr("LENDING_GRACE_PERIOD_SECONDS", uint256(1 days)));
        config.initialUsdcMint = vm.envOr("INITIAL_USDC_MINT", uint256(5_000_000e6));
        config.initialEveMint = vm.envOr("INITIAL_EVE_MINT", uint256(1_000_000e18));
        config.initialVaultBootstrap = vm.envOr("INITIAL_VAULT_BOOTSTRAP", uint256(0));
        config.faucetOwner = vm.envOr("FAUCET_OWNER", config.market.owner);
        config.faucetUsdcEnabled = vm.envOr("FAUCET_USDC_ENABLED", true);
        config.faucetEveEnabled = vm.envOr("FAUCET_EVE_ENABLED", true);
        config.faucetUsdcClaimAmount = vm.envOr("FAUCET_USDC_CLAIM_AMOUNT", uint256(1_000e6));
        config.faucetEveClaimAmount = vm.envOr("FAUCET_EVE_CLAIM_AMOUNT", uint256(10_000e18));
        config.faucetUsdcFundAmount = vm.envOr("FAUCET_USDC_FUND_AMOUNT", uint256(1_000_000e6));
        config.faucetEveFundAmount = vm.envOr("FAUCET_EVE_FUND_AMOUNT", uint256(10_000_000e18));
        config.wethToken = vm.envOr("WETH_ADDRESS", address(0));
        config.eveETH = vm.envOr("EVEETH_ADDRESS", address(0));
        config.eveEthPayoutUnit = uint128(vm.envOr("EVEETH_PAYOUT_UNIT", uint256(0.0005 ether)));
        config.eveEthMarketCreationFee = uint128(vm.envOr("EVEETH_MARKET_CREATION_FEE", uint256(0)));
        config.eveEthParimutuelCreationSeedAmount =
            uint128(vm.envOr("EVEETH_PARIMUTUEL_CREATION_SEED_AMOUNT", uint256(0)));
        config.eveEthParimutuelMinEntry =
            uint128(vm.envOr("EVEETH_PARIMUTUEL_MIN_ENTRY", uint256(config.eveEthPayoutUnit)));
        config.eveEthParlayUnderwritingFee = uint128(vm.envOr("EVEETH_PARLAY_UNDERWRITING_FEE", uint256(0.0002 ether)));
        config.deployMockWeth = vm.envOr("DEPLOY_MOCK_WETH", false);
        config.deployEveETH = vm.envOr("DEPLOY_EVEETH", false);
        config.enableEveEthMarkets = vm.envOr("ENABLE_EVEETH_MARKETS", false);
    }

    function _validateConfig(DeploymentConfig memory config, address temporaryOwner) internal pure {
        require(temporaryOwner != address(0), "zero temporary owner");
        require(config.owner != address(0), "zero owner");
        require(
            config.conditionalTokens != address(0) || bytes(config.conditionalTokensArtifactPath).length != 0,
            "missing conditional tokens source"
        );
        require(config.collateralToken != address(0), "zero collateral token");
        require(config.eveToken != address(0), "zero eve token");
        require(config.eveTreasury != address(0), "zero eve treasury");
        require(config.bondToken != address(0), "zero bond token");
        require(config.resolutionBondL2 >= config.resolutionBondL1, "invalid resolution bonds");
        require(config.parlayFeeRecipient != address(0), "zero parlay fee recipient");
        require(config.minMarketDuration <= config.maxMarketDuration, "invalid duration bounds");
        require(config.orderbookEntryFeeBps <= 10_000, "invalid orderbook entry fee");
        require(config.spotTradeFeeBps <= 10_000, "invalid spot trade fee");
        require(config.comboTradeFeeBps <= 10_000, "invalid combo trade fee");
        require(config.parimutuelEntryFeeBps <= 10_000, "invalid parimutuel entry fee");
        require(config.delayedOrderProcessorFeeShareBps <= 10_000, "invalid delayed processor fee share");
        require(
            config.delayedOrderProcessingMode <= uint8(LibEveMarket.ProcessingMode.Paused),
            "invalid delayed processing mode"
        );
        require(
            uint256(config.orderbookMakerFeeBps) + config.orderbookCreatorFeeBps + config.orderbookProtocolFeeBps
                    + config.orderbookVaultFeeBps == 10_000,
            "invalid orderbook fee split"
        );
        require(
            uint256(config.spotMakerFeeBps) + config.spotProtocolFeeBps + config.spotVaultFeeBps == 10_000,
            "invalid spot fee split"
        );
        require(
            uint256(config.comboMakerFeeBps) + config.comboCreatorFeeBps + config.comboProtocolFeeBps
                    + config.comboVaultFeeBps == 10_000,
            "invalid combo fee split"
        );
        require(
            uint256(config.parimutuelCreatorFeeBps) + config.parimutuelProtocolFeeBps + config.parimutuelVaultFeeBps
                == 10_000,
            "invalid parimutuel fee split"
        );
        require(uint256(config.parlayVaultFeeBps) + config.parlayFeeRecipientBps == 10_000, "invalid parlay fee split");
    }

    function _withFullConfigDefaults(FullDeploymentConfig memory config, address temporaryOwner)
        internal
        pure
        returns (FullDeploymentConfig memory)
    {
        if (config.eveUsdcOnramp == address(0)) {
            config.eveUsdcOnramp = temporaryOwner;
        }
        if (config.eveUsdcOfframp == address(0)) {
            config.eveUsdcOfframp = temporaryOwner;
        }
        if (config.feeRecipient == address(0)) {
            config.feeRecipient = config.market.eveTreasury;
        }
        if (config.market.parlayFeeRecipient == address(0)) {
            config.market.parlayFeeRecipient = config.feeRecipient;
        }
        if (config.faucetOwner == address(0)) {
            config.faucetOwner = config.market.owner;
        }
        if (config.initialVaultBootstrap == 0 && _requiresVaultBootstrap(config)) {
            config.initialVaultBootstrap = 1e6;
        }

        return config;
    }

    function _requiresVaultBootstrap(FullDeploymentConfig memory config) internal pure returns (bool) {
        return config.market.marketCreationFee != 0 || config.market.spotBookCreationFee != 0
            || (config.market.orderbookEntryFeeBps != 0 && config.market.orderbookVaultFeeBps != 0)
            || (config.market.parimutuelEntryFeeBps != 0 && config.market.parimutuelVaultFeeBps != 0)
            || (config.market.parlayUnderwritingFee != 0 && config.market.parlayVaultFeeBps != 0);
    }

    function _validateFullConfig(FullDeploymentConfig memory config, address temporaryOwner) internal pure {
        require(temporaryOwner != address(0), "zero temporary owner");
        require(config.market.owner != address(0), "zero owner");
        require(config.market.owner == temporaryOwner, "full deploy owner mismatch");
        require(config.market.eveTreasury != address(0), "zero eve treasury");
        require(config.eveUsdcOnramp != address(0), "zero eveUSDC onramp");
        require(config.eveUsdcOfframp != address(0), "zero eveUSDC offramp");
        require(config.feeRecipient != address(0), "zero fee recipient");
        require(config.market.parlayFeeRecipient != address(0), "zero parlay fee recipient");
        require(config.faucetOwner != address(0), "zero faucet owner");
        if (config.enableEveEthMarkets) {
            require(config.eveEthPayoutUnit != 0, "zero eveETH payout unit");
            require(config.deployEveETH || config.eveETH != address(0), "missing eveETH source");
            require(config.deployMockWeth || config.wethToken != address(0), "missing WETH source");
        }
        if (config.deployEveETH) {
            require(config.deployMockWeth || config.wethToken != address(0), "missing WETH for eveETH");
        }
        if (config.deployMockWeth) {
            require(config.wethToken == address(0), "mock WETH conflicts with WETH address");
        }
        require(config.faucetUsdcEnabled || config.faucetEveEnabled, "faucet disabled");
        if (config.faucetUsdcEnabled) {
            require(config.faucetUsdcClaimAmount != 0, "zero faucet usdc amount");
        }
        if (config.faucetEveEnabled) {
            require(config.faucetEveClaimAmount != 0, "zero faucet eve amount");
        }
        require(config.lendingMinDurationSeconds <= config.lendingMaxDurationSeconds, "invalid lending duration bounds");
    }

    function _addCoreFacets(Deployment memory deployment) internal {
        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](38);
        cuts[0] = _cut(deployment.diamondLoupeFacet, loupeSelectors());
        cuts[1] = _cut(deployment.ownershipFacet, ownershipSelectors());
        cuts[2] = _cut(deployment.marketFactoryFacet, marketFactorySelectors());
        cuts[3] = _cut(deployment.marketViewFacet, marketViewSelectors());
        cuts[4] = _cut(deployment.curveInventoryFacet, curveInventorySelectors());
        cuts[5] = _cut(deployment.curveLifecycleFacet, curveLifecycleSelectors());
        cuts[6] = _cut(deployment.curveCLOBFacet, curveTradeSelectors());
        cuts[7] = _cut(deployment.curveViewFacet, curveViewSelectors());
        cuts[8] = _cut(deployment.bookFacet, bookSelectors());
        cuts[9] = _cut(deployment.bookOrderFacet, bookOrderSelectors());
        cuts[10] = _cut(deployment.bookTradeFacet, bookTradeSelectors());
        cuts[11] = _cut(deployment.bookViewFacet, bookViewSelectors());
        cuts[12] = _cut(deployment.bondManagerFacet, bondManagerSelectors());
        cuts[13] = _cut(deployment.bondTokenGateFacet, bondTokenGateSelectors());
        cuts[14] = _cut(deployment.obrResolutionFacet, obrResolutionSelectors());
        cuts[15] = _cut(deployment.feeRouterFacet, feeRouterSelectors());
        cuts[16] = _cut(deployment.marketSettlementFacet, marketSettlementSelectors());
        cuts[17] = _cut(deployment.multiOutcomeOrderbookFacet, multiOutcomeOrderbookSelectors());
        cuts[18] = _cut(deployment.multiOutcomeOrderbookViewFacet, multiOutcomeOrderbookViewSelectors());
        cuts[19] = _cut(deployment.nativeBinaryPositionFacet, nativeBinaryPositionSelectors());
        cuts[20] = _cut(deployment.comboCoreFacet, comboCoreSelectors());
        cuts[21] = _cut(deployment.comboSettlementFacet, comboSettlementSelectors());
        cuts[22] = _cut(deployment.comboBranchFacet, comboBranchSelectors());
        cuts[23] = _cut(deployment.comboViewFacet, comboViewSelectors());
        cuts[24] = _cut(deployment.comboMarketFacet, comboMarketSelectors());
        cuts[25] = _cut(deployment.parimutuelFacet, parimutuelSelectors());
        cuts[26] = _cut(deployment.parlayAdminFacet, parlayAdminSelectors());
        cuts[27] = _cut(deployment.parlayUnderwritingFacet, parlayUnderwritingSelectors());
        cuts[28] = _cut(deployment.parlayBudgetFacet, parlayBudgetSelectors());
        cuts[29] = _cut(deployment.parlaySettlementFacet, parlaySettlementSelectors());
        cuts[30] = _cut(deployment.parlayBookFacet, parlayBookSelectors());
        cuts[31] = _cut(deployment.parlayViewFacet, parlayViewSelectors());
        cuts[32] = _cut(deployment.parlayMulticallFacet, parlayMulticallSelectors());
        cuts[33] = _cut(deployment.tradeRouterFacet, tradeRouterSelectors());
        cuts[34] = _cut(deployment.vaultRouterFacet, vaultRouterSelectors());
        cuts[35] = _cut(deployment.resolverRegistryFacet, resolverRegistrySelectors());
        cuts[36] = _cut(deployment.resolverJuryFacet, resolverJurySelectors());
        cuts[37] = _cut(deployment.delayedOrderFacet, delayedOrderSelectors());

        ResolverJuryInit init = new ResolverJuryInit();
        DiamondCutFacet(deployment.diamond)
            .diamondCut(
                cuts, address(init), abi.encodeCall(ResolverJuryInit.initResolverJury, (deployment.eveIdentity))
            );
    }

    function _configureDeployment(address diamond, DeploymentConfig memory config) internal {
        OwnershipFacet(diamond).setDefaultConditionalTokens(config.conditionalTokens);
        OwnershipFacet(diamond).setCollateralToken(config.collateralToken);
        OwnershipFacet(diamond).setEveToken(config.eveToken);
        OwnershipFacet(diamond).setEveTreasury(config.eveTreasury);
        OwnershipFacet(diamond).setStakingVault(config.stakingVault);
        OwnershipFacet(diamond).setEvesPositionManager(config.evesPositionManager);
        OwnershipFacet(diamond)
            .setOrderbookFeeSplit(
                config.orderbookMakerFeeBps,
                config.orderbookCreatorFeeBps,
                config.orderbookProtocolFeeBps,
                config.orderbookVaultFeeBps
            );
        OwnershipFacet(diamond)
            .setSpotFeeSplit(config.spotMakerFeeBps, config.spotProtocolFeeBps, config.spotVaultFeeBps);
        OwnershipFacet(diamond)
            .setComboFeeSplit(
                config.comboMakerFeeBps, config.comboCreatorFeeBps, config.comboProtocolFeeBps, config.comboVaultFeeBps
            );
        OwnershipFacet(diamond)
            .setParimutuelFeeSplit(
                config.parimutuelCreatorFeeBps, config.parimutuelProtocolFeeBps, config.parimutuelVaultFeeBps
            );
        OwnershipFacet(diamond)
            .setParimutuelConfig(config.parimutuelShareToken, config.parimutuelEntryFeeBps, config.parimutuelMinEntry);
        ParlayAdminFacet(diamond)
            .setParlayConfig(
                config.parlayTicketToken,
                config.parlayFeeRecipient,
                config.parlayUnderwritingFee,
                config.parlayVaultFeeBps,
                config.parlayFeeRecipientBps
            );
        OwnershipFacet(diamond).setParimutuelEpochWindowCap(config.parimutuelEpochWindowCap);
        OwnershipFacet(diamond).setParimutuelEpochMultipliers(_defaultParimutuelEpochMultipliers());
        OwnershipFacet(diamond).setOrderbookEntryFeeBps(config.orderbookEntryFeeBps);
        OwnershipFacet(diamond).setSpotTradeFeeBps(config.spotTradeFeeBps);
        OwnershipFacet(diamond).setComboTradeFeeBps(config.comboTradeFeeBps);
        OwnershipFacet(diamond).setParimutuelCreationSeedAmount(config.parimutuelCreationSeedAmount);
        OwnershipFacet(diamond).setMarketCreationFee(config.marketCreationFee);
        OwnershipFacet(diamond).setSpotBookCreationFee(config.spotBookCreationFee);
        OwnershipFacet(diamond).setComboMarketCreationFee(config.comboMarketCreationFee);
        OwnershipFacet(diamond).setMarketCreationBond(config.marketCreationBond);
        OwnershipFacet(diamond).setMarketCreationBatchCap(config.marketCreationBatchCap);
        OwnershipFacet(diamond).setPermissionlessCreationEnabled(config.permissionlessCreationEnabled);
        OwnershipFacet(diamond)
            .setDelayedOrderConfig(
                config.delayedOrderProtectionDelayBlocks,
                config.delayedOrderExecutionGraceBlocks,
                config.delayedOrderRestingDurationMinutes
            );
        OwnershipFacet(diamond)
            .setDelayedOrderProcessing(config.delayedOrderProcessingMode, config.delayedOrderProcessorFeeShareBps);
        OwnershipFacet(diamond)
            .setResolutionBondConfig(config.bondToken, config.resolutionBondL1, config.resolutionBondL2);
        OwnershipFacet(diamond).setDurationParams(config.minMarketDuration, config.maxMarketDuration);
        OwnershipFacet(diamond).setDisputeWindow(config.disputeWindow);
        OwnershipFacet(diamond).setCreatorSettleGrace(config.creatorSettleGrace);
        OwnershipFacet(diamond).setOpenResolutionTimeout(config.openResolutionTimeout);
        OwnershipFacet(diamond).setMaxEscalation(config.maxEscalation);
        _configureResolverJuryDefaults(diamond);
    }

    function _configureResolverJuryDefaults(address diamond) internal {
        OwnershipFacet(diamond)
            .setResolverJuryIdentitySettings(
                OwnershipConfigTypes.ResolverJuryIdentitySettings({
                    identityMintFeeToken: address(0),
                    identityMintFee: 0,
                    resolverStakeRequirement: 100e18,
                    resolverStakeCap: 250e18
                })
            );
        OwnershipFacet(diamond)
            .setResolverJuryPoolSettings(
                OwnershipConfigTypes.ResolverJuryPoolSettings({
                    resolverPoolCap: 50,
                    activationDelay: 0,
                    exitCooldown: 7 days,
                    participationThresholdBps: 0,
                    concurrencyLimit: 5,
                    participationGraceCount: 5,
                    conflictPositionThreshold: 0
                })
            );

        uint16[] memory committeeSizes = new uint16[](2);
        committeeSizes[0] = 3;
        committeeSizes[1] = 5;
        OwnershipFacet(diamond)
            .setResolverJuryRoundSettings(
                OwnershipConfigTypes.ResolverJuryRoundSettings({
                    committeeSizesByRound: committeeSizes,
                    maxAppealRounds: 1,
                    appealBondMultiplierBps: 20_000,
                    randomnessCommitDuration: 1 hours,
                    randomnessRevealDuration: 1 hours,
                    commitDuration: 1 hours,
                    revealDuration: 1 hours,
                    appealWindow: 1 hours,
                    randomnessTimeout: 5 minutes,
                    quorum: 2,
                    redrawLimit: 1,
                    lowQuorumMode: LibEveMarket.LowQuorumMode.FinalizeInvalid,
                    tieBreakMode: LibEveMarket.TieBreakMode.ResolveInvalid,
                    randomnessFailureMode: LibEveMarket.RandomnessFailureMode.AllEligible,
                    minRandomnessReveals: 2,
                    allEligibleFallbackCap: 10
                })
            );
        OwnershipFacet(diamond)
            .setResolverJuryEconomicsSettings(
                OwnershipConfigTypes.ResolverJuryEconomicsSettings({
                    missedCommitSlashBps: 1_000,
                    missedRevealSlashBps: 2_000,
                    invalidRevealSlashBps: 3_000,
                    slashCooldown: 1 days,
                    protocolFeeAllocationBps: 0,
                    appealSuccessRoutingBps: [uint16(7_000), 1_000, 1_000, 1_000],
                    appealFailureRoutingBps: [uint16(4_000), 3_000, 3_000],
                    incentiveSelectCommittee: 0,
                    incentiveCloseCommit: 0,
                    incentiveCloseReveal: 0,
                    incentiveOpenAppeal: 0,
                    incentiveFinalize: 0,
                    incentiveRandomness: 0
                })
            );
    }

    function _configureFullStack(FullDeployment memory deployment, FullDeploymentConfig memory config) internal {
        SEveUSDCVault(deployment.seveUsdcVault).setLendingContract(deployment.seveUsdcLending);
        SEveUSDCLending(deployment.seveUsdcLending)
            .setLendingConfig(
                config.lendingMaxLtvBps,
                config.lendingOriginationFeeBps,
                config.lendingExtensionFeeBps,
                config.lendingMinDurationSeconds,
                config.lendingMaxDurationSeconds,
                config.lendingGracePeriodSeconds
            );
        SEveUSDCLending(deployment.seveUsdcLending).setLendingFeeRecipientBps(config.lendingFeeRecipientBps);
        SEveUSDCLending(deployment.seveUsdcLending).setApprovedRouter(deployment.makerLendingRouter, true);
        OwnershipFacet(deployment.market.diamond).setStakingVault(deployment.seveUsdcVault);
        if (config.enableEveEthMarkets) {
            OwnershipFacet(deployment.market.diamond)
                .setCollateralProfile(
                    EVE_ETH_PROFILE_ID,
                    deployment.eveETH,
                    deployment.wethToken,
                    config.eveEthPayoutUnit,
                    config.eveEthMarketCreationFee,
                    true
                );
            OwnershipFacet(deployment.market.diamond)
                .setCollateralProfileParimutuelCreationSeedAmount(
                    EVE_ETH_PROFILE_ID, config.eveEthParimutuelCreationSeedAmount
                );
            OwnershipFacet(deployment.market.diamond)
                .setCollateralProfileParimutuelMinEntry(EVE_ETH_PROFILE_ID, config.eveEthParimutuelMinEntry);
            OwnershipFacet(deployment.market.diamond)
                .setCollateralProfileParlayUnderwritingFee(EVE_ETH_PROFILE_ID, config.eveEthParlayUnderwritingFee);
        }
    }

    function _deployAndConfigureFaucet(FullDeployment memory deployment, FullDeploymentConfig memory config)
        internal
        returns (address)
    {
        Faucet faucet = new Faucet(config.market.owner);
        if (config.faucetUsdcEnabled) {
            faucet.setToken(deployment.usdcToken, config.faucetUsdcClaimAmount, true);
        }
        if (config.faucetEveEnabled) {
            faucet.setToken(deployment.eveToken, config.faucetEveClaimAmount, true);
        }
        if (config.faucetOwner != config.market.owner) {
            faucet.transferOwnership(config.faucetOwner);
        }

        return address(faucet);
    }

    function _mintFullStackMocks(
        FullDeployment memory deployment,
        FullDeploymentConfig memory config,
        bool autoDeployUsdc,
        bool autoDeployEveToken
    ) internal {
        if (autoDeployUsdc && config.initialUsdcMint != 0) {
            MockUSDC(deployment.usdcToken).mint(config.market.owner, config.initialUsdcMint);
        }
        if (autoDeployEveToken && config.initialEveMint != 0) {
            MockEveToken(deployment.eveToken).mintAndDelegate(config.market.owner, config.initialEveMint);
        }
    }

    function _fundFaucet(
        FullDeployment memory deployment,
        FullDeploymentConfig memory config,
        bool autoDeployUsdc,
        bool autoDeployEveToken
    ) internal {
        if (config.faucetUsdcEnabled && config.faucetUsdcFundAmount != 0) {
            if (autoDeployUsdc) {
                MockUSDC(deployment.usdcToken).mint(deployment.faucet, config.faucetUsdcFundAmount);
            } else {
                IERC20(deployment.usdcToken).safeTransfer(deployment.faucet, config.faucetUsdcFundAmount);
            }
        }
        if (config.faucetEveEnabled && config.faucetEveFundAmount != 0) {
            if (autoDeployEveToken) {
                MockEveToken(deployment.eveToken).mint(deployment.faucet, config.faucetEveFundAmount);
            } else {
                IERC20(deployment.eveToken).safeTransfer(deployment.faucet, config.faucetEveFundAmount);
            }
        }
    }

    function _bootstrapVault(FullDeployment memory deployment, FullDeploymentConfig memory config) internal {
        uint256 bootstrapUsdc = config.initialVaultBootstrap;
        if (bootstrapUsdc == 0 || SEveUSDCVault(deployment.seveUsdcVault).totalSupply() != 0) {
            return;
        }

        uint256 bootstrapAssets = LibEveUSDCUnits.toEveUSDC(bootstrapUsdc);
        uint256 eveUSDCBalance = IERC20(deployment.eveUSDC).balanceOf(config.market.owner);
        if (eveUSDCBalance < bootstrapAssets) {
            uint256 deficit = (bootstrapAssets - eveUSDCBalance + LibEveUSDCUnits.USDC_TO_EVEUSDC_SCALE - 1)
                / LibEveUSDCUnits.USDC_TO_EVEUSDC_SCALE;
            IERC20(deployment.usdcToken).forceApprove(deployment.eveUSDC, deficit);
            EveUSDC(deployment.eveUSDC).wrap(deficit, config.market.owner);
        }

        IERC20(deployment.eveUSDC).forceApprove(deployment.seveUsdcVault, bootstrapAssets);
        SEveUSDCVault(deployment.seveUsdcVault).deposit(bootstrapAssets, config.market.owner);
    }

    function _verifyDeployment(Deployment memory deployment) internal view {
        require(DiamondLoupeFacet(deployment.diamond).facetAddresses().length == 39, "unexpected facet count");
        require(deployment.eveIdentity != address(0), "zero eve identity");
        require(EveIdentity(deployment.eveIdentity).diamond() == deployment.diamond, "eve identity diamond mismatch");

        _assertSelectorRouting(deployment.diamond, deployment.diamondCutFacet, diamondCutSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.diamondLoupeFacet, loupeSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.ownershipFacet, ownershipSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.marketFactoryFacet, marketFactorySelectors());
        _assertSelectorRouting(deployment.diamond, deployment.marketViewFacet, marketViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.curveInventoryFacet, curveInventorySelectors());
        _assertSelectorRouting(deployment.diamond, deployment.curveLifecycleFacet, curveLifecycleSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.curveCLOBFacet, curveTradeSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.curveViewFacet, curveViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bookFacet, bookSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bookOrderFacet, bookOrderSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bookTradeFacet, bookTradeSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bookViewFacet, bookViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bondManagerFacet, bondManagerSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bondTokenGateFacet, bondTokenGateSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.obrResolutionFacet, obrResolutionSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.resolverRegistryFacet, resolverRegistrySelectors());
        _assertSelectorRouting(deployment.diamond, deployment.resolverJuryFacet, resolverJurySelectors());
        _assertSelectorRouting(deployment.diamond, deployment.feeRouterFacet, feeRouterSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.marketSettlementFacet, marketSettlementSelectors());
        _assertSelectorRouting(
            deployment.diamond, deployment.multiOutcomeOrderbookFacet, multiOutcomeOrderbookSelectors()
        );
        _assertSelectorRouting(
            deployment.diamond, deployment.multiOutcomeOrderbookViewFacet, multiOutcomeOrderbookViewSelectors()
        );
        _assertSelectorRouting(
            deployment.diamond, deployment.nativeBinaryPositionFacet, nativeBinaryPositionSelectors()
        );
        _assertSelectorRouting(deployment.diamond, deployment.comboCoreFacet, comboCoreSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.comboSettlementFacet, comboSettlementSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.comboBranchFacet, comboBranchSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.comboViewFacet, comboViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.comboMarketFacet, comboMarketSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parimutuelFacet, parimutuelSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayAdminFacet, parlayAdminSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayUnderwritingFacet, parlayUnderwritingSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayBudgetFacet, parlayBudgetSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlaySettlementFacet, parlaySettlementSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayBookFacet, parlayBookSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayViewFacet, parlayViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayMulticallFacet, parlayMulticallSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.tradeRouterFacet, tradeRouterSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.vaultRouterFacet, vaultRouterSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.delayedOrderFacet, delayedOrderSelectors());
    }

    function _verifyFullDeployment(FullDeployment memory deployment, FullDeploymentConfig memory config) internal view {
        _verifyDeployment(deployment.market);
        require(deployment.faucet != address(0), "zero faucet");

        MarketFactoryTypes.MarketConfigView memory marketConfig =
            IMarketFactoryFacet(deployment.market.diamond).getMarketConfig();
        require(OwnershipFacet(deployment.market.diamond).owner() == config.market.owner, "owner mismatch");
        require(marketConfig.defaultConditionalTokens == deployment.market.conditionalTokens, "ctf mismatch");
        require(marketConfig.collateralToken == deployment.eveUSDC, "collateral mismatch");
        require(marketConfig.eveToken == deployment.eveToken, "eve token mismatch");
        require(marketConfig.stakingVault == deployment.seveUsdcVault, "staking vault mismatch");
        require(
            marketConfig.evesPositionManager == deployment.market.evesPositionManager, "eves position manager mismatch"
        );
        require(
            marketConfig.parimutuelShareToken == deployment.market.parimutuelShareToken, "parimutuel token mismatch"
        );
        _verifyParlayDeployment(deployment, config);
        require(
            marketConfig.orderbookFeeConfig.entryFeeBps == config.market.orderbookEntryFeeBps,
            "orderbook entry fee mismatch"
        );
        require(
            marketConfig.orderbookFeeConfig.makerFeeBps == config.market.orderbookMakerFeeBps,
            "orderbook maker fee mismatch"
        );
        require(
            marketConfig.orderbookFeeConfig.creatorFeeBps == config.market.orderbookCreatorFeeBps,
            "orderbook creator fee mismatch"
        );
        require(
            marketConfig.orderbookFeeConfig.protocolFeeBps == config.market.orderbookProtocolFeeBps,
            "orderbook protocol fee mismatch"
        );
        require(
            marketConfig.orderbookFeeConfig.vaultFeeBps == config.market.orderbookVaultFeeBps,
            "orderbook vault fee mismatch"
        );
        require(marketConfig.spotFeeConfig.tradeFeeBps == config.market.spotTradeFeeBps, "spot trade fee mismatch");
        require(marketConfig.spotFeeConfig.makerFeeBps == config.market.spotMakerFeeBps, "spot maker fee mismatch");
        require(
            marketConfig.spotFeeConfig.protocolFeeBps == config.market.spotProtocolFeeBps, "spot protocol fee mismatch"
        );
        require(marketConfig.spotFeeConfig.vaultFeeBps == config.market.spotVaultFeeBps, "spot vault fee mismatch");
        require(marketConfig.comboFeeConfig.tradeFeeBps == config.market.comboTradeFeeBps, "combo trade fee mismatch");
        require(marketConfig.comboFeeConfig.makerFeeBps == config.market.comboMakerFeeBps, "combo maker fee mismatch");
        require(
            marketConfig.comboFeeConfig.creatorFeeBps == config.market.comboCreatorFeeBps, "combo creator fee mismatch"
        );
        require(
            marketConfig.comboFeeConfig.protocolFeeBps == config.market.comboProtocolFeeBps,
            "combo protocol fee mismatch"
        );
        require(marketConfig.comboFeeConfig.vaultFeeBps == config.market.comboVaultFeeBps, "combo vault fee mismatch");
        require(
            marketConfig.parimutuelFeeConfig.entryFeeBps == config.market.parimutuelEntryFeeBps,
            "parimutuel entry fee mismatch"
        );
        require(
            marketConfig.parimutuelFeeConfig.creatorFeeBps == config.market.parimutuelCreatorFeeBps,
            "parimutuel creator fee mismatch"
        );
        require(
            marketConfig.parimutuelFeeConfig.protocolFeeBps == config.market.parimutuelProtocolFeeBps,
            "parimutuel protocol fee mismatch"
        );
        require(
            marketConfig.parimutuelFeeConfig.vaultFeeBps == config.market.parimutuelVaultFeeBps,
            "parimutuel vault fee mismatch"
        );
        require(marketConfig.parimutuelMinEntry == config.market.parimutuelMinEntry, "parimutuel min mismatch");
        require(
            marketConfig.parimutuelCreationSeedAmount == config.market.parimutuelCreationSeedAmount,
            "parimutuel seed mismatch"
        );
        uint16[8] memory parimutuelMultipliers =
            IParimutuelFacet(deployment.market.diamond).getParimutuelEpochMultipliers();
        uint16[8] memory expectedParimutuelMultipliers = _defaultParimutuelEpochMultipliers();
        for (uint256 index = 0; index < expectedParimutuelMultipliers.length; ++index) {
            require(parimutuelMultipliers[index] == expectedParimutuelMultipliers[index], "parimutuel epoch mismatch");
        }
        require(marketConfig.spotBookCreationFee == config.market.spotBookCreationFee, "spot book fee mismatch");
        require(
            marketConfig.comboMarketCreationFee == config.market.comboMarketCreationFee, "combo market fee mismatch"
        );
        require(
            marketConfig.delayedOrderProtectionDelayBlocks == config.market.delayedOrderProtectionDelayBlocks,
            "delayed protection mismatch"
        );
        require(
            marketConfig.delayedOrderExecutionGraceBlocks == config.market.delayedOrderExecutionGraceBlocks,
            "delayed grace mismatch"
        );
        require(
            marketConfig.delayedOrderRestingDurationMinutes == config.market.delayedOrderRestingDurationMinutes,
            "delayed resting mismatch"
        );
        require(
            marketConfig.delayedOrderProcessorFeeShareBps == config.market.delayedOrderProcessorFeeShareBps,
            "delayed processor fee mismatch"
        );
        require(
            marketConfig.delayedOrderProcessingMode == config.market.delayedOrderProcessingMode, "delayed mode mismatch"
        );

        require(EveUSDC(deployment.eveUSDC).usdc() == deployment.usdcToken, "eveUSDC usdc mismatch");
        require(EveUSDC(deployment.eveUSDC).onramp() == config.eveUsdcOnramp, "eveUSDC onramp mismatch");
        require(EveUSDC(deployment.eveUSDC).offramp() == config.eveUsdcOfframp, "eveUSDC offramp mismatch");

        require(SEveUSDCVault(deployment.seveUsdcVault).owner() == config.market.owner, "vault owner mismatch");
        require(SEveUSDCVault(deployment.seveUsdcVault).asset() == deployment.eveUSDC, "vault asset mismatch");
        require(SEveUSDCVault(deployment.seveUsdcVault).feeRecipient() == config.feeRecipient, "fee recipient mismatch");
        require(SEveUSDCVault(deployment.seveUsdcVault).aumFeeBps() == config.aumFeeBps, "aum fee mismatch");
        if (config.initialVaultBootstrap != 0) {
            require(SEveUSDCVault(deployment.seveUsdcVault).totalSupply() != 0, "vault bootstrap missing");
        }
        require(
            SEveUSDCVault(deployment.seveUsdcVault).lendingContract() == deployment.seveUsdcLending, "lending mismatch"
        );

        require(SEveUSDCLending(deployment.seveUsdcLending).owner() == config.market.owner, "lending owner mismatch");
        require(
            address(SEveUSDCLending(deployment.seveUsdcLending).vault()) == deployment.seveUsdcVault, "vault link mismatch"
        );
        require(
            address(SEveUSDCLending(deployment.seveUsdcLending).eveUSDC()) == deployment.eveUSDC, "eveUSDC link mismatch"
        );
        require(
            SEveUSDCLending(deployment.seveUsdcLending).approvedRouters(deployment.makerLendingRouter),
            "router approval mismatch"
        );

        (
            uint16 maxLtvBps,
            uint16 originationFeeBps,
            uint16 extensionFeeBps,
            uint32 minDurationSeconds,
            uint32 maxDurationSeconds,
            uint32 gracePeriodSeconds
        ) = SEveUSDCLending(deployment.seveUsdcLending).config();
        require(maxLtvBps == config.lendingMaxLtvBps, "ltv mismatch");
        require(originationFeeBps == config.lendingOriginationFeeBps, "origination mismatch");
        require(extensionFeeBps == config.lendingExtensionFeeBps, "extension mismatch");
        require(minDurationSeconds == config.lendingMinDurationSeconds, "min duration mismatch");
        require(maxDurationSeconds == config.lendingMaxDurationSeconds, "max duration mismatch");
        require(gracePeriodSeconds == config.lendingGracePeriodSeconds, "grace mismatch");
        require(
            SEveUSDCLending(deployment.seveUsdcLending).lendingFeeRecipientBps() == config.lendingFeeRecipientBps,
            "lending fee recipient mismatch"
        );

        require(
            MakerLendingRouter(deployment.makerLendingRouter).usdc() == deployment.usdcToken,
            "maker router usdc mismatch"
        );
        require(
            MakerLendingRouter(deployment.makerLendingRouter).eveUSDC() == deployment.eveUSDC,
            "maker router eveUSDC mismatch"
        );
        require(
            MakerLendingRouter(deployment.makerLendingRouter).vault() == deployment.seveUsdcVault,
            "maker router vault mismatch"
        );
        require(
            MakerLendingRouter(deployment.makerLendingRouter).lending() == deployment.seveUsdcLending,
            "maker router lending mismatch"
        );
        require(
            MakerLendingRouter(deployment.makerLendingRouter).diamond() == deployment.market.diamond,
            "maker router diamond mismatch"
        );
        require(
            MakerLendingRouter(deployment.makerLendingRouter).defaultConditionalTokens()
                == deployment.market.conditionalTokens,
            "maker router ctf mismatch"
        );
        if (config.enableEveEthMarkets) {
            require(deployment.wethToken != address(0), "WETH missing");
            require(deployment.eveETH != address(0), "eveETH missing");
            MarketFactoryTypes.CollateralProfileView memory profile =
                IMarketFactoryFacet(deployment.market.diamond).getCollateralProfile(EVE_ETH_PROFILE_ID);
            require(profile.collateralToken == deployment.eveETH, "eveETH profile collateral mismatch");
            require(profile.wrapperToken == deployment.wethToken, "eveETH profile wrapper mismatch");
            require(profile.payoutUnit == config.eveEthPayoutUnit, "eveETH profile payout mismatch");
            require(profile.marketCreationFee == config.eveEthMarketCreationFee, "eveETH profile fee mismatch");
            require(profile.enabled, "eveETH profile disabled");
            (uint128 profileSeed, uint128 profileMinEntry) =
                IMarketFactoryFacet(deployment.market.diamond).getCollateralProfileParimutuelConfig(EVE_ETH_PROFILE_ID);
            require(profileSeed == config.eveEthParimutuelCreationSeedAmount, "eveETH parimutuel seed mismatch");
            require(profileMinEntry == config.eveEthParimutuelMinEntry, "eveETH parimutuel min mismatch");
            uint128 profileParlayFee = IMarketFactoryFacet(deployment.market.diamond)
                .getCollateralProfileParlayUnderwritingFee(EVE_ETH_PROFILE_ID);
            require(profileParlayFee == config.eveEthParlayUnderwritingFee, "eveETH parlay fee mismatch");
        }

        require(Faucet(deployment.faucet).owner() == config.faucetOwner, "faucet owner mismatch");
        if (config.faucetUsdcEnabled) {
            (uint256 usdcAmount, bool usdcEnabled, bool usdcExists) =
                Faucet(deployment.faucet).getTokenConfig(deployment.usdcToken);
            require(usdcExists, "faucet usdc missing");
            require(usdcEnabled, "faucet usdc disabled");
            require(usdcAmount == config.faucetUsdcClaimAmount, "faucet usdc amount mismatch");
        }
        if (config.faucetEveEnabled) {
            (uint256 bondAmount, bool eveEnabled, bool eveExists) =
                Faucet(deployment.faucet).getTokenConfig(deployment.eveToken);
            require(eveExists, "faucet eve missing");
            require(eveEnabled, "faucet eve disabled");
            require(bondAmount == config.faucetEveClaimAmount, "faucet eve amount mismatch");
        }
    }

    function _verifyParlayDeployment(FullDeployment memory deployment, FullDeploymentConfig memory config)
        internal
        view
    {
        ParlayTypes.ParlayConfigView memory parlayConfig = ParlayAdminFacet(deployment.market.diamond).getParlayConfig();
        require(parlayConfig.ticketToken == deployment.market.parlayTicketToken, "parlay ticket token mismatch");
        require(parlayConfig.feeRecipient == config.market.parlayFeeRecipient, "parlay fee recipient mismatch");
        require(parlayConfig.underwritingFee == config.market.parlayUnderwritingFee, "parlay fee mismatch");
        require(parlayConfig.vaultFeeBps == config.market.parlayVaultFeeBps, "parlay vault fee mismatch");
        require(
            parlayConfig.feeRecipientBps == config.market.parlayFeeRecipientBps, "parlay fee recipient bps mismatch"
        );
    }

    function _assertSelectorRouting(address diamond, address facetAddress, bytes4[] memory selectors) internal view {
        for (uint256 index = 0; index < selectors.length; ++index) {
            require(
                DiamondLoupeFacet(diamond).facetAddress(selectors[index]) == facetAddress, "selector route mismatch"
            );
        }
    }

    function _resolveConditionalTokens(address configuredAddress, string memory artifactPath)
        internal
        returns (address conditionalTokens)
    {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }

        bytes memory creationCode = _loadConditionalTokensCreationCode(artifactPath);
        require(creationCode.length != 0, "empty conditional tokens bytecode");

        assembly {
            conditionalTokens := create(0, add(creationCode, 0x20), mload(creationCode))
        }

        require(conditionalTokens != address(0), "conditional tokens deploy failed");
    }

    function _resolveUsdcToken(address configuredAddress, address configuredEveUSDC) internal returns (address) {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }
        if (configuredEveUSDC != address(0)) {
            return EveUSDC(configuredEveUSDC).usdc();
        }

        return address(new MockUSDC());
    }

    function _resolveEveToken(address configuredAddress) internal returns (address) {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }

        return address(new MockEveToken());
    }

    function _resolveEveUSDC(address configuredAddress, address usdcToken, address onramp, address offramp)
        internal
        returns (address)
    {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }

        return address(new EveUSDC(usdcToken, onramp, offramp));
    }

    function _resolveWeth(address configuredAddress, bool deployMockWeth) internal returns (address) {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }
        if (!deployMockWeth) {
            return address(0);
        }

        return address(new CanonicalWETH9());
    }

    function _resolveEveETH(address configuredAddress, address wethToken, bool deployEveETH)
        internal
        returns (address)
    {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }
        if (!deployEveETH) {
            return address(0);
        }

        return address(new EveETH(wethToken));
    }

    function _resolveParimutuelShareToken(address configuredAddress, address diamond) internal returns (address) {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }

        return address(new ParimutuelShareToken(diamond, "uri://parimutuel/{id}"));
    }

    function _resolveParlayTicketToken(address configuredAddress, address diamond) internal returns (address) {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }

        return address(new ParlayTicketToken(diamond, "uri://parlay/{id}"));
    }

    function _resolveEvesPositionManager(address configuredAddress, address diamond) internal returns (address) {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }

        return address(new EvesPositionManager(diamond, "uri://eves-position/{id}"));
    }

    function _resolveSEveUSDCVault(
        address configuredAddress,
        address eveUSDC,
        address owner,
        address feeRecipient,
        uint16 aumFeeBps,
        address revenueNotifier
    ) internal returns (address) {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }

        return address(new SEveUSDCVault(eveUSDC, owner, feeRecipient, aumFeeBps, revenueNotifier));
    }

    function _resolveSEveUSDCLending(address configuredAddress, address vault, address eveUSDC, address owner)
        internal
        returns (address)
    {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }

        return address(new SEveUSDCLending(vault, eveUSDC, owner));
    }

    function _resolveMakerLendingRouter(
        address configuredAddress,
        address usdcToken,
        address eveUSDC,
        address vault,
        address lending,
        address diamond,
        address conditionalTokens
    ) internal returns (address) {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }

        return address(new MakerLendingRouter(usdcToken, eveUSDC, vault, lending, diamond, conditionalTokens));
    }

    function _loadConditionalTokensCreationCode(string memory artifactPath)
        internal
        view
        returns (bytes memory creationCode)
    {
        string memory artifactJson = vm.readFile(string.concat(vm.projectRoot(), "/", artifactPath));

        if (artifactJson.keyExists(".bytecode.object")) {
            return artifactJson.readBytes(".bytecode.object");
        }

        return artifactJson.readBytes(".bytecode");
    }

    function _cut(address facetAddress, bytes4[] memory selectors)
        internal
        pure
        returns (DiamondCutFacet.FacetCut memory cut)
    {
        cut = DiamondCutFacet.FacetCut({
            facetAddress: facetAddress, action: DiamondCutFacet.FacetCutAction.Add, functionSelectors: selectors
        });
    }

    function _defaultParimutuelEpochMultipliers() internal pure returns (uint16[8] memory multipliersBps) {
        multipliersBps = [uint16(20_000), 15_000, 11_500, 10_000, 8_500, 7_000, 5_500, 4_000];
    }
}
