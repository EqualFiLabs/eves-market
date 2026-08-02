// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {stdJson} from "../lib/forge-std/src/StdJson.sol";

import {IStaticsDollarCore} from "@statics/dollar/core/interfaces/IStaticsDollarCore.sol";
import {IStaticsDollarCoreTypes} from "@statics/dollar/interfaces/IStaticsDollarCoreTypes.sol";
import {IStaticsDollarGateway} from "@statics/dollar/interfaces/IStaticsDollarGateway.sol";
import {IStaticsDollar} from "@statics/dollar/interfaces/IStaticsDollar.sol";
import {EveMarketDiamond} from "../src/EveMarketDiamond.sol";
import {Faucet} from "../src/Faucet.sol";
import {MLOInsuranceFund} from "../src/MLOInsuranceFund.sol";
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
import {MarketGroupFacet} from "../src/facets/MarketGroupFacet.sol";
import {MarketSettlementFacet} from "../src/facets/MarketSettlementFacet.sol";
import {MarketViewFacet} from "../src/facets/MarketViewFacet.sol";
import {MarginAccountFacet} from "../src/facets/MarginAccountFacet.sol";
import {MarkOracleFacet} from "../src/facets/MarkOracleFacet.sol";
import {MLOPredictionAdapterFacet} from "../src/facets/MLOPredictionAdapterFacet.sol";
import {MLOPredictionBidTradeFacet} from "../src/facets/MLOPredictionBidTradeFacet.sol";
import {MLOPredictionAskRouteFacet} from "../src/facets/MLOPredictionAskRouteFacet.sol";
import {MLOPredictionCurveFacet} from "../src/facets/MLOPredictionCurveFacet.sol";
import {MLOPredictionPostFacet} from "../src/facets/MLOPredictionPostFacet.sol";
import {MLOPredictionSettlementFacet} from "../src/facets/MLOPredictionSettlementFacet.sol";
import {MLOPredictionTradeFacet} from "../src/facets/MLOPredictionTradeFacet.sol";
import {MLOPredictionRecoveryFacet} from "../src/facets/MLOPredictionRecoveryFacet.sol";
import {MLOPredictionUpdateFacet} from "../src/facets/MLOPredictionUpdateFacet.sol";
import {MLOProfitShareFacet} from "../src/facets/MLOProfitShareFacet.sol";
import {SeniorCapitalFacet} from "../src/facets/SeniorCapitalFacet.sol";
import {SeniorCapitalViewFacet} from "../src/facets/SeniorCapitalViewFacet.sol";
import {MultiOutcomeOrderbookFacet} from "../src/facets/MultiOutcomeOrderbookFacet.sol";
import {NegRiskConfigFacet} from "../src/facets/NegRiskConfigFacet.sol";
import {CTFPositionViewFacet} from "../src/facets/CTFPositionViewFacet.sol";
import {MultiOutcomeOrderbookViewFacet} from "../src/facets/MultiOutcomeOrderbookViewFacet.sol";
import {ComboCoreFacet} from "../src/facets/native/ComboCoreFacet.sol";
import {ComboSettlementFacet} from "../src/facets/native/ComboSettlementFacet.sol";
import {ComboViewFacet} from "../src/facets/native/ComboViewFacet.sol";
import {ComboMarketFacet} from "../src/facets/native/ComboMarketFacet.sol";
import {OBRResolutionFacet} from "../src/facets/OBRResolutionFacet.sol";
import {OwnershipFacet} from "../src/facets/OwnershipFacet.sol";
import {FeeConfigFacet} from "../src/facets/FeeConfigFacet.sol";
import {ParimutuelFacet} from "../src/facets/ParimutuelFacet.sol";
import {ParimutuelViewFacet} from "../src/facets/ParimutuelViewFacet.sol";
import {QuoteEnvelopeFacet} from "../src/facets/QuoteEnvelopeFacet.sol";
import {ResolverJuryFacet} from "../src/facets/ResolverJuryFacet.sol";
import {ResolverRegistryFacet} from "../src/facets/ResolverRegistryFacet.sol";
import {ResolverRegistryReputationFacet} from "../src/facets/ResolverRegistryReputationFacet.sol";
import {ResolverRegistryRewardsFacet} from "../src/facets/ResolverRegistryRewardsFacet.sol";
import {ResolverRegistryViewFacet} from "../src/facets/ResolverRegistryViewFacet.sol";
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
import {BookSellFacet} from "../src/facets/BookSellFacet.sol";
import {BookViewFacet} from "../src/facets/BookViewFacet.sol";
import {CollateralTradeExecutionFacet} from "../src/facets/CollateralTradeExecutionFacet.sol";
import {CollateralTradeRouterFacet} from "../src/facets/CollateralTradeRouterFacet.sol";
import {CollateralTradeRouterExactFacet} from "../src/facets/CollateralTradeRouterExactFacet.sol";
import {StaticsDollarTradeRouterFacet} from "../src/facets/StaticsDollarTradeRouterFacet.sol";
import {TradeRouterBookFacet} from "../src/facets/TradeRouterBookFacet.sol";
import {TradeRouterBookSellFacet} from "../src/facets/TradeRouterBookSellFacet.sol";
import {CollateralTradeRouterSellFacet} from "../src/facets/CollateralTradeRouterSellFacet.sol";
import {CollateralTradeRouterPreviewFacet} from "../src/facets/CollateralTradeRouterPreviewFacet.sol";
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
import {ICollateralTradeExecution} from "../src/interfaces/ICollateralTradeExecution.sol";
import {IMarketFactoryFacet} from "../src/interfaces/IMarketFactoryFacet.sol";
import {IMarketSettlementFacet} from "../src/interfaces/IMarketSettlementFacet.sol";
import {IMarginAccountFacet} from "../src/interfaces/IMarginAccountFacet.sol";
import {IMarkOracleFacet} from "../src/interfaces/IMarkOracleFacet.sol";
import {IMLOPredictionAdapterFacet} from "../src/interfaces/IMLOPredictionAdapterFacet.sol";
import {IMLOProfitShareFacet} from "../src/interfaces/IMLOProfitShareFacet.sol";
import {ISeniorCapitalFacet} from "../src/interfaces/ISeniorCapitalFacet.sol";
import {IMultiOutcomeOrderbookFacet} from "../src/interfaces/IMultiOutcomeOrderbookFacet.sol";
import {INegRiskConfigFacet} from "../src/interfaces/INegRiskConfigFacet.sol";
import {ICTFPositionViewFacet} from "../src/interfaces/ICTFPositionViewFacet.sol";
import {ITradeRouterBook} from "../src/interfaces/ITradeRouterBook.sol";
import {IComboCoreFacet} from "../src/interfaces/IComboCoreFacet.sol";
import {IComboSettlementFacet} from "../src/interfaces/IComboSettlementFacet.sol";
import {IComboViewFacet} from "../src/interfaces/IComboViewFacet.sol";
import {IComboMarketFacet} from "../src/interfaces/IComboMarketFacet.sol";
import {IOBRResolutionFacet} from "../src/interfaces/IOBRResolutionFacet.sol";
import {IParimutuelFacet} from "../src/interfaces/IParimutuelFacet.sol";
import {IQuoteEnvelopeFacet} from "../src/interfaces/IQuoteEnvelopeFacet.sol";
import {IResolverJuryFacet} from "../src/interfaces/IResolverJuryFacet.sol";
import {IResolverRegistryFacet} from "../src/interfaces/IResolverRegistryFacet.sol";
import {ITradeRouter} from "../src/interfaces/ITradeRouter.sol";
import {ResolverJuryInit} from "../src/init/ResolverJuryInit.sol";
import {LibEveMarket} from "../src/libraries/LibEveMarket.sol";
import {ParlayTypes} from "../src/types/ParlayTypes.sol";
import {OwnershipConfigTypes} from "../src/types/OwnershipConfigTypes.sol";
import {MLOPredictionTypes} from "../src/types/MLOPredictionTypes.sol";
import {ParimutuelShareToken} from "../src/tokens/ParimutuelShareToken.sol";
import {EveIdentity} from "../src/tokens/EveIdentity.sol";
import {EvesPositionManager} from "../src/tokens/EvesPositionManager.sol";
import {EvesNegRiskAdapter} from "../src/EvesNegRiskAdapter.sol";
import {EvesCTFSettlementAdapter} from "../src/EvesCTFSettlementAdapter.sol";
import {ParlayTicketToken} from "../src/tokens/ParlayTicketToken.sol";
import {TestnetEVE} from "../src/mocks/TestnetEVE.sol";
import {MarketFactoryTypes} from "../src/types/MarketFactoryTypes.sol";
import {MarginTypes} from "../src/types/MarginTypes.sol";

contract DeployScript is Script {
    using SafeERC20 for IERC20;
    using stdJson for string;

    uint256 internal constant EIP170_MAX_CODE_SIZE = 24_576;
    uint64 internal constant DEFAULT_INITIAL_GOVERNANCE_DELAY = 15 minutes;
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46630;

    string internal constant DEFAULT_CONDITIONAL_TOKENS_ARTIFACT_PATH =
        "out/conditional-tokens/ConditionalTokens.sol/ConditionalTokens.json";
    uint8 internal constant STATICS_DOLLAR_PROFILE_ID = 1;

    error RobinhoodTestnetConditionalTokensRequired();

    struct StaticsDollarStackConfig {
        address core;
        uint256 peggedProfileId;
        uint128 payoutUnit;
        uint128 marketCreationFee;
        uint128 parimutuelCreationSeedAmount;
        uint128 parimutuelMinEntry;
        uint128 parlayUnderwritingFee;
        bool enableMarkets;
    }

    struct StaticsDollarStackDeployment {
        address staticsDollar;
        address core;
        address staticsDiamond;
    }

    struct DeploymentConfig {
        address owner;
        uint64 governanceDelay;
        uint64 mloProfitSplitDelay;
        address conditionalTokens;
        string conditionalTokensArtifactPath;
        address collateralToken;
        address eveToken;
        address eveTreasury;
        address evesPositionManager;
        address parimutuelShareToken;
        address parlayTicketToken;
        address parlayFeeRecipient;
        uint128 parlayUnderwritingFee;
        uint16 parlaySeniorPoolFeeBps;
        uint16 parlayFeeRecipientBps;
        uint16 orderbookEntryFeeBps;
        uint16 orderbookMakerFeeBps;
        uint16 orderbookCreatorFeeBps;
        uint16 orderbookProtocolFeeBps;
        uint16 orderbookSeniorPoolFeeBps;
        uint16 orderbookResolverFeeBps;
        uint16 spotTradeFeeBps;
        uint16 spotMakerFeeBps;
        uint16 spotProtocolFeeBps;
        uint16 spotSeniorPoolFeeBps;
        uint16 spotResolverFeeBps;
        uint16 comboTradeFeeBps;
        uint16 comboMakerFeeBps;
        uint16 comboCreatorFeeBps;
        uint16 comboProtocolFeeBps;
        uint16 comboSeniorPoolFeeBps;
        uint16 comboResolverFeeBps;
        uint16 parimutuelEntryFeeBps;
        uint16 parimutuelCreatorFeeBps;
        uint16 parimutuelProtocolFeeBps;
        uint16 parimutuelSeniorPoolFeeBps;
        uint16 parimutuelResolverFeeBps;
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
        uint32 maxDelayedOrderRouteLength;
        uint128 minDelayedOrderQuoteWad;
        uint128 minDelayedOrderBaseWad;
        uint128 mloDefaultFundingRatePerSecondWad;
    }

    struct Deployment {
        address diamond;
        address conditionalTokens;
        address diamondCutFacet;
        address diamondLoupeFacet;
        address ownershipFacet;
        address feeConfigFacet;
        address marketFactoryFacet;
        address marketGroupFacet;
        address marketViewFacet;
        address marginAccountFacet;
        address markOracleFacet;
        address quoteEnvelopeFacet;
        address mloPredictionAdapterFacet;
        address mloPredictionCurveFacet;
        address mloPredictionPostFacet;
        address mloPredictionUpdateFacet;
        address mloPredictionTradeFacet;
        address mloPredictionAskRouteFacet;
        address mloPredictionBidTradeFacet;
        address mloPredictionSettlementFacet;
        address mloPredictionRecoveryFacet;
        address mloProfitShareFacet;
        address seniorCapitalFacet;
        address seniorCapitalViewFacet;
        address tradeRouterBookFacet;
        address tradeRouterBookSellFacet;
        address curveInventoryFacet;
        address curveLifecycleFacet;
        address curveCLOBFacet;
        address curveViewFacet;
        address delayedOrderFacet;
        address bookFacet;
        address bookOrderFacet;
        address bookTradeFacet;
        address bookSellFacet;
        address bookViewFacet;
        address bondManagerFacet;
        address bondTokenGateFacet;
        address obrResolutionFacet;
        address resolverRegistryFacet;
        address resolverRegistryViewFacet;
        address resolverRegistryRewardsFacet;
        address resolverRegistryReputationFacet;
        address resolverJuryFacet;
        address eveIdentity;
        address feeRouterFacet;
        address marketSettlementFacet;
        address multiOutcomeOrderbookFacet;
        address multiOutcomeOrderbookViewFacet;
        address negRiskConfigFacet;
        address ctfPositionViewFacet;
        address comboCoreFacet;
        address comboSettlementFacet;
        address comboViewFacet;
        address comboMarketFacet;
        address evesPositionManager;
        address negRiskAdapter;
        address ctfSettlementAdapter;
        address parimutuelFacet;
        address parimutuelViewFacet;
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
        address tradeRouterExactFacet;
        address tradeRouterSellFacet;
        address staticsDollarTradeRouterFacet;
        address collateralTradeExecutionFacet;
        address collateralTradeRouterPreviewFacet;
    }

    struct FullDeploymentConfig {
        DeploymentConfig market;
        address usdcToken;
        address mloInsuranceFund;
        address feeRecipient;
        uint256 initialEveMint;
        uint256 initialMloInsuranceBootstrapUsdg;
        uint256 initialSeniorCapitalBootstrapUsdg;
        uint16 mloFundingSeniorBps;
        uint16 mloMaxCleanupBatch;
        address faucetOwner;
        StaticsDollarStackConfig staticsDollar;
        bool faucetUsdcEnabled;
        bool faucetEveEnabled;
        uint256 faucetUsdcClaimAmount;
        uint256 faucetEveClaimAmount;
        uint256 faucetUsdcFundAmount;
        uint256 faucetEveFundAmount;
    }

    struct FullDeployment {
        Deployment market;
        address usdcToken;
        address eveToken;
        address mloInsuranceFund;
        address faucet;
        address staticsDollar;
        address staticsDollarCore;
        address staticsDiamond;
    }

    struct ReleaseSurface {
        string[] criticalNames;
        address[] criticalAddresses;
        bytes32[] criticalRuntimeCodeHashes;
        address[] facetAddresses;
        bytes32[] facetRuntimeCodeHashes;
        uint256[] facetSelectorCounts;
        bytes32[] selectors;
        address[] selectorFacets;
        bytes32[] absentSelectors;
    }

    function run() external virtual returns (FullDeployment memory deployment) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address temporaryOwner = vm.addr(deployerPrivateKey);
        FullDeploymentConfig memory config = _loadFullConfigFromEnv();

        vm.startBroadcast(deployerPrivateKey);
        deployment = deployFullStack(config, temporaryOwner);
        vm.stopBroadcast();

        string memory manifestPath = vm.envOr("DEPLOYMENT_MANIFEST_PATH", string(""));
        if (bytes(manifestPath).length != 0) {
            writeFullDeploymentManifest(
                deployment, config, manifestPath, vm.envString("RELEASE_COMMIT"), vm.envString("STATICS_RELEASE_COMMIT")
            );
        }
    }

    function deployFullStack(FullDeploymentConfig memory config, address temporaryOwner)
        public
        returns (FullDeployment memory deployment)
    {
        config = _withFullConfigDefaults(config);
        _validateFullConfig(config, temporaryOwner);

        bool autoDeployEveToken = config.market.eveToken == address(0);

        deployment.usdcToken = config.usdcToken;
        deployment.eveToken = _resolveEveToken(config.market.eveToken, temporaryOwner);
        StaticsDollarStackDeployment memory staticsDollarDeployment = _resolveStaticsDollarStack(config.staticsDollar);
        deployment.staticsDollar = staticsDollarDeployment.staticsDollar;
        deployment.staticsDollarCore = staticsDollarDeployment.core;
        deployment.staticsDiamond = staticsDollarDeployment.staticsDiamond;
        _validateStaticsDollarIntegration(deployment, config);

        address finalOwner = config.market.owner;
        DeploymentConfig memory marketConfig = config.market;
        marketConfig.owner = temporaryOwner;
        marketConfig.collateralToken = deployment.staticsDollar;
        marketConfig.eveToken = deployment.eveToken;
        if (marketConfig.bondToken == address(0)) {
            marketConfig.bondToken = deployment.staticsDollar;
        }
        marketConfig.parlayFeeRecipient = config.feeRecipient;

        deployment.market = _deploy(marketConfig, temporaryOwner, false);
        config.market.owner = finalOwner;
        deployment.mloInsuranceFund = _resolveMLOInsuranceFund(
            config.mloInsuranceFund, deployment.staticsDollar, deployment.market.diamond, deployment.market.diamond
        );
        deployment.faucet = _deployAndConfigureFaucet(deployment, config, temporaryOwner);

        _configureFullStack(deployment, config);
        _mintFullStackEveToken(deployment, config, autoDeployEveToken);
        _fundFaucet(deployment, config, autoDeployEveToken);
        _finalizeEveTokenOwnership(deployment, config, autoDeployEveToken);
        _bootstrapMLOLiquidity(deployment, config, temporaryOwner);
        DiamondCutFacet(deployment.market.diamond).finalizeGovernanceDelay(finalOwner, config.market.governanceDelay);
        _verifyFullDeployment(deployment, config);
    }

    function deploy(DeploymentConfig memory config, address temporaryOwner)
        public
        returns (Deployment memory deployment)
    {
        deployment = _deploy(config, temporaryOwner, true);
    }

    function _deploy(DeploymentConfig memory config, address temporaryOwner, bool finalizeGovernance)
        private
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
        deployment.feeConfigFacet = address(new FeeConfigFacet());
        deployment.marketFactoryFacet = address(new MarketFactoryFacet());
        deployment.marketGroupFacet = address(new MarketGroupFacet());
        deployment.marketViewFacet = address(new MarketViewFacet());
        deployment.marginAccountFacet = address(new MarginAccountFacet());
        deployment.markOracleFacet = address(new MarkOracleFacet());
        deployment.quoteEnvelopeFacet = address(new QuoteEnvelopeFacet());
        deployment.mloPredictionAdapterFacet = address(new MLOPredictionAdapterFacet());
        deployment.mloPredictionCurveFacet = address(new MLOPredictionCurveFacet());
        deployment.mloPredictionPostFacet = address(new MLOPredictionPostFacet());
        deployment.mloPredictionUpdateFacet = address(new MLOPredictionUpdateFacet());
        deployment.mloPredictionTradeFacet = address(new MLOPredictionTradeFacet());
        deployment.mloPredictionAskRouteFacet = address(new MLOPredictionAskRouteFacet());
        deployment.mloPredictionBidTradeFacet = address(new MLOPredictionBidTradeFacet());
        deployment.mloPredictionSettlementFacet = address(new MLOPredictionSettlementFacet());
        deployment.mloPredictionRecoveryFacet = address(new MLOPredictionRecoveryFacet());
        deployment.mloProfitShareFacet = address(new MLOProfitShareFacet());
        deployment.seniorCapitalFacet = address(new SeniorCapitalFacet());
        deployment.seniorCapitalViewFacet = address(new SeniorCapitalViewFacet());
        deployment.tradeRouterBookFacet = address(new TradeRouterBookFacet());
        deployment.tradeRouterBookSellFacet = address(new TradeRouterBookSellFacet());
        deployment.curveInventoryFacet = address(new CurveInventoryFacet());
        deployment.curveLifecycleFacet = address(new CurveLifecycleFacet());
        deployment.curveCLOBFacet = address(new CurveCLOBFacet());
        deployment.curveViewFacet = address(new CurveViewFacet());
        deployment.delayedOrderFacet = address(new DelayedOrderFacet());
        deployment.bookFacet = address(new BookFacet());
        deployment.bookOrderFacet = address(new BookOrderFacet());
        deployment.bookTradeFacet = address(new BookTradeFacet());
        deployment.bookSellFacet = address(new BookSellFacet());
        deployment.bookViewFacet = address(new BookViewFacet());
        deployment.bondManagerFacet = address(new BondManagerFacet());
        deployment.bondTokenGateFacet = address(new BondTokenGateFacet());
        deployment.obrResolutionFacet = address(new OBRResolutionFacet());
        deployment.resolverRegistryFacet = address(new ResolverRegistryFacet());
        deployment.resolverRegistryViewFacet = address(new ResolverRegistryViewFacet());
        deployment.resolverRegistryRewardsFacet = address(new ResolverRegistryRewardsFacet());
        deployment.resolverRegistryReputationFacet = address(new ResolverRegistryReputationFacet());
        deployment.resolverJuryFacet = address(new ResolverJuryFacet());
        deployment.eveIdentity = address(new EveIdentity(deployment.diamond, "Eve Identity", "EVE-ID"));
        deployment.feeRouterFacet = address(new FeeRouterFacet());
        deployment.marketSettlementFacet = address(new MarketSettlementFacet());
        deployment.multiOutcomeOrderbookFacet = address(new MultiOutcomeOrderbookFacet());
        deployment.multiOutcomeOrderbookViewFacet = address(new MultiOutcomeOrderbookViewFacet());
        deployment.negRiskConfigFacet = address(new NegRiskConfigFacet());
        deployment.ctfPositionViewFacet = address(new CTFPositionViewFacet());
        deployment.comboCoreFacet = address(new ComboCoreFacet());
        deployment.comboSettlementFacet = address(new ComboSettlementFacet());
        deployment.comboViewFacet = address(new ComboViewFacet());
        deployment.comboMarketFacet = address(new ComboMarketFacet());
        deployment.evesPositionManager = _resolveEvesPositionManager(config.evesPositionManager, deployment.diamond);
        config.evesPositionManager = deployment.evesPositionManager;
        deployment.negRiskAdapter =
            address(new EvesNegRiskAdapter(deployment.conditionalTokens, config.collateralToken, deployment.diamond));
        deployment.ctfSettlementAdapter =
            address(new EvesCTFSettlementAdapter(deployment.conditionalTokens, config.collateralToken));
        deployment.parimutuelFacet = address(new ParimutuelFacet());
        deployment.parimutuelViewFacet = address(new ParimutuelViewFacet());
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
        deployment.tradeRouterFacet = address(new CollateralTradeRouterFacet());
        deployment.tradeRouterExactFacet = address(new CollateralTradeRouterExactFacet());
        deployment.tradeRouterSellFacet = address(new CollateralTradeRouterSellFacet());
        deployment.staticsDollarTradeRouterFacet = address(new StaticsDollarTradeRouterFacet());
        deployment.collateralTradeExecutionFacet = address(new CollateralTradeExecutionFacet());
        deployment.collateralTradeRouterPreviewFacet = address(new CollateralTradeRouterPreviewFacet());

        _addCoreFacets(deployment);
        _configureDeployment(deployment.diamond, config, deployment.negRiskAdapter, deployment.ctfSettlementAdapter);

        if (finalizeGovernance) {
            DiamondCutFacet(deployment.diamond).finalizeGovernanceDelay(config.owner, config.governanceDelay);
        } else {
            require(config.owner == temporaryOwner, "unfinalized owner mismatch");
        }

        if (finalizeGovernance) {
            _verifyDeployment(deployment, config.governanceDelay, config.mloProfitSplitDelay);
            require(OwnershipFacet(deployment.diamond).owner() == config.owner, "owner mismatch");
        }
    }

    function diamondCutSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](11);
        selectors[0] = DiamondCutFacet.diamondCut.selector;
        selectors[1] = DiamondCutFacet.freezeFacet.selector;
        selectors[2] = DiamondCutFacet.isSelectorFrozen.selector;
        selectors[3] = DiamondCutFacet.scheduleGovernanceOperation.selector;
        selectors[4] = DiamondCutFacet.cancelGovernanceOperation.selector;
        selectors[5] = DiamondCutFacet.finalizeGovernanceDelay.selector;
        selectors[6] = DiamondCutFacet.governanceOperationId.selector;
        selectors[7] = DiamondCutFacet.governanceOperationReadyAt.selector;
        selectors[8] = DiamondCutFacet.governanceDelay.selector;
        selectors[9] = DiamondCutFacet.governanceDelayFinalized.selector;
        selectors[10] = DiamondCutFacet.setGovernanceDelay.selector;
    }

    function loupeSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = DiamondLoupeFacet.facets.selector;
        selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
        selectors[3] = DiamondLoupeFacet.facetAddress.selector;
    }

    function ownershipSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](43);
        selectors[0] = OwnershipFacet.transferOwnership.selector;
        selectors[1] = OwnershipFacet.owner.selector;
        selectors[2] = OwnershipFacet.setResolutionBondConfig.selector;
        selectors[3] = OwnershipFacet.setMarketCreationFee.selector;
        selectors[4] = OwnershipFacet.setMarketCreationBond.selector;
        selectors[5] = OwnershipFacet.setPermissionlessCreationEnabled.selector;
        selectors[6] = OwnershipFacet.setDefaultConditionalTokens.selector;
        selectors[7] = OwnershipFacet.setCollateralToken.selector;
        selectors[8] = OwnershipFacet.setEveToken.selector;
        selectors[9] = OwnershipFacet.setEveTreasury.selector;
        selectors[10] = OwnershipFacet.setParimutuelConfig.selector;
        selectors[11] = OwnershipFacet.setDurationParams.selector;
        selectors[12] = OwnershipFacet.setDisputeWindow.selector;
        selectors[13] = OwnershipFacet.setCreatorSettleGrace.selector;
        selectors[14] = OwnershipFacet.setOpenResolutionTimeout.selector;
        selectors[15] = OwnershipFacet.setMaxEscalation.selector;
        selectors[16] = OwnershipFacet.registerCurveProfile.selector;
        selectors[17] = OwnershipFacet.setSpotBookCreationFee.selector;
        selectors[18] = OwnershipFacet.setParimutuelEpochWindowCap.selector;
        selectors[19] = OwnershipFacet.setParimutuelEpochMultipliers.selector;
        selectors[20] = OwnershipFacet.setMarketCreationBatchCap.selector;
        selectors[21] = OwnershipFacet.setEvesPositionManager.selector;
        selectors[22] = OwnershipFacet.setParimutuelCreationSeedAmount.selector;
        selectors[23] = OwnershipFacet.setComboMarketCreationFee.selector;
        selectors[24] = OwnershipFacet.setCollateralProfile.selector;
        selectors[25] = OwnershipFacet.setCollateralProfileEnabled.selector;
        selectors[26] = OwnershipFacet.setCollateralProfilePayoutUnit.selector;
        selectors[27] = OwnershipFacet.setCollateralProfileMarketCreationFee.selector;
        selectors[28] = OwnershipFacet.setCollateralProfileParimutuelCreationSeedAmount.selector;
        selectors[29] = OwnershipFacet.setCollateralProfileParimutuelMinEntry.selector;
        selectors[30] = OwnershipFacet.setCollateralProfileParlayUnderwritingFee.selector;
        selectors[31] = OwnershipFacet.setResolverJuryIdentitySettings.selector;
        selectors[32] = OwnershipFacet.setResolverJuryPoolSettings.selector;
        selectors[33] = OwnershipFacet.setResolverJuryRoundSettings.selector;
        selectors[34] = OwnershipFacet.setResolverJuryEconomicsSettings.selector;
        selectors[35] = OwnershipFacet.setResolutionMode.selector;
        selectors[36] = OwnershipFacet.setDelayedOrderConfig.selector;
        selectors[37] = OwnershipFacet.setDelayedOrderProcessing.selector;
        selectors[38] = OwnershipFacet.setDelayedOrderGuards.selector;
        selectors[39] = OwnershipFacet.setDelayedOrderProtocolProcessor.selector;
        selectors[40] = OwnershipFacet.setMarketDelayedExecution.selector;
        selectors[41] = OwnershipFacet.setBookDelayedExecution.selector;
        selectors[42] = OwnershipFacet.setStaticsDollarRail.selector;
    }

    function feeConfigSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = FeeConfigFacet.setOrderbookEntryFeeBps.selector;
        selectors[1] = FeeConfigFacet.setSpotTradeFeeBps.selector;
        selectors[2] = FeeConfigFacet.setComboTradeFeeBps.selector;
        selectors[3] = FeeConfigFacet.setOrderbookFeeSplit.selector;
        selectors[4] = FeeConfigFacet.setSpotFeeSplit.selector;
        selectors[5] = FeeConfigFacet.setComboFeeSplit.selector;
        selectors[6] = FeeConfigFacet.setParimutuelFeeSplit.selector;
    }

    function delayedOrderSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](13);
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
        selectors[10] = DelayedOrderFacet.processDelayedOrdersFrom.selector;
        selectors[11] = DelayedOrderFacet.expireDelayedOrders.selector;
        selectors[12] = DelayedOrderFacet.getDelayedOrderHead.selector;
    }

    function marginAccountSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](34);
        selectors[0] = IMarginAccountFacet.marginConfig.selector;
        selectors[1] = IMarginAccountFacet.depositMargin.selector;
        selectors[2] = IMarginAccountFacet.withdrawMargin.selector;
        selectors[3] = IMarginAccountFacet.allocateBucketMargin.selector;
        selectors[4] = IMarginAccountFacet.allocateBucketMarginWithKind.selector;
        selectors[5] = IMarginAccountFacet.releaseBucketMargin.selector;
        selectors[6] = IMarginAccountFacet.getMarginAccount.selector;
        selectors[7] = IMarginAccountFacet.getMarginBucket.selector;
        selectors[8] = IMarginAccountFacet.getBucketRisk.selector;
        selectors[9] = IMarginAccountFacet.bucketHealth.selector;
        selectors[10] = IMarginAccountFacet.riskParamsForBucket.selector;
        selectors[11] = IMarginAccountFacet.defaultRiskParams.selector;
        selectors[12] = IMarginAccountFacet.riskDomainRiskParams.selector;
        selectors[13] = IMarginAccountFacet.bucketLockedRisk.selector;
        selectors[14] = IMarginAccountFacet.bucketIdFor.selector;
        selectors[15] = IMarginAccountFacet.riskDomainForBook.selector;
        selectors[16] = IMarginAccountFacet.riskDomainForMarket.selector;
        selectors[17] = IMarginAccountFacet.canBucketIncreaseRisk.selector;
        selectors[18] = IMarginAccountFacet.canBucketIncreaseRiskForBook.selector;
        selectors[19] = IMarginAccountFacet.riskDomainOracleConfig.selector;
        selectors[20] = IMarginAccountFacet.riskDomainMarkConfig.selector;
        selectors[21] = IMarginAccountFacet.riskDomainRiskMark.selector;
        selectors[22] = IMarginAccountFacet.riskDomainFundingConfig.selector;
        selectors[23] = IMarginAccountFacet.defaultFundingConfig.selector;
        selectors[24] = IMarginAccountFacet.setMarginAsset.selector;
        selectors[25] = IMarginAccountFacet.setWarningRiskIncreaseAllowed.selector;
        selectors[26] = IMarginAccountFacet.setRiskDomainOracleConfig.selector;
        selectors[27] = IMarginAccountFacet.setRiskDomainMarkConfig.selector;
        selectors[28] = IMarginAccountFacet.setRiskDomainFundingConfig.selector;
        selectors[29] = IMarginAccountFacet.setDefaultFundingConfig.selector;
        selectors[30] = IMarginAccountFacet.setDefaultRiskParams.selector;
        selectors[31] = IMarginAccountFacet.setRiskDomainRiskParams.selector;
        selectors[32] = IMarginAccountFacet.clearRiskDomainRiskParams.selector;
        selectors[33] = IMarginAccountFacet.accrueBucketFundingNow.selector;
    }

    function mloProfitShareSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](12);
        selectors[0] = IMLOProfitShareFacet.initializeMLOProfitSplit.selector;
        selectors[1] = IMLOProfitShareFacet.scheduleMLOProfitSplit.selector;
        selectors[2] = IMLOProfitShareFacet.cancelMLOProfitSplit.selector;
        selectors[3] = IMLOProfitShareFacet.executeMLOProfitSplit.selector;
        selectors[4] = IMLOProfitShareFacet.activeMLOProfitSplit.selector;
        selectors[5] = IMLOProfitShareFacet.pendingMLOProfitSplit.selector;
        selectors[6] = IMLOProfitShareFacet.mloBucketProfitAccount.selector;
        selectors[7] = IMLOProfitShareFacet.previewMLOProfitRelease.selector;
        selectors[8] = IMLOProfitShareFacet.mloBucketProfitReward.selector;
        selectors[9] = IMLOProfitShareFacet.claimMLOBucketProfitReward.selector;
        selectors[10] = IMLOProfitShareFacet.setMLOProfitSplitDelay.selector;
        selectors[11] = IMLOProfitShareFacet.mloProfitSplitDelay.selector;
    }

    function markOracleSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IMarkOracleFacet.getMarkOracle.selector;
        selectors[1] = IMarkOracleFacet.getMarkObservation.selector;
        selectors[2] = IMarkOracleFacet.consultTwap.selector;
        selectors[3] = IMarkOracleFacet.consultVwap.selector;
        selectors[4] = IMarkOracleFacet.oracleState.selector;
        selectors[5] = IMarkOracleFacet.riskMarkForBook.selector;
        selectors[6] = IMarkOracleFacet.markOracleConfig.selector;
        selectors[7] = IMarkOracleFacet.setMarkOracleThresholds.selector;
        selectors[8] = IMarkOracleFacet.clearMarkOracleManualState.selector;
        selectors[9] = IMarkOracleFacet.setMarkOracleManualState.selector;
    }

    function quoteEnvelopeSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = IQuoteEnvelopeFacet.createQuoteEnvelope.selector;
        selectors[1] = IQuoteEnvelopeFacet.updateQuoteEnvelope.selector;
        selectors[2] = IQuoteEnvelopeFacet.cancelQuoteEnvelope.selector;
        selectors[3] = IQuoteEnvelopeFacet.cancelQuoteEnvelopes.selector;
        selectors[4] = IQuoteEnvelopeFacet.getQuoteEnvelope.selector;
        selectors[5] = IQuoteEnvelopeFacet.getOperatorQuoteEnvelopesPage.selector;
        selectors[6] = IQuoteEnvelopeFacet.getBookQuoteEnvelopesPage.selector;
        selectors[7] = IQuoteEnvelopeFacet.previewQuoteEnvelopeRisk.selector;
        selectors[8] = IQuoteEnvelopeFacet.canUpdateQuoteEnvelope.selector;
    }

    function mloPredictionAdapterSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IMLOPredictionAdapterFacet.getMLOCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.getMLOInventory.selector;
        selectors[2] = IMLOPredictionAdapterFacet.getMLOScenarioExposure.selector;
        selectors[3] = IMLOPredictionAdapterFacet.applyMLOAskFillState.selector;
        selectors[4] = IMLOPredictionAdapterFacet.previewMLOFunding.selector;
    }

    function seniorCapitalSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = ISeniorCapitalFacet.depositSeniorCapital.selector;
        selectors[1] = ISeniorCapitalFacet.withdrawPendingSeniorCapital.selector;
        selectors[2] = ISeniorCapitalFacet.activateSeniorCapital.selector;
        selectors[3] = ISeniorCapitalFacet.requestSeniorCapitalExit.selector;
        selectors[4] = ISeniorCapitalFacet.cancelSeniorCapitalExit.selector;
        selectors[5] = ISeniorCapitalFacet.processSeniorCapitalExits.selector;
        selectors[6] = ISeniorCapitalFacet.claimSeniorCapitalFees.selector;
        selectors[7] = ISeniorCapitalFacet.donateSeniorCapitalFees.selector;
        selectors[8] = ISeniorCapitalFacet.claimSeniorCapitalExit.selector;
    }

    function seniorCapitalViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = ISeniorCapitalFacet.seniorCapitalState.selector;
        selectors[1] = ISeniorCapitalFacet.seniorCapitalAccount.selector;
        selectors[2] = ISeniorCapitalFacet.seniorCapitalExit.selector;
        selectors[3] = ISeniorCapitalFacet.seniorCapitalBucket.selector;
        selectors[4] = ISeniorCapitalFacet.pendingSeniorCapitalFees.selector;
        selectors[5] = ISeniorCapitalFacet.claimableSeniorCapitalExit.selector;
    }

    function mloPredictionCurveSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IMLOPredictionAdapterFacet.createMLOCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.cancelMLOCurve.selector;
        selectors[2] = IMLOPredictionAdapterFacet.rebalanceMLOAskCurve.selector;
    }

    function mloPredictionPostSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IMLOPredictionAdapterFacet.postMLOCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.postMLOCurvesBatch.selector;
    }

    function mloPredictionUpdateSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IMLOPredictionAdapterFacet.updateMLOCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.updateMLOCurvesBatch.selector;
        selectors[2] = IMLOPredictionAdapterFacet.updateMLOCurveFromNow.selector;
        selectors[3] = IMLOPredictionAdapterFacet.updateMLOCurvesFromNowBatch.selector;
    }

    function mloPredictionTradeSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IMLOPredictionAdapterFacet.fillMLOAskCurve.selector;
    }

    function mloPredictionAskRouteSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IMLOPredictionAdapterFacet.executeMLOAskFromRoute.selector;
    }

    function mloPredictionBidTradeSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IMLOPredictionAdapterFacet.fillMLOBidCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.executeMLOBidFromRoute.selector;
    }

    function mloPredictionSettlementSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IMLOPredictionAdapterFacet.settleMLOInventory.selector;
        selectors[1] = IMLOPredictionAdapterFacet.mergeMLOCompleteSet.selector;
        selectors[2] = IMLOPredictionAdapterFacet.executeMLOAskAssetSettlement.selector;
        selectors[3] = IMLOPredictionAdapterFacet.executeMLOBidAssetSettlement.selector;
        selectors[4] = IMLOPredictionAdapterFacet.settleMLOFunding.selector;
        selectors[5] = IMLOPredictionAdapterFacet.prepareMLOAskBacking.selector;
        selectors[6] = IMLOPredictionAdapterFacet.mergeAvailableMLOCompleteSet.selector;
    }

    function mloPredictionRecoverySelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IMLOPredictionAdapterFacet.mloRecoveryConfig.selector;
        selectors[1] = IMLOPredictionAdapterFacet.setMLORecoveryConfig.selector;
        selectors[2] = IMLOPredictionAdapterFacet.synchronizeMLOBucketState.selector;
        selectors[3] = IMLOPredictionAdapterFacet.cleanupMLOCurves.selector;
    }

    function tradeRouterBookSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouterBook.buyBookWithCollateral.selector;
    }

    function tradeRouterBookSellSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouterBook.sellBookWithCollateral.selector;
    }

    function marketFactorySelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = bytes4(
            keccak256(
                "createMarket((string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
            )
        );
        selectors[1] = IMarketFactoryFacet.createMarkets.selector;
        selectors[2] = MarketFactoryFacet.syncMarketState.selector;
        selectors[3] = bytes4(
            keccak256(
                "createMarketWithCollateralProfile(uint8,(string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
            )
        );
        selectors[4] = bytes4(keccak256("createMarket(string,string,string,uint64,uint64,uint128,bool)"));
        selectors[5] = bytes4(
            keccak256("createMarketWithCollateralProfile(uint8,string,string,string,uint64,uint64,uint128,bool)")
        );
    }

    function marketGroupSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = bytes4(
            keccak256(
                "createMarketGroup(((string,string,uint8,string,(uint8,string,string,string,string,bytes32)),((string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)),(string,string,int32,uint8))[]))"
            )
        );
        selectors[1] = bytes4(
            keccak256(
                "createMarketGroup(string,(string,string,string,uint64,uint64,uint128,bool,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32))[])"
            )
        );
        selectors[2] = bytes4(
            keccak256(
                "createMarketGroupFromExisting(((string,string,uint8,string,(uint8,string,string,string,string,bytes32)),(bytes32,(string,string,int32,uint8))[]))"
            )
        );
        selectors[3] = bytes4(keccak256("addMarketsToGroup(bytes32,(bytes32,(string,string,int32,uint8))[])"));
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
        selectors[4] = IMultiOutcomeOrderbookFacet.getMultiOutcomeDisplay.selector;
        selectors[5] = IMultiOutcomeOrderbookFacet.getOutcomeCTFPositions.selector;
    }

    function negRiskConfigSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = INegRiskConfigFacet.setNegRiskAdapter.selector;
        selectors[1] = INegRiskConfigFacet.negRiskAdapter.selector;
    }

    function ctfConfigSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = INegRiskConfigFacet.setCTFSettlementAdapter.selector;
        selectors[1] = INegRiskConfigFacet.ctfSettlementAdapter.selector;
    }

    function ctfPositionViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = ICTFPositionViewFacet.getCTFPositionMetadata.selector;
        selectors[1] = ICTFPositionViewFacet.getCTFComboEscrow.selector;
        selectors[2] = ICTFPositionViewFacet.getCTFConditionPositions.selector;
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
        selectors = new bytes4[](2);
        selectors[0] = IComboSettlementFacet.redeemCombo.selector;
        selectors[1] = IComboSettlementFacet.getComboPayout.selector;
    }

    function comboViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IComboViewFacet.getComboPositionMetadata.selector;
        selectors[1] = IComboViewFacet.getComboPositionPayout.selector;
        selectors[2] = IComboViewFacet.getComboCollateralStatus.selector;
    }

    function comboMarketSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IComboMarketFacet.createComboMarket.selector;
        selectors[1] = IComboMarketFacet.createComboMarketFromLegs.selector;
        selectors[2] = IComboMarketFacet.computeComboBookId.selector;
        selectors[3] = IComboMarketFacet.getComboMarket.selector;
        selectors[4] = IComboMarketFacet.getComboBook.selector;
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
        selectors = new bytes4[](16);
        selectors[0] = ICurveLifecycleFacet.postCurve.selector;
        selectors[1] = ICurveLifecycleFacet.postCurvesBatch.selector;
        selectors[2] = ICurveLifecycleFacet.postBidCurve.selector;
        selectors[3] = ICurveLifecycleFacet.postBidCurvesBatch.selector;
        selectors[4] = ICurveLifecycleFacet.postCurvesMultiMarket.selector;
        selectors[5] = ICurveLifecycleFacet.postBidCurvesMultiMarket.selector;
        selectors[6] = ICurveLifecycleFacet.updateCurve.selector;
        selectors[7] = ICurveLifecycleFacet.updateCurvesBatch.selector;
        selectors[8] = ICurveLifecycleFacet.updateCurveFromNow.selector;
        selectors[9] = ICurveLifecycleFacet.updateCurvesFromNowBatch.selector;
        selectors[10] = ICurveLifecycleFacet.topUpCurvesBatch.selector;
        selectors[11] = ICurveLifecycleFacet.splitAndTopUpCurvesBatch.selector;
        selectors[12] = ICurveLifecycleFacet.topUpCurvesMultiMarket.selector;
        selectors[13] = ICurveLifecycleFacet.splitAndTopUpCurvesMultiMarket.selector;
        selectors[14] = ICurveLifecycleFacet.cancelCurve.selector;
        selectors[15] = ICurveLifecycleFacet.cancelCurvesBatch.selector;
    }

    function curveTradeSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
        selectors[1] = ICurveTradeFacet.fillBest.selector;
    }

    function curveViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ICurveViewFacet.getCurveInfo.selector;
        selectors[1] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[2] = ICurveViewFacet.previewCurveQuote.selector;
        selectors[3] = ICurveViewFacet.previewBestExecution.selector;
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
        selectors = new bytes4[](5);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
        selectors[1] = IBookOrderFacet.postBookCurvesBatch.selector;
        selectors[2] = IBookOrderFacet.topUpBookCurvesBatch.selector;
        selectors[3] = IBookOrderFacet.reactivateBookCurve.selector;
        selectors[4] = IBookOrderFacet.pruneBookCurves.selector;
    }

    function bookTradeSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBestFor.selector;
    }

    function bookSellSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.sellBookBest.selector;
        selectors[1] = IBookTradeFacet.sellBookBestFor.selector;
    }

    function bookViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookViewFacet.previewBookExecution.selector;
        selectors[1] = IBookViewFacet.getBookCurveIdsPage.selector;
        selectors[2] = IBookViewFacet.getActiveBookCurveIdsPage.selector;
        selectors[3] = IBookViewFacet.getBookTopOfBookPage.selector;
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
        selectors = new bytes4[](10);
        selectors[0] = IOBRResolutionFacet.settleMarket.selector;
        selectors[1] = IOBRResolutionFacet.openResolution.selector;
        selectors[2] = IOBRResolutionFacet.disputeResolution.selector;
        selectors[3] = IOBRResolutionFacet.adminFinalizeResolution.selector;
        selectors[4] = IOBRResolutionFacet.getResolutionHistory.selector;
        selectors[5] = IOBRResolutionFacet.finalizeResolution.selector;
        selectors[6] = IOBRResolutionFacet.getMarketStatus.selector;
        selectors[7] = IOBRResolutionFacet.settleMarketEarly.selector;
        selectors[8] = IOBRResolutionFacet.finalizeFromJury.selector;
        selectors[9] = IOBRResolutionFacet.resolutionMode.selector;
    }

    function resolverRegistrySelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](15);
        selectors[0] = IResolverRegistryFacet.mintIdentity.selector;
        selectors[1] = IResolverRegistryFacet.setCreatorRole.selector;
        selectors[2] = IResolverRegistryFacet.setResolverRole.selector;
        selectors[3] = IResolverRegistryFacet.depositResolverStake.selector;
        selectors[4] = IResolverRegistryFacet.openResolverEpochRotation.selector;
        selectors[5] = IResolverRegistryFacet.optIntoResolverEpoch.selector;
        selectors[6] = IResolverRegistryFacet.commitResolverEpochRandomness.selector;
        selectors[7] = IResolverRegistryFacet.closeResolverEpochRandomnessCommit.selector;
        selectors[8] = IResolverRegistryFacet.revealResolverEpochRandomness.selector;
        selectors[9] = IResolverRegistryFacet.finalizeResolverEpochSeed.selector;
        selectors[10] = IResolverRegistryFacet.submitResolverEpochCandidateScore.selector;
        selectors[11] = IResolverRegistryFacet.finalizeResolverEpochSelection.selector;
        selectors[12] = IResolverRegistryFacet.activateFinalizedResolverEpoch.selector;
        selectors[13] = IResolverRegistryFacet.requestResolverExit.selector;
        selectors[14] = IResolverRegistryFacet.withdrawResolverStake.selector;
    }

    function resolverRegistryRewardsSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IResolverRegistryFacet.finalizeResolverTradingRewards.selector;
        selectors[1] = IResolverRegistryFacet.claimResolverRewards.selector;
    }

    function resolverRegistryViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](19);
        selectors[0] = IResolverRegistryFacet.eveIdentity.selector;
        selectors[1] = IResolverRegistryFacet.resolverDashboard.selector;
        selectors[2] = IResolverRegistryFacet.resolverIdentity.selector;
        selectors[3] = IResolverRegistryFacet.resolverIdentityByOwner.selector;
        selectors[4] = IResolverRegistryFacet.resolverJuryConfig.selector;
        selectors[5] = IResolverRegistryFacet.identityByOwner.selector;
        selectors[6] = IResolverRegistryFacet.isEligibleResolver.selector;
        selectors[7] = IResolverRegistryFacet.hasConflict.selector;
        selectors[8] = IResolverRegistryFacet.resolverLifecycleState.selector;
        selectors[9] = IResolverRegistryFacet.creatorReputation.selector;
        selectors[10] = IResolverRegistryFacet.resolverReputation.selector;
        selectors[11] = IResolverRegistryFacet.eligibleResolverCount.selector;
        selectors[12] = IResolverRegistryFacet.activeResolverCount.selector;
        selectors[13] = IResolverRegistryFacet.activeResolverEpochSize.selector;
        selectors[14] = IResolverRegistryFacet.activeResolverAt.selector;
        selectors[15] = IResolverRegistryFacet.currentResolverEpoch.selector;
        selectors[16] = IResolverRegistryFacet.resolverEpoch.selector;
        selectors[17] = IResolverRegistryFacet.resolverEpochCandidate.selector;
        selectors[18] = IResolverRegistryFacet.previewResolverRewards.selector;
    }

    function resolverRegistryReputationSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IResolverRegistryFacet.applyFinalityReputation.selector;
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
        selectors = new bytes4[](8);
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
        selectors[6] = bytes4(keccak256("createParimutuelMarket(string,string,string,uint64,uint64,uint64)"));
        selectors[7] = bytes4(
            keccak256("createParimutuelMarketWithCollateralProfile(uint8,string,string,string,uint64,uint64,uint64)")
        );
    }

    function parimutuelViewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = IParimutuelFacet.previewPayout.selector;
        selectors[1] = IParimutuelFacet.previewEntryFee.selector;
        selectors[2] = IParimutuelFacet.getParimutuelPool.selector;
        selectors[3] = IParimutuelFacet.getParimutuelBalances.selector;
        selectors[4] = IParimutuelFacet.isParimutuelMarket.selector;
        selectors[5] = IParimutuelFacet.getParimutuelEpochWindow.selector;
        selectors[6] = IParimutuelFacet.getEpochMultiplier.selector;
        selectors[7] = IParimutuelFacet.getParimutuelEpochMultipliers.selector;
        selectors[8] = IParimutuelFacet.previewParimutuelEntry.selector;
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
        selectors = new bytes4[](2);
        selectors[0] = ITradeRouter.buyWithCollateral.selector;
        selectors[1] = ITradeRouter.buyWithCollateralWithPermit.selector;
    }

    function tradeRouterExactSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouter.buyWithCollateralExact.selector;
    }

    function staticsDollarTradeRouterSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ITradeRouter.mintAndBuyWithUSDC.selector;
        selectors[1] = ITradeRouter.mintAndBuyWithUSDCPermit.selector;
    }

    function collateralTradeExecutionSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICollateralTradeExecution.executeCollateralBuy.selector;
    }

    function tradeRouterSellSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouter.sellWithCollateral.selector;
    }

    function collateralTradeRouterPreviewSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ITradeRouter.previewSellBest.selector;
        selectors[1] = ITradeRouter.executeExactRouterTransfer.selector;
    }

    function verifyDeployment(
        Deployment memory deployment,
        uint64 expectedGovernanceDelay,
        uint64 expectedMLOProfitSplitDelay
    ) external view {
        _verifyDeployment(deployment, expectedGovernanceDelay, expectedMLOProfitSplitDelay);
    }

    function verifyFullDeployment(FullDeployment memory deployment, FullDeploymentConfig memory config) external view {
        config = _withFullConfigDefaults(config);
        _verifyFullDeployment(deployment, config);
    }

    function verifyRobinhoodPreflightFromEnv(address broadcaster) external view {
        verifyRobinhoodPreflight(_loadFullConfigFromEnv(), broadcaster);
    }

    function verifyRobinhoodPreflight(FullDeploymentConfig memory config, address broadcaster) public view {
        require(block.chainid == ROBINHOOD_TESTNET_CHAIN_ID, "wrong Robinhood testnet chain");
        config = _withFullConfigDefaults(config);
        _validateFullConfig(config, broadcaster);
        require(config.market.conditionalTokens.code.length != 0, "invalid conditional tokens");
        require(
            config.market.conditionalTokens.codehash
                == keccak256(_loadConditionalTokensRuntimeCode(config.market.conditionalTokensArtifactPath)),
            "conditional tokens runtime mismatch"
        );
        require(config.usdcToken.code.length != 0, "invalid USDG");
        require(IERC20Metadata(config.usdcToken).decimals() == 6, "USDG decimals mismatch");

        FullDeployment memory statics;
        statics.usdcToken = config.usdcToken;
        statics.staticsDollarCore = config.staticsDollar.core;
        statics.staticsDollar = IStaticsDollarCore(config.staticsDollar.core).staticsDollar();
        statics.staticsDiamond = IStaticsDollarCore(config.staticsDollar.core).periphery();
        _validateStaticsDollarIntegration(statics, config);

        require(broadcaster.balance != 0, "deployment broadcaster has no native gas");
        uint256 bootstrapAssets =
            (config.initialMloInsuranceBootstrapUsdg + config.initialSeniorCapitalBootstrapUsdg) * 1e12;
        uint256 requiredUsdg = config.faucetUsdcEnabled ? config.faucetUsdcFundAmount : 0;
        uint256 existingStaticsDollar = IERC20(statics.staticsDollar).balanceOf(broadcaster);
        if (bootstrapAssets > existingStaticsDollar) {
            requiredUsdg += IStaticsDollarCore(config.staticsDollar.core)
            .previewPeggedMint(config.staticsDollar.peggedProfileId, bootstrapAssets - existingStaticsDollar)
            .totalCollateralIn;
        }
        require(IERC20(config.usdcToken).balanceOf(broadcaster) >= requiredUsdg, "insufficient deployment USDG");

        if (config.market.eveToken != address(0)) {
            require(config.market.eveToken.code.length != 0, "invalid configured EVE");
            uint256 requiredEve = config.faucetEveEnabled ? config.faucetEveFundAmount : 0;
            require(IERC20(config.market.eveToken).balanceOf(broadcaster) >= requiredEve, "insufficient deployment EVE");
        }
    }

    function writeFullDeploymentManifest(
        FullDeployment memory deployment,
        FullDeploymentConfig memory config,
        string memory path,
        string memory releaseCommit,
        string memory staticsReleaseCommit
    ) public returns (string memory json) {
        require(block.chainid == ROBINHOOD_TESTNET_CHAIN_ID, "wrong manifest chain");
        require(bytes(path).length != 0, "empty manifest path");
        require(bytes(releaseCommit).length != 0, "empty release commit");
        require(bytes(staticsReleaseCommit).length != 0, "empty Statics release commit");
        config = _withFullConfigDefaults(config);
        _verifyFullDeployment(deployment, config);

        ReleaseSurface memory surface = _releaseSurface(deployment);
        string memory objectKey = "robinhood-release";
        json = vm.serializeUint(objectKey, "schemaVersion", 1);
        json = vm.serializeString(objectKey, "network", "Robinhood Chain Testnet");
        json = vm.serializeUint(objectKey, "chainId", block.chainid);
        json = vm.serializeUint(objectKey, "deploymentBlock", block.number);
        json = vm.serializeString(objectKey, "releaseCommit", releaseCommit);
        json = vm.serializeString(objectKey, "staticsReleaseCommit", staticsReleaseCommit);
        json = vm.serializeAddress(objectKey, "owner", config.market.owner);
        json = vm.serializeAddress(objectKey, "treasury", config.market.eveTreasury);
        json = vm.serializeUint(objectKey, "governanceDelaySeconds", config.market.governanceDelay);
        json = vm.serializeUint(objectKey, "mloProfitSplitDelaySeconds", config.market.mloProfitSplitDelay);
        json = vm.serializeBool(objectKey, "permissionlessCreationEnabled", config.market.permissionlessCreationEnabled);
        json = vm.serializeUint(objectKey, "marketCreationFee", config.market.marketCreationFee);
        json = vm.serializeUint(objectKey, "initialMloInsuranceBootstrapUsdg", config.initialMloInsuranceBootstrapUsdg);
        json =
            vm.serializeUint(objectKey, "initialSeniorCapitalBootstrapUsdg", config.initialSeniorCapitalBootstrapUsdg);
        json = vm.serializeBytes32(objectKey, "deploymentHash", keccak256(abi.encode(deployment)));
        json = vm.serializeBytes32(objectKey, "configHash", keccak256(abi.encode(config)));
        json = vm.serializeBytes(objectKey, "deploymentAbi", abi.encode(deployment));
        json = vm.serializeBytes(objectKey, "configAbi", abi.encode(config));
        json = vm.serializeString(objectKey, "criticalContractNames", surface.criticalNames);
        json = vm.serializeAddress(objectKey, "criticalContractAddresses", surface.criticalAddresses);
        json = vm.serializeBytes32(objectKey, "criticalRuntimeCodeHashes", surface.criticalRuntimeCodeHashes);
        json = vm.serializeAddress(objectKey, "facetAddresses", surface.facetAddresses);
        json = vm.serializeBytes32(objectKey, "facetRuntimeCodeHashes", surface.facetRuntimeCodeHashes);
        json = vm.serializeUint(objectKey, "facetSelectorCounts", surface.facetSelectorCounts);
        json = vm.serializeBytes32(objectKey, "selectors", surface.selectors);
        json = vm.serializeAddress(objectKey, "selectorFacets", surface.selectorFacets);
        json = vm.serializeBytes32(objectKey, "absentSelectors", surface.absentSelectors);
        vm.writeJson(json, path);
    }

    function verifyFullDeploymentManifestFromFile(string memory path)
        public
        view
        returns (FullDeployment memory deployment, FullDeploymentConfig memory config)
    {
        string memory json = vm.readFile(path);
        require(vm.parseJsonUint(json, ".schemaVersion") == 1, "manifest schema mismatch");
        require(vm.parseJsonUint(json, ".chainId") == block.chainid, "manifest chain mismatch");
        require(bytes(vm.parseJsonString(json, ".releaseCommit")).length != 0, "manifest release commit missing");
        require(
            bytes(vm.parseJsonString(json, ".staticsReleaseCommit")).length != 0,
            "manifest Statics release commit missing"
        );

        deployment = abi.decode(vm.parseJsonBytes(json, ".deploymentAbi"), (FullDeployment));
        config = abi.decode(vm.parseJsonBytes(json, ".configAbi"), (FullDeploymentConfig));
        config = _withFullConfigDefaults(config);
        require(
            vm.parseJsonBytes32(json, ".deploymentHash") == keccak256(abi.encode(deployment)),
            "manifest deployment hash mismatch"
        );
        require(
            vm.parseJsonBytes32(json, ".configHash") == keccak256(abi.encode(config)), "manifest config hash mismatch"
        );
        _verifyFullDeployment(deployment, config);
        _verifyReleaseSurface(json, _releaseSurface(deployment));
    }

    function _loadConfigFromEnv() internal view returns (DeploymentConfig memory config) {
        config.owner = vm.envAddress("INITIAL_OWNER");
        config.governanceDelay =
            uint64(vm.envOr("INITIAL_GOVERNANCE_DELAY_SECONDS", uint256(DEFAULT_INITIAL_GOVERNANCE_DELAY)));
        config.mloProfitSplitDelay = uint64(vm.envOr("MLO_PROFIT_SPLIT_DELAY_SECONDS", uint256(config.governanceDelay)));
        config.conditionalTokens = vm.envOr("CONDITIONAL_TOKENS", address(0));
        config.conditionalTokensArtifactPath =
            vm.envOr("CONDITIONAL_TOKENS_ARTIFACT", DEFAULT_CONDITIONAL_TOKENS_ARTIFACT_PATH);
        config.collateralToken = vm.envOr("COLLATERAL_TOKEN", address(0));
        config.eveToken = vm.envOr("EVE_TOKEN", address(0));
        config.eveTreasury = vm.envAddress("EVE_TREASURY");
        config.evesPositionManager = vm.envOr("EVES_POSITION_MANAGER", address(0));
        config.parimutuelShareToken = vm.envOr("PARIMUTUEL_SHARE_TOKEN", address(0));
        config.parlayTicketToken = vm.envOr("PARLAY_TICKET_TOKEN", address(0));
        config.parlayFeeRecipient = vm.envOr("PARLAY_FEE_RECIPIENT", config.eveTreasury);
        config.parlayUnderwritingFee = uint128(vm.envOr("PARLAY_UNDERWRITING_FEE", uint256(3e18)));
        config.parlaySeniorPoolFeeBps = uint16(vm.envOr("PARLAY_SENIOR_POOL_FEE_BPS", uint256(0)));
        config.parlayFeeRecipientBps = uint16(vm.envOr("PARLAY_FEE_RECIPIENT_BPS", uint256(10_000)));
        config.orderbookEntryFeeBps = uint16(vm.envOr("ORDERBOOK_ENTRY_FEE_BPS", uint256(100)));
        config.orderbookMakerFeeBps = uint16(vm.envOr("ORDERBOOK_MAKER_FEE_BPS", uint256(4_000)));
        config.orderbookCreatorFeeBps = uint16(vm.envOr("ORDERBOOK_CREATOR_FEE_BPS", uint256(500)));
        config.orderbookProtocolFeeBps = uint16(vm.envOr("ORDERBOOK_PROTOCOL_FEE_BPS", uint256(1_000)));
        config.orderbookSeniorPoolFeeBps = uint16(vm.envOr("ORDERBOOK_SENIOR_POOL_FEE_BPS", uint256(4_000)));
        config.orderbookResolverFeeBps = uint16(vm.envOr("ORDERBOOK_RESOLVER_FEE_BPS", uint256(500)));
        config.spotTradeFeeBps = uint16(vm.envOr("SPOT_TRADE_FEE_BPS", uint256(100)));
        config.spotMakerFeeBps = uint16(vm.envOr("SPOT_MAKER_FEE_BPS", uint256(4_000)));
        config.spotProtocolFeeBps = uint16(vm.envOr("SPOT_PROTOCOL_FEE_BPS", uint256(1_500)));
        config.spotSeniorPoolFeeBps = uint16(vm.envOr("SPOT_SENIOR_POOL_FEE_BPS", uint256(4_000)));
        config.spotResolverFeeBps = uint16(vm.envOr("SPOT_RESOLVER_FEE_BPS", uint256(500)));
        config.comboTradeFeeBps = uint16(vm.envOr("COMBO_TRADE_FEE_BPS", uint256(100)));
        config.comboMakerFeeBps = uint16(vm.envOr("COMBO_MAKER_FEE_BPS", uint256(4_000)));
        config.comboCreatorFeeBps = uint16(vm.envOr("COMBO_CREATOR_FEE_BPS", uint256(500)));
        config.comboProtocolFeeBps = uint16(vm.envOr("COMBO_PROTOCOL_FEE_BPS", uint256(1_000)));
        config.comboSeniorPoolFeeBps = uint16(vm.envOr("COMBO_SENIOR_POOL_FEE_BPS", uint256(4_000)));
        config.comboResolverFeeBps = uint16(vm.envOr("COMBO_RESOLVER_FEE_BPS", uint256(500)));
        config.parimutuelEntryFeeBps = uint16(vm.envOr("PARIMUTUEL_ENTRY_FEE_BPS", uint256(250)));
        config.parimutuelCreatorFeeBps = uint16(vm.envOr("PARIMUTUEL_CREATOR_FEE_BPS", uint256(500)));
        config.parimutuelProtocolFeeBps = uint16(vm.envOr("PARIMUTUEL_PROTOCOL_FEE_BPS", uint256(5_000)));
        config.parimutuelSeniorPoolFeeBps = uint16(vm.envOr("PARIMUTUEL_SENIOR_POOL_FEE_BPS", uint256(4_000)));
        config.parimutuelResolverFeeBps = uint16(vm.envOr("PARIMUTUEL_RESOLVER_FEE_BPS", uint256(500)));
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
        config.maxDelayedOrderRouteLength = uint32(vm.envOr("MAX_DELAYED_ORDER_ROUTE_LENGTH", uint256(64)));
        config.minDelayedOrderQuoteWad = uint128(vm.envOr("MIN_DELAYED_ORDER_QUOTE_WAD", uint256(1e18)));
        config.minDelayedOrderBaseWad = uint128(vm.envOr("MIN_DELAYED_ORDER_BASE_WAD", uint256(1e18)));
        config.mloDefaultFundingRatePerSecondWad = uint128(vm.envUint("MLO_DEFAULT_FUNDING_RATE_PER_SECOND_WAD"));
    }

    function _loadFullConfigFromEnv() internal view returns (FullDeploymentConfig memory config) {
        config.market = _loadConfigFromEnv();
        config.usdcToken = vm.envOr("USDC_TOKEN", address(0));
        config.mloInsuranceFund = vm.envOr("MLO_INSURANCE_FUND", address(0));
        config.feeRecipient = vm.envOr("FEE_RECIPIENT", config.market.eveTreasury);
        config.initialEveMint = vm.envOr("INITIAL_EVE_MINT", uint256(1_000_000e18));
        config.initialMloInsuranceBootstrapUsdg = vm.envOr("INITIAL_MLO_INSURANCE_BOOTSTRAP_USDG", uint256(100_000e6));
        config.initialSeniorCapitalBootstrapUsdg = vm.envOr("INITIAL_SENIOR_CAPITAL_BOOTSTRAP_USDG", uint256(100_000e6));
        config.mloFundingSeniorBps = uint16(vm.envOr("MLO_FUNDING_SENIOR_BPS", uint256(5_000)));
        config.mloMaxCleanupBatch = uint16(vm.envOr("MLO_MAX_CLEANUP_BATCH", uint256(32)));
        config.faucetOwner = vm.envOr("FAUCET_OWNER", config.market.owner);
        config.faucetUsdcEnabled = vm.envOr("FAUCET_USDC_ENABLED", true);
        config.faucetEveEnabled = vm.envOr("FAUCET_EVE_ENABLED", true);
        config.faucetUsdcClaimAmount = vm.envOr("FAUCET_USDC_CLAIM_AMOUNT", uint256(1_000e6));
        config.faucetEveClaimAmount = vm.envOr("FAUCET_EVE_CLAIM_AMOUNT", uint256(10_000e18));
        config.faucetUsdcFundAmount = vm.envOr("FAUCET_USDC_FUND_AMOUNT", uint256(1_000_000e6));
        config.faucetEveFundAmount = vm.envOr("FAUCET_EVE_FUND_AMOUNT", uint256(10_000_000e18));
        config.staticsDollar.core = vm.envOr("STATICS_DOLLAR_CORE_ADDRESS", address(0));
        config.staticsDollar.peggedProfileId = vm.envUint("STATICS_DOLLAR_USDC_PROFILE_ID");
        config.staticsDollar.payoutUnit = uint128(vm.envOr("STATICS_DOLLAR_PAYOUT_UNIT", uint256(1e18)));
        config.staticsDollar.marketCreationFee = uint128(vm.envOr("STATICS_DOLLAR_MARKET_CREATION_FEE", uint256(0)));
        config.staticsDollar.parimutuelCreationSeedAmount =
            uint128(vm.envOr("STATICS_DOLLAR_PARIMUTUEL_CREATION_SEED_AMOUNT", uint256(0)));
        config.staticsDollar.parimutuelMinEntry =
            uint128(vm.envOr("STATICS_DOLLAR_PARIMUTUEL_MIN_ENTRY", uint256(config.staticsDollar.payoutUnit)));
        config.staticsDollar.parlayUnderwritingFee =
            uint128(vm.envOr("STATICS_DOLLAR_PARLAY_UNDERWRITING_FEE", uint256(1e18)));
        config.staticsDollar.enableMarkets = vm.envOr("ENABLE_STATICS_DOLLAR_MARKETS", false);
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
                    + config.orderbookSeniorPoolFeeBps + config.orderbookResolverFeeBps == 10_000,
            "invalid orderbook fee split"
        );
        require(
            uint256(config.spotMakerFeeBps) + config.spotProtocolFeeBps + config.spotSeniorPoolFeeBps
                    + config.spotResolverFeeBps == 10_000,
            "invalid spot fee split"
        );
        require(
            uint256(config.comboMakerFeeBps) + config.comboCreatorFeeBps + config.comboProtocolFeeBps
                    + config.comboSeniorPoolFeeBps + config.comboResolverFeeBps == 10_000,
            "invalid combo fee split"
        );
        require(
            uint256(config.parimutuelCreatorFeeBps) + config.parimutuelProtocolFeeBps
                    + config.parimutuelSeniorPoolFeeBps + config.parimutuelResolverFeeBps == 10_000,
            "invalid parimutuel fee split"
        );
        require(
            uint256(config.parlaySeniorPoolFeeBps) + config.parlayFeeRecipientBps == 10_000, "invalid parlay fee split"
        );
    }

    function _withFullConfigDefaults(FullDeploymentConfig memory config)
        internal
        pure
        returns (FullDeploymentConfig memory)
    {
        if (config.feeRecipient == address(0)) {
            config.feeRecipient = config.market.eveTreasury;
        }
        if (config.market.parlayFeeRecipient == address(0)) {
            config.market.parlayFeeRecipient = config.feeRecipient;
        }
        if (config.faucetOwner == address(0)) {
            config.faucetOwner = config.market.owner;
        }
        if (config.mloMaxCleanupBatch == 0) {
            config.mloMaxCleanupBatch = 32;
        }
        if (config.staticsDollar.payoutUnit == 0) {
            config.staticsDollar.payoutUnit = 1e18;
        }
        if (config.staticsDollar.parimutuelMinEntry == 0) {
            config.staticsDollar.parimutuelMinEntry = config.staticsDollar.payoutUnit;
        }
        if (config.staticsDollar.parlayUnderwritingFee == 0) {
            config.staticsDollar.parlayUnderwritingFee = config.staticsDollar.payoutUnit;
        }
        return config;
    }

    function _validateFullConfig(FullDeploymentConfig memory config, address temporaryOwner) internal pure {
        require(temporaryOwner != address(0), "zero temporary owner");
        require(config.market.owner != address(0), "zero owner");
        require(config.market.eveTreasury != address(0), "zero eve treasury");
        require(config.usdcToken != address(0), "missing USDC token");
        require(config.feeRecipient != address(0), "zero fee recipient");
        require(config.market.parlayFeeRecipient != address(0), "zero parlay fee recipient");
        require(config.faucetOwner != address(0), "zero faucet owner");
        require(config.mloFundingSeniorBps <= 10_000, "invalid MLO funding split");
        require(config.mloMaxCleanupBatch <= 64, "invalid MLO cleanup cap");
        require(config.staticsDollar.core != address(0), "missing staticsDollar core");
        require(config.staticsDollar.peggedProfileId != 0, "missing USDC profile");
        require(config.staticsDollar.payoutUnit != 0, "zero staticsDollar payout unit");
        require(config.faucetUsdcEnabled || config.faucetEveEnabled, "faucet disabled");
        if (config.faucetUsdcEnabled) {
            require(config.faucetUsdcClaimAmount != 0, "zero faucet usdc amount");
        }
        if (config.faucetEveEnabled) {
            require(config.faucetEveClaimAmount != 0, "zero faucet eve amount");
        }
    }

    function _validateStaticsDollarIntegration(FullDeployment memory deployment, FullDeploymentConfig memory config)
        internal
        view
    {
        require(deployment.staticsDollarCore.code.length != 0, "invalid staticsDollar core");
        require(deployment.staticsDollar.code.length != 0, "invalid staticsDollar token");
        require(deployment.staticsDiamond.code.length != 0, "invalid Statics Diamond");
        IStaticsDollarCore core = IStaticsDollarCore(deployment.staticsDollarCore);
        require(core.bootstrapFinalized(), "staticsDollar bootstrap incomplete");
        require(
            IStaticsDollar(deployment.staticsDollar).pool() == deployment.staticsDollarCore,
            "staticsDollar core mismatch"
        );
        require(core.staticsDollar() == deployment.staticsDollar, "core staticsDollar mismatch");
        require(core.periphery() == deployment.staticsDiamond, "core Statics Diamond mismatch");
        require(core.positionNFT() == deployment.staticsDiamond, "shared position mismatch");
        require(
            IStaticsDollarGateway(deployment.staticsDiamond).pool() == deployment.staticsDollarCore,
            "gateway core mismatch"
        );
        require(
            IStaticsDollarGateway(deployment.staticsDiamond).staticsDollar() == deployment.staticsDollar,
            "gateway token mismatch"
        );
        require(deployment.staticsDollarCore == config.staticsDollar.core, "staticsDollar integration core mismatch");
        IStaticsDollarCoreTypes.StableCollateralProfile memory profile =
            core.collateralProfile(config.staticsDollar.peggedProfileId);
        require(profile.kind == IStaticsDollarCoreTypes.ProfileKind.Pegged, "USDC profile is not pegged");
        require(profile.collateralToken == deployment.usdcToken, "USDC profile token mismatch");
    }

    function _addCoreFacets(Deployment memory deployment) internal {
        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](67);
        cuts[0] = _cut(deployment.diamondLoupeFacet, loupeSelectors());
        cuts[1] = _cut(deployment.ownershipFacet, ownershipSelectors());
        cuts[2] = _cut(deployment.feeConfigFacet, feeConfigSelectors());
        cuts[3] = _cut(deployment.marketFactoryFacet, marketFactorySelectors());
        cuts[4] = _cut(deployment.marketGroupFacet, marketGroupSelectors());
        cuts[5] = _cut(deployment.marketViewFacet, marketViewSelectors());
        cuts[6] = _cut(deployment.curveInventoryFacet, curveInventorySelectors());
        cuts[7] = _cut(deployment.curveLifecycleFacet, curveLifecycleSelectors());
        cuts[8] = _cut(deployment.curveCLOBFacet, curveTradeSelectors());
        cuts[9] = _cut(deployment.curveViewFacet, curveViewSelectors());
        cuts[10] = _cut(deployment.bookFacet, bookSelectors());
        cuts[11] = _cut(deployment.bookOrderFacet, bookOrderSelectors());
        cuts[12] = _cut(deployment.bookTradeFacet, bookTradeSelectors());
        cuts[13] = _cut(deployment.bookViewFacet, bookViewSelectors());
        cuts[14] = _cut(deployment.bondManagerFacet, bondManagerSelectors());
        cuts[15] = _cut(deployment.bondTokenGateFacet, bondTokenGateSelectors());
        cuts[16] = _cut(deployment.obrResolutionFacet, obrResolutionSelectors());
        cuts[17] = _cut(deployment.feeRouterFacet, feeRouterSelectors());
        cuts[18] = _cut(deployment.marketSettlementFacet, marketSettlementSelectors());
        cuts[19] = _cut(deployment.multiOutcomeOrderbookFacet, multiOutcomeOrderbookSelectors());
        cuts[20] = _cut(deployment.multiOutcomeOrderbookViewFacet, multiOutcomeOrderbookViewSelectors());
        cuts[21] = _cut(deployment.negRiskConfigFacet, negRiskConfigSelectors());
        cuts[22] = _cut(deployment.comboCoreFacet, comboCoreSelectors());
        cuts[23] = _cut(deployment.comboSettlementFacet, comboSettlementSelectors());
        cuts[24] = _cut(deployment.negRiskConfigFacet, ctfConfigSelectors());
        cuts[25] = _cut(deployment.comboViewFacet, comboViewSelectors());
        cuts[26] = _cut(deployment.comboMarketFacet, comboMarketSelectors());
        cuts[27] = _cut(deployment.parimutuelFacet, parimutuelSelectors());
        cuts[28] = _cut(deployment.parimutuelViewFacet, parimutuelViewSelectors());
        cuts[29] = _cut(deployment.parlayAdminFacet, parlayAdminSelectors());
        cuts[30] = _cut(deployment.parlayUnderwritingFacet, parlayUnderwritingSelectors());
        cuts[31] = _cut(deployment.parlayBudgetFacet, parlayBudgetSelectors());
        cuts[32] = _cut(deployment.parlaySettlementFacet, parlaySettlementSelectors());
        cuts[33] = _cut(deployment.parlayBookFacet, parlayBookSelectors());
        cuts[34] = _cut(deployment.parlayViewFacet, parlayViewSelectors());
        cuts[35] = _cut(deployment.parlayMulticallFacet, parlayMulticallSelectors());
        cuts[36] = _cut(deployment.tradeRouterFacet, tradeRouterSelectors());
        cuts[37] = _cut(deployment.tradeRouterSellFacet, tradeRouterSellSelectors());
        cuts[38] = _cut(deployment.resolverRegistryFacet, resolverRegistrySelectors());
        cuts[39] = _cut(deployment.resolverRegistryViewFacet, resolverRegistryViewSelectors());
        cuts[40] = _cut(deployment.resolverRegistryRewardsFacet, resolverRegistryRewardsSelectors());
        cuts[41] = _cut(deployment.resolverRegistryReputationFacet, resolverRegistryReputationSelectors());
        cuts[42] = _cut(deployment.resolverJuryFacet, resolverJurySelectors());
        cuts[43] = _cut(deployment.delayedOrderFacet, delayedOrderSelectors());
        cuts[44] = _cut(deployment.marginAccountFacet, marginAccountSelectors());
        cuts[45] = _cut(deployment.markOracleFacet, markOracleSelectors());
        cuts[46] = _cut(deployment.quoteEnvelopeFacet, quoteEnvelopeSelectors());
        cuts[47] = _cut(deployment.mloPredictionAdapterFacet, mloPredictionAdapterSelectors());
        cuts[48] = _cut(deployment.mloPredictionCurveFacet, mloPredictionCurveSelectors());
        cuts[49] = _cut(deployment.mloPredictionTradeFacet, mloPredictionTradeSelectors());
        cuts[50] = _cut(deployment.mloPredictionSettlementFacet, mloPredictionSettlementSelectors());
        cuts[51] = _cut(deployment.mloPredictionBidTradeFacet, mloPredictionBidTradeSelectors());
        cuts[52] = _cut(deployment.tradeRouterBookFacet, tradeRouterBookSelectors());
        cuts[53] = _cut(deployment.tradeRouterBookSellFacet, tradeRouterBookSellSelectors());
        cuts[54] = _cut(deployment.mloPredictionAskRouteFacet, mloPredictionAskRouteSelectors());
        cuts[55] = _cut(deployment.mloPredictionRecoveryFacet, mloPredictionRecoverySelectors());
        cuts[56] = _cut(deployment.staticsDollarTradeRouterFacet, staticsDollarTradeRouterSelectors());
        cuts[57] = _cut(deployment.collateralTradeRouterPreviewFacet, collateralTradeRouterPreviewSelectors());
        cuts[58] = _cut(deployment.ctfPositionViewFacet, ctfPositionViewSelectors());
        cuts[59] = _cut(deployment.mloPredictionPostFacet, mloPredictionPostSelectors());
        cuts[60] = _cut(deployment.mloPredictionUpdateFacet, mloPredictionUpdateSelectors());
        cuts[61] = _cut(deployment.tradeRouterExactFacet, tradeRouterExactSelectors());
        cuts[62] = _cut(deployment.bookSellFacet, bookSellSelectors());
        cuts[63] = _cut(deployment.seniorCapitalFacet, seniorCapitalSelectors());
        cuts[64] = _cut(deployment.seniorCapitalViewFacet, seniorCapitalViewSelectors());
        cuts[65] = _cut(deployment.collateralTradeExecutionFacet, collateralTradeExecutionSelectors());
        cuts[66] = _cut(deployment.mloProfitShareFacet, mloProfitShareSelectors());

        ResolverJuryInit init = new ResolverJuryInit();
        DiamondCutFacet(deployment.diamond)
            .diamondCut(
                cuts, address(init), abi.encodeCall(ResolverJuryInit.initResolverJury, (deployment.eveIdentity))
            );
    }

    function _configureDeployment(
        address diamond,
        DeploymentConfig memory config,
        address negRiskAdapter,
        address ctfSettlementAdapter
    ) internal {
        OwnershipFacet(diamond).setDefaultConditionalTokens(config.conditionalTokens);
        OwnershipFacet(diamond).setCollateralToken(config.collateralToken);
        OwnershipFacet(diamond).setEveToken(config.eveToken);
        OwnershipFacet(diamond).setEveTreasury(config.eveTreasury);
        IMarginAccountFacet(diamond).setMarginAsset(config.collateralToken);
        IMLOProfitShareFacet(diamond).initializeMLOProfitSplit(7_500, 2_000, 500, config.mloProfitSplitDelay);
        IMarginAccountFacet(diamond)
            .setDefaultFundingConfig(
                MarginTypes.BucketKind.MLO,
                config.mloDefaultFundingRatePerSecondWad == 0
                    ? MarginTypes.FundingMode.None
                    : MarginTypes.FundingMode.BorrowRate,
                config.mloDefaultFundingRatePerSecondWad
            );
        OwnershipFacet(diamond).setEvesPositionManager(config.evesPositionManager);
        NegRiskConfigFacet(diamond).setNegRiskAdapter(negRiskAdapter);
        NegRiskConfigFacet(diamond).setCTFSettlementAdapter(ctfSettlementAdapter);
        FeeConfigFacet(diamond)
            .setOrderbookFeeSplit(
                config.orderbookMakerFeeBps,
                config.orderbookCreatorFeeBps,
                config.orderbookProtocolFeeBps,
                config.orderbookSeniorPoolFeeBps,
                config.orderbookResolverFeeBps
            );
        FeeConfigFacet(diamond)
            .setSpotFeeSplit(
                config.spotMakerFeeBps,
                config.spotProtocolFeeBps,
                config.spotSeniorPoolFeeBps,
                config.spotResolverFeeBps
            );
        FeeConfigFacet(diamond)
            .setComboFeeSplit(
                config.comboMakerFeeBps,
                config.comboCreatorFeeBps,
                config.comboProtocolFeeBps,
                config.comboSeniorPoolFeeBps,
                config.comboResolverFeeBps
            );
        FeeConfigFacet(diamond)
            .setParimutuelFeeSplit(
                config.parimutuelCreatorFeeBps,
                config.parimutuelProtocolFeeBps,
                config.parimutuelSeniorPoolFeeBps,
                config.parimutuelResolverFeeBps
            );
        OwnershipFacet(diamond)
            .setParimutuelConfig(config.parimutuelShareToken, config.parimutuelEntryFeeBps, config.parimutuelMinEntry);
        ParlayAdminFacet(diamond)
            .setParlayConfig(
                config.parlayTicketToken,
                config.parlayFeeRecipient,
                config.parlayUnderwritingFee,
                config.parlaySeniorPoolFeeBps,
                config.parlayFeeRecipientBps
            );
        OwnershipFacet(diamond).setParimutuelEpochWindowCap(config.parimutuelEpochWindowCap);
        OwnershipFacet(diamond).setParimutuelEpochMultipliers(_defaultParimutuelEpochMultipliers());
        FeeConfigFacet(diamond).setOrderbookEntryFeeBps(config.orderbookEntryFeeBps);
        FeeConfigFacet(diamond).setSpotTradeFeeBps(config.spotTradeFeeBps);
        FeeConfigFacet(diamond).setComboTradeFeeBps(config.comboTradeFeeBps);
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
            .setDelayedOrderGuards(
                config.maxDelayedOrderRouteLength, config.minDelayedOrderQuoteWad, config.minDelayedOrderBaseWad
            );
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
                    resolverSeatStake: 100e18,
                    epochCandidateFeeToken: address(0),
                    epochCandidateFeeAmount: 0
                })
            );
        OwnershipFacet(diamond)
            .setResolverJuryPoolSettings(
                OwnershipConfigTypes.ResolverJuryPoolSettings({
                    activeEpochSize: 16,
                    resolverEpochDuration: 180 days,
                    resolverRotationWindow: 30 days,
                    epochRandomnessCommitDuration: 7 days,
                    epochRandomnessRevealDuration: 7 days,
                    epochSelectionDuration: 3 days,
                    minEpochRandomnessReveals: 2,
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
        OwnershipFacet(deployment.market.diamond)
            .setStaticsDollarRail(
                deployment.staticsDollarCore, config.staticsDollar.peggedProfileId, deployment.usdcToken
            );
        IMLOPredictionAdapterFacet(deployment.market.diamond)
            .setMLORecoveryConfig(deployment.mloInsuranceFund, config.mloFundingSeniorBps, config.mloMaxCleanupBatch);
        if (config.staticsDollar.enableMarkets) {
            OwnershipFacet(deployment.market.diamond)
                .setCollateralProfile(
                    STATICS_DOLLAR_PROFILE_ID,
                    deployment.staticsDollar,
                    address(0),
                    config.staticsDollar.payoutUnit,
                    config.staticsDollar.marketCreationFee,
                    true
                );
            OwnershipFacet(deployment.market.diamond)
                .setCollateralProfileParimutuelCreationSeedAmount(
                    STATICS_DOLLAR_PROFILE_ID, config.staticsDollar.parimutuelCreationSeedAmount
                );
            OwnershipFacet(deployment.market.diamond)
                .setCollateralProfileParimutuelMinEntry(
                    STATICS_DOLLAR_PROFILE_ID, config.staticsDollar.parimutuelMinEntry
                );
            OwnershipFacet(deployment.market.diamond)
                .setCollateralProfileParlayUnderwritingFee(
                    STATICS_DOLLAR_PROFILE_ID, config.staticsDollar.parlayUnderwritingFee
                );
        }
    }

    function _deployAndConfigureFaucet(
        FullDeployment memory deployment,
        FullDeploymentConfig memory config,
        address temporaryOwner
    ) internal returns (address) {
        Faucet faucet = new Faucet(temporaryOwner);
        if (config.faucetUsdcEnabled) {
            faucet.setToken(deployment.usdcToken, config.faucetUsdcClaimAmount, true);
        }
        if (config.faucetEveEnabled) {
            faucet.setToken(deployment.eveToken, config.faucetEveClaimAmount, true);
        }
        if (config.faucetOwner != temporaryOwner) {
            faucet.transferOwnership(config.faucetOwner);
        }

        return address(faucet);
    }

    function _mintFullStackEveToken(
        FullDeployment memory deployment,
        FullDeploymentConfig memory config,
        bool autoDeployEveToken
    ) internal {
        if (autoDeployEveToken && config.initialEveMint != 0) {
            TestnetEVE(deployment.eveToken).mintAndDelegate(config.market.owner, config.initialEveMint);
        }
    }

    function _fundFaucet(FullDeployment memory deployment, FullDeploymentConfig memory config, bool autoDeployEveToken)
        internal
    {
        if (config.faucetUsdcEnabled && config.faucetUsdcFundAmount != 0) {
            IERC20(deployment.usdcToken).safeTransfer(deployment.faucet, config.faucetUsdcFundAmount);
        }
        if (config.faucetEveEnabled && config.faucetEveFundAmount != 0) {
            if (autoDeployEveToken) {
                TestnetEVE(deployment.eveToken).mint(deployment.faucet, config.faucetEveFundAmount);
            } else {
                IERC20(deployment.eveToken).safeTransfer(deployment.faucet, config.faucetEveFundAmount);
            }
        }
    }

    function _finalizeEveTokenOwnership(
        FullDeployment memory deployment,
        FullDeploymentConfig memory config,
        bool autoDeployEveToken
    ) internal {
        if (autoDeployEveToken && TestnetEVE(deployment.eveToken).owner() != config.market.owner) {
            TestnetEVE(deployment.eveToken).transferOwnership(config.market.owner);
        }
    }

    function _bootstrapMLOLiquidity(
        FullDeployment memory deployment,
        FullDeploymentConfig memory config,
        address temporaryOwner
    ) internal {
        uint256 insuranceAssets = config.initialMloInsuranceBootstrapUsdg * 1e12;
        uint256 seniorAssets = config.initialSeniorCapitalBootstrapUsdg * 1e12;
        uint256 totalAssets = insuranceAssets + seniorAssets;
        if (totalAssets == 0) return;

        _ensureStaticsDollarBalance(deployment, config, temporaryOwner, totalAssets);
        if (insuranceAssets != 0) {
            IERC20(deployment.staticsDollar).forceApprove(deployment.mloInsuranceFund, insuranceAssets);
            MLOInsuranceFund(deployment.mloInsuranceFund).sponsor(insuranceAssets);
        }
        if (seniorAssets != 0) {
            IERC20(deployment.staticsDollar).forceApprove(deployment.market.diamond, seniorAssets);
            ISeniorCapitalFacet(deployment.market.diamond).depositSeniorCapital(seniorAssets);
        }
    }

    function _ensureStaticsDollarBalance(
        FullDeployment memory deployment,
        FullDeploymentConfig memory config,
        address temporaryOwner,
        uint256 requiredBalance
    ) internal {
        uint256 currentBalance = IERC20(deployment.staticsDollar).balanceOf(temporaryOwner);
        if (currentBalance >= requiredBalance) return;

        uint256 mintAmount = requiredBalance - currentBalance;
        IStaticsDollarGateway gateway = IStaticsDollarGateway(deployment.staticsDiamond);
        IStaticsDollarCoreTypes.PeggedMintPreview memory preview =
            gateway.previewPeggedMint(config.staticsDollar.peggedProfileId, mintAmount);
        IERC20(deployment.usdcToken).forceApprove(deployment.staticsDiamond, preview.totalCollateralIn);
        gateway.mintPegged(config.staticsDollar.peggedProfileId, mintAmount, preview.totalCollateralIn, temporaryOwner);
        IERC20(deployment.usdcToken).forceApprove(deployment.staticsDiamond, 0);
    }

    function _verifyDeployment(
        Deployment memory deployment,
        uint64 expectedGovernanceDelay,
        uint64 expectedMLOProfitSplitDelay
    ) internal view {
        require(DiamondCutFacet(deployment.diamond).governanceDelayFinalized(), "governance delay not finalized");
        require(
            DiamondCutFacet(deployment.diamond).governanceDelay() == expectedGovernanceDelay,
            "governance delay mismatch"
        );
        require(
            IMLOProfitShareFacet(deployment.diamond).mloProfitSplitDelay() == expectedMLOProfitSplitDelay,
            "MLO profit split delay mismatch"
        );
        MarketFactoryTypes.MarketConfigView memory marketConfig =
            IMarketFactoryFacet(deployment.diamond).getMarketConfig();
        require(
            EvesNegRiskAdapter(deployment.negRiskAdapter).conditionalTokens() == deployment.conditionalTokens,
            "neg-risk CTF mismatch"
        );
        require(
            EvesNegRiskAdapter(deployment.negRiskAdapter).collateralToken() == marketConfig.collateralToken,
            "neg-risk collateral mismatch"
        );
        require(
            EvesNegRiskAdapter(deployment.negRiskAdapter).oracle() == deployment.diamond, "neg-risk oracle mismatch"
        );
        require(
            EvesCTFSettlementAdapter(deployment.ctfSettlementAdapter).conditionalTokens()
                == deployment.conditionalTokens,
            "settlement CTF mismatch"
        );
        require(
            EvesCTFSettlementAdapter(deployment.ctfSettlementAdapter).collateralToken() == marketConfig.collateralToken,
            "settlement collateral mismatch"
        );
        require(
            IMarginAccountFacet(deployment.diamond).marginConfig().marginAsset == marketConfig.collateralToken,
            "margin collateral mismatch"
        );
        require(
            IMLOProfitShareFacet(deployment.diamond).activeMLOProfitSplit().version == 1,
            "profit split version mismatch"
        );
        address[] memory facets = DiamondLoupeFacet(deployment.diamond).facetAddresses();
        require(facets.length == 67, "unexpected facet count");
        for (uint256 index; index < facets.length; ++index) {
            require(facets[index].code.length <= EIP170_MAX_CODE_SIZE, "facet exceeds EIP-170 limit");
        }
        require(deployment.eveIdentity != address(0), "zero eve identity");
        require(EveIdentity(deployment.eveIdentity).diamond() == deployment.diamond, "eve identity diamond mismatch");
        require(
            EvesPositionManager(deployment.evesPositionManager).diamond() == deployment.diamond,
            "eves position manager diamond mismatch"
        );

        _assertSelectorRouting(deployment.diamond, deployment.diamondCutFacet, diamondCutSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.diamondLoupeFacet, loupeSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.ownershipFacet, ownershipSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.feeConfigFacet, feeConfigSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.marketFactoryFacet, marketFactorySelectors());
        _assertSelectorRouting(deployment.diamond, deployment.marketGroupFacet, marketGroupSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.marketViewFacet, marketViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.curveInventoryFacet, curveInventorySelectors());
        _assertSelectorRouting(deployment.diamond, deployment.curveLifecycleFacet, curveLifecycleSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.curveCLOBFacet, curveTradeSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.curveViewFacet, curveViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bookFacet, bookSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bookOrderFacet, bookOrderSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bookTradeFacet, bookTradeSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bookSellFacet, bookSellSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bookViewFacet, bookViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bondManagerFacet, bondManagerSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.bondTokenGateFacet, bondTokenGateSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.obrResolutionFacet, obrResolutionSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.resolverRegistryFacet, resolverRegistrySelectors());
        _assertSelectorRouting(
            deployment.diamond, deployment.resolverRegistryViewFacet, resolverRegistryViewSelectors()
        );
        _assertSelectorRouting(
            deployment.diamond, deployment.resolverRegistryRewardsFacet, resolverRegistryRewardsSelectors()
        );
        _assertSelectorRouting(
            deployment.diamond, deployment.resolverRegistryReputationFacet, resolverRegistryReputationSelectors()
        );
        _assertSelectorRouting(deployment.diamond, deployment.resolverJuryFacet, resolverJurySelectors());
        _assertSelectorRouting(deployment.diamond, deployment.feeRouterFacet, feeRouterSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.marketSettlementFacet, marketSettlementSelectors());
        _assertSelectorRouting(
            deployment.diamond, deployment.multiOutcomeOrderbookFacet, multiOutcomeOrderbookSelectors()
        );
        _assertSelectorRouting(
            deployment.diamond, deployment.multiOutcomeOrderbookViewFacet, multiOutcomeOrderbookViewSelectors()
        );
        _assertSelectorRouting(deployment.diamond, deployment.negRiskConfigFacet, negRiskConfigSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.negRiskConfigFacet, ctfConfigSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.ctfPositionViewFacet, ctfPositionViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.comboCoreFacet, comboCoreSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.comboSettlementFacet, comboSettlementSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.comboViewFacet, comboViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.comboMarketFacet, comboMarketSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parimutuelFacet, parimutuelSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parimutuelViewFacet, parimutuelViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayAdminFacet, parlayAdminSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayUnderwritingFacet, parlayUnderwritingSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayBudgetFacet, parlayBudgetSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlaySettlementFacet, parlaySettlementSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayBookFacet, parlayBookSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayViewFacet, parlayViewSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.parlayMulticallFacet, parlayMulticallSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.tradeRouterFacet, tradeRouterSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.tradeRouterExactFacet, tradeRouterExactSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.tradeRouterSellFacet, tradeRouterSellSelectors());
        _assertSelectorRouting(
            deployment.diamond, deployment.staticsDollarTradeRouterFacet, staticsDollarTradeRouterSelectors()
        );
        _assertSelectorRouting(
            deployment.diamond, deployment.collateralTradeExecutionFacet, collateralTradeExecutionSelectors()
        );
        _assertSelectorRouting(
            deployment.diamond, deployment.collateralTradeRouterPreviewFacet, collateralTradeRouterPreviewSelectors()
        );
        _assertSelectorRouting(deployment.diamond, deployment.delayedOrderFacet, delayedOrderSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.marginAccountFacet, marginAccountSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.mloProfitShareFacet, mloProfitShareSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.markOracleFacet, markOracleSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.quoteEnvelopeFacet, quoteEnvelopeSelectors());
        _assertSelectorRouting(
            deployment.diamond, deployment.mloPredictionAdapterFacet, mloPredictionAdapterSelectors()
        );
        _assertSelectorRouting(deployment.diamond, deployment.mloPredictionCurveFacet, mloPredictionCurveSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.mloPredictionPostFacet, mloPredictionPostSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.mloPredictionUpdateFacet, mloPredictionUpdateSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.mloPredictionTradeFacet, mloPredictionTradeSelectors());
        _assertSelectorRouting(
            deployment.diamond, deployment.mloPredictionAskRouteFacet, mloPredictionAskRouteSelectors()
        );
        _assertSelectorRouting(
            deployment.diamond, deployment.mloPredictionBidTradeFacet, mloPredictionBidTradeSelectors()
        );
        _assertSelectorRouting(
            deployment.diamond, deployment.mloPredictionSettlementFacet, mloPredictionSettlementSelectors()
        );
        _assertSelectorRouting(
            deployment.diamond, deployment.mloPredictionRecoveryFacet, mloPredictionRecoverySelectors()
        );
        _assertSelectorRouting(deployment.diamond, deployment.tradeRouterBookFacet, tradeRouterBookSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.tradeRouterBookSellFacet, tradeRouterBookSellSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.seniorCapitalFacet, seniorCapitalSelectors());
        _assertSelectorRouting(deployment.diamond, deployment.seniorCapitalViewFacet, seniorCapitalViewSelectors());
    }

    function _verifyFullDeployment(FullDeployment memory deployment, FullDeploymentConfig memory config) internal view {
        _verifyDeployment(deployment.market, config.market.governanceDelay, config.market.mloProfitSplitDelay);
        require(deployment.faucet != address(0), "zero faucet");

        MarketFactoryTypes.MarketConfigView memory marketConfig =
            IMarketFactoryFacet(deployment.market.diamond).getMarketConfig();
        require(OwnershipFacet(deployment.market.diamond).owner() == config.market.owner, "owner mismatch");
        require(marketConfig.defaultConditionalTokens == deployment.market.conditionalTokens, "ctf mismatch");
        require(marketConfig.collateralToken == deployment.staticsDollar, "collateral mismatch");
        require(marketConfig.eveToken == deployment.eveToken, "eve token mismatch");
        require(marketConfig.staticsDollarCore == deployment.staticsDollarCore, "staticsDollar rail pool mismatch");
        require(marketConfig.staticsDiamond == deployment.staticsDiamond, "Statics Diamond rail mismatch");
        require(marketConfig.usdcToken == deployment.usdcToken, "staticsDollar rail USDC mismatch");
        require(
            marketConfig.peggedProfileId == config.staticsDollar.peggedProfileId, "staticsDollar rail profile mismatch"
        );
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
            marketConfig.orderbookFeeConfig.seniorPoolFeeBps == config.market.orderbookSeniorPoolFeeBps,
            "orderbook seniorPool fee mismatch"
        );
        require(
            marketConfig.orderbookFeeConfig.resolverFeeBps == config.market.orderbookResolverFeeBps,
            "orderbook resolver fee mismatch"
        );
        require(marketConfig.spotFeeConfig.tradeFeeBps == config.market.spotTradeFeeBps, "spot trade fee mismatch");
        require(marketConfig.spotFeeConfig.makerFeeBps == config.market.spotMakerFeeBps, "spot maker fee mismatch");
        require(
            marketConfig.spotFeeConfig.protocolFeeBps == config.market.spotProtocolFeeBps, "spot protocol fee mismatch"
        );
        require(
            marketConfig.spotFeeConfig.seniorPoolFeeBps == config.market.spotSeniorPoolFeeBps,
            "spot seniorPool fee mismatch"
        );
        require(
            marketConfig.spotFeeConfig.resolverFeeBps == config.market.spotResolverFeeBps, "spot resolver fee mismatch"
        );
        require(marketConfig.comboFeeConfig.tradeFeeBps == config.market.comboTradeFeeBps, "combo trade fee mismatch");
        require(marketConfig.comboFeeConfig.makerFeeBps == config.market.comboMakerFeeBps, "combo maker fee mismatch");
        require(
            marketConfig.comboFeeConfig.creatorFeeBps == config.market.comboCreatorFeeBps, "combo creator fee mismatch"
        );
        require(
            marketConfig.comboFeeConfig.protocolFeeBps == config.market.comboProtocolFeeBps,
            "combo protocol fee mismatch"
        );
        require(
            marketConfig.comboFeeConfig.seniorPoolFeeBps == config.market.comboSeniorPoolFeeBps,
            "combo seniorPool fee mismatch"
        );
        require(
            marketConfig.comboFeeConfig.resolverFeeBps == config.market.comboResolverFeeBps,
            "combo resolver fee mismatch"
        );
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
            marketConfig.parimutuelFeeConfig.seniorPoolFeeBps == config.market.parimutuelSeniorPoolFeeBps,
            "parimutuel seniorPool fee mismatch"
        );
        require(
            marketConfig.parimutuelFeeConfig.resolverFeeBps == config.market.parimutuelResolverFeeBps,
            "parimutuel resolver fee mismatch"
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
        require(
            marketConfig.maxDelayedOrderRouteLength == config.market.maxDelayedOrderRouteLength,
            "delayed route cap mismatch"
        );
        require(
            marketConfig.minDelayedOrderQuoteWad == config.market.minDelayedOrderQuoteWad, "delayed min quote mismatch"
        );
        require(
            marketConfig.minDelayedOrderBaseWad == config.market.minDelayedOrderBaseWad, "delayed min base mismatch"
        );

        ISeniorCapitalFacet.SeniorCapitalState memory seniorState =
            ISeniorCapitalFacet(deployment.market.diamond).seniorCapitalState();
        require(seniorState.asset == deployment.staticsDollar, "senior asset mismatch");
        require(
            MLOInsuranceFund(deployment.mloInsuranceFund).owner() == config.market.owner, "insurance owner mismatch"
        );
        require(
            MLOInsuranceFund(deployment.mloInsuranceFund).governance() == deployment.market.diamond,
            "insurance governance mismatch"
        );
        require(
            MLOInsuranceFund(deployment.mloInsuranceFund).asset() == deployment.staticsDollar,
            "insurance asset mismatch"
        );
        require(
            MLOInsuranceFund(deployment.mloInsuranceFund).riskManager() == deployment.market.diamond,
            "insurance risk manager mismatch"
        );
        MLOPredictionTypes.MLORecoveryConfig memory recoveryConfig =
            IMLOPredictionAdapterFacet(deployment.market.diamond).mloRecoveryConfig();
        require(recoveryConfig.insuranceFund == deployment.mloInsuranceFund, "insurance config mismatch");
        require(recoveryConfig.seniorFundingBps == config.mloFundingSeniorBps, "funding split mismatch");
        require(recoveryConfig.maxCleanupBatch == config.mloMaxCleanupBatch, "cleanup cap mismatch");
        if (config.initialMloInsuranceBootstrapUsdg != 0) {
            require(
                MLOInsuranceFund(deployment.mloInsuranceFund).availableInsurance()
                    >= config.initialMloInsuranceBootstrapUsdg * 1e12,
                "insurance bootstrap missing"
            );
        }
        require(seniorState.activationDelay == 15 minutes, "senior activation delay mismatch");
        require(
            seniorState.pendingPrincipal + seniorState.totalPrincipal
                == config.initialSeniorCapitalBootstrapUsdg * 1e12,
            "senior bootstrap mismatch"
        );
        if (_staticsDollarStackRequested(config.staticsDollar)) {
            require(deployment.staticsDollar != address(0), "staticsDollar missing");
            require(deployment.staticsDollarCore != address(0), "staticsDollar core missing");
            require(deployment.staticsDiamond != address(0), "Statics Diamond missing");
            IStaticsDollarCore core = IStaticsDollarCore(deployment.staticsDollarCore);
            require(
                IStaticsDollar(deployment.staticsDollar).pool() == deployment.staticsDollarCore,
                "staticsDollar core mismatch"
            );
            IStaticsDollarCoreTypes.StableCollateralProfile memory stableProfile =
                core.collateralProfile(config.staticsDollar.peggedProfileId);
            require(stableProfile.collateralToken == deployment.usdcToken, "staticsDollar USDC mismatch");
            require(
                stableProfile.kind == IStaticsDollarCoreTypes.ProfileKind.Pegged, "staticsDollar profile kind mismatch"
            );
            require(core.staticsDollar() == deployment.staticsDollar, "core staticsDollar mismatch");
            require(core.periphery() == deployment.staticsDiamond, "core Statics Diamond mismatch");
            require(core.positionNFT() == deployment.staticsDiamond, "shared position mismatch");
            require(
                IStaticsDollarGateway(deployment.staticsDiamond).pool() == deployment.staticsDollarCore,
                "gateway core mismatch"
            );
        }
        if (config.staticsDollar.enableMarkets) {
            MarketFactoryTypes.CollateralProfileView memory profile =
                IMarketFactoryFacet(deployment.market.diamond).getCollateralProfile(STATICS_DOLLAR_PROFILE_ID);
            require(profile.collateralToken == deployment.staticsDollar, "staticsDollar profile collateral mismatch");
            require(profile.wrapperToken == address(0), "staticsDollar profile wrapper mismatch");
            require(profile.payoutUnit == config.staticsDollar.payoutUnit, "staticsDollar profile payout mismatch");
            require(
                profile.marketCreationFee == config.staticsDollar.marketCreationFee,
                "staticsDollar profile fee mismatch"
            );
            require(profile.enabled, "staticsDollar profile disabled");
            (uint128 profileSeed, uint128 profileMinEntry) = IMarketFactoryFacet(deployment.market.diamond)
                .getCollateralProfileParimutuelConfig(STATICS_DOLLAR_PROFILE_ID);
            require(
                profileSeed == config.staticsDollar.parimutuelCreationSeedAmount,
                "staticsDollar parimutuel seed mismatch"
            );
            require(profileMinEntry == config.staticsDollar.parimutuelMinEntry, "staticsDollar parimutuel min mismatch");
            uint128 profileParlayFee = IMarketFactoryFacet(deployment.market.diamond)
                .getCollateralProfileParlayUnderwritingFee(STATICS_DOLLAR_PROFILE_ID);
            require(profileParlayFee == config.staticsDollar.parlayUnderwritingFee, "staticsDollar parlay fee mismatch");
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
        require(parlayConfig.seniorPoolFeeBps == config.market.parlaySeniorPoolFeeBps, "parlay seniorPool fee mismatch");
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

    function _assertSelectorsAbsent(address diamond, bytes4[] memory selectors) internal view {
        for (uint256 index; index < selectors.length; ++index) {
            require(DiamondLoupeFacet(diamond).facetAddress(selectors[index]) == address(0), "selector still routed");
        }
    }

    function _resolveConditionalTokens(address configuredAddress, string memory artifactPath)
        internal
        returns (address conditionalTokens)
    {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }
        if (block.chainid == ROBINHOOD_TESTNET_CHAIN_ID) {
            revert RobinhoodTestnetConditionalTokensRequired();
        }

        bytes memory creationCode = _loadConditionalTokensCreationCode(artifactPath);
        require(creationCode.length != 0, "empty conditional tokens bytecode");

        assembly {
            conditionalTokens := create(0, add(creationCode, 0x20), mload(creationCode))
        }

        require(conditionalTokens != address(0), "conditional tokens deploy failed");
    }

    function _resolveEveToken(address configuredAddress, address temporaryOwner) internal returns (address) {
        if (configuredAddress != address(0)) {
            return configuredAddress;
        }

        return address(new TestnetEVE(temporaryOwner));
    }

    function _resolveStaticsDollarStack(StaticsDollarStackConfig memory config)
        internal
        view
        returns (StaticsDollarStackDeployment memory deployment)
    {
        IStaticsDollarCore core = IStaticsDollarCore(config.core);
        deployment.core = config.core;
        deployment.staticsDollar = core.staticsDollar();
        deployment.staticsDiamond = core.periphery();
    }

    function _staticsDollarStackRequested(StaticsDollarStackConfig memory config) internal pure returns (bool) {
        return config.enableMarkets || config.core != address(0);
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

    function _resolveMLOInsuranceFund(address configuredAddress, address asset, address governance, address riskManager)
        internal
        returns (address)
    {
        if (configuredAddress != address(0)) return configuredAddress;
        return address(new MLOInsuranceFund(asset, governance, riskManager));
    }

    function _releaseSurface(FullDeployment memory deployment) internal view returns (ReleaseSurface memory surface) {
        (surface.criticalNames, surface.criticalAddresses) = _criticalContracts(deployment);
        surface.criticalRuntimeCodeHashes = new bytes32[](surface.criticalAddresses.length);
        for (uint256 index; index < surface.criticalAddresses.length; ++index) {
            require(surface.criticalAddresses[index].code.length != 0, "critical contract has no code");
            surface.criticalRuntimeCodeHashes[index] = surface.criticalAddresses[index].codehash;
        }

        DiamondLoupeFacet.Facet[] memory facets = DiamondLoupeFacet(deployment.market.diamond).facets();
        uint256 selectorCount;
        for (uint256 index; index < facets.length; ++index) {
            selectorCount += facets[index].functionSelectors.length;
        }

        surface.facetAddresses = new address[](facets.length);
        surface.facetRuntimeCodeHashes = new bytes32[](facets.length);
        surface.facetSelectorCounts = new uint256[](facets.length);
        surface.selectors = new bytes32[](selectorCount);
        surface.selectorFacets = new address[](selectorCount);

        uint256 flatIndex;
        for (uint256 facetIndex; facetIndex < facets.length; ++facetIndex) {
            DiamondLoupeFacet.Facet memory facet = facets[facetIndex];
            surface.facetAddresses[facetIndex] = facet.facetAddress;
            surface.facetRuntimeCodeHashes[facetIndex] = facet.facetAddress.codehash;
            surface.facetSelectorCounts[facetIndex] = facet.functionSelectors.length;
            for (uint256 selectorIndex; selectorIndex < facet.functionSelectors.length; ++selectorIndex) {
                surface.selectors[flatIndex] = bytes32(facet.functionSelectors[selectorIndex]);
                surface.selectorFacets[flatIndex] = facet.facetAddress;
                ++flatIndex;
            }
        }

        surface.absentSelectors = _legacyAbsentSelectors();
        for (uint256 index; index < surface.absentSelectors.length; ++index) {
            require(
                DiamondLoupeFacet(deployment.market.diamond).facetAddress(bytes4(surface.absentSelectors[index]))
                    == address(0),
                "legacy selector routed"
            );
        }
    }

    function _criticalContracts(FullDeployment memory deployment)
        internal
        pure
        returns (string[] memory names, address[] memory addresses)
    {
        names = new string[](15);
        addresses = new address[](15);

        names[0] = "EveMarketDiamond";
        addresses[0] = deployment.market.diamond;
        names[1] = "ConditionalTokens";
        addresses[1] = deployment.market.conditionalTokens;
        names[2] = "EVE";
        addresses[2] = deployment.eveToken;
        names[3] = "MLOInsuranceFund";
        addresses[3] = deployment.mloInsuranceFund;
        names[4] = "Faucet";
        addresses[4] = deployment.faucet;
        names[5] = "USDstx";
        addresses[5] = deployment.staticsDollar;
        names[6] = "StaticsDollarCoreDiamond";
        addresses[6] = deployment.staticsDollarCore;
        names[7] = "StaticsDiamond";
        addresses[7] = deployment.staticsDiamond;
        names[8] = "MockUSDG";
        addresses[8] = deployment.usdcToken;
        names[9] = "EvesPositionManager";
        addresses[9] = deployment.market.evesPositionManager;
        names[10] = "EvesNegRiskAdapter";
        addresses[10] = deployment.market.negRiskAdapter;
        names[11] = "EvesCTFSettlementAdapter";
        addresses[11] = deployment.market.ctfSettlementAdapter;
        names[12] = "ParimutuelShareToken";
        addresses[12] = deployment.market.parimutuelShareToken;
        names[13] = "ParlayTicketToken";
        addresses[13] = deployment.market.parlayTicketToken;
        names[14] = "EveIdentity";
        addresses[14] = deployment.market.eveIdentity;
    }

    function _legacyAbsentSelectors() internal pure returns (bytes32[] memory selectors) {
        selectors = new bytes32[](5);
        selectors[0] = bytes32(
            bytes4(
                keccak256(
                    "buyWithEveUSDC((bytes32,bool,uint128,uint128,uint128,uint256[],uint32[],bytes32[],address,address))"
                )
            )
        );
        selectors[1] = bytes32(
            bytes4(
                keccak256(
                    "buyWithUSDC((bytes32,bool,uint128,uint128,uint128,uint256[],uint32[],bytes32[],address,address))"
                )
            )
        );
        selectors[2] = bytes32(
            bytes4(keccak256("sellWithEveUSDC((bytes32,bool,uint128,uint128,uint256[],uint32[],bytes32[],address))"))
        );
        selectors[3] = bytes32(
            bytes4(keccak256("sellWithUSDC((bytes32,bool,uint128,uint128,uint256[],uint32[],bytes32[],address))"))
        );
        selectors[4] = bytes32(bytes4(keccak256("splitWithUSDC(bytes32,uint128,address)")));
    }

    function _verifyReleaseSurface(string memory json, ReleaseSurface memory expected) internal pure {
        string[] memory criticalNames = vm.parseJsonStringArray(json, ".criticalContractNames");
        address[] memory criticalAddresses = vm.parseJsonAddressArray(json, ".criticalContractAddresses");
        bytes32[] memory criticalHashes = vm.parseJsonBytes32Array(json, ".criticalRuntimeCodeHashes");
        require(criticalNames.length == expected.criticalNames.length, "critical name count mismatch");
        require(criticalAddresses.length == expected.criticalAddresses.length, "critical address count mismatch");
        require(criticalHashes.length == expected.criticalRuntimeCodeHashes.length, "critical hash count mismatch");
        for (uint256 index; index < criticalNames.length; ++index) {
            require(
                keccak256(bytes(criticalNames[index])) == keccak256(bytes(expected.criticalNames[index])),
                "critical name mismatch"
            );
            require(criticalAddresses[index] == expected.criticalAddresses[index], "critical address mismatch");
            require(criticalHashes[index] == expected.criticalRuntimeCodeHashes[index], "critical codehash mismatch");
        }

        address[] memory facetAddresses = vm.parseJsonAddressArray(json, ".facetAddresses");
        bytes32[] memory facetHashes = vm.parseJsonBytes32Array(json, ".facetRuntimeCodeHashes");
        uint256[] memory selectorCounts = vm.parseJsonUintArray(json, ".facetSelectorCounts");
        require(facetAddresses.length == expected.facetAddresses.length, "facet address count mismatch");
        require(facetHashes.length == expected.facetRuntimeCodeHashes.length, "facet hash count mismatch");
        require(selectorCounts.length == expected.facetSelectorCounts.length, "facet selector count mismatch");
        for (uint256 index; index < facetAddresses.length; ++index) {
            require(facetAddresses[index] == expected.facetAddresses[index], "facet address mismatch");
            require(facetHashes[index] == expected.facetRuntimeCodeHashes[index], "facet codehash mismatch");
            require(selectorCounts[index] == expected.facetSelectorCounts[index], "facet selector mismatch");
        }

        bytes32[] memory selectors = vm.parseJsonBytes32Array(json, ".selectors");
        address[] memory selectorFacets = vm.parseJsonAddressArray(json, ".selectorFacets");
        require(selectors.length == expected.selectors.length, "selector count mismatch");
        require(selectorFacets.length == expected.selectorFacets.length, "selector route count mismatch");
        for (uint256 index; index < selectors.length; ++index) {
            require(selectors[index] == expected.selectors[index], "selector mismatch");
            require(selectorFacets[index] == expected.selectorFacets[index], "selector facet mismatch");
        }

        bytes32[] memory absentSelectors = vm.parseJsonBytes32Array(json, ".absentSelectors");
        require(absentSelectors.length == expected.absentSelectors.length, "absent selector count mismatch");
        for (uint256 index; index < absentSelectors.length; ++index) {
            require(absentSelectors[index] == expected.absentSelectors[index], "absent selector mismatch");
        }
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

    function _loadConditionalTokensRuntimeCode(string memory artifactPath)
        internal
        view
        returns (bytes memory runtimeCode)
    {
        string memory artifactJson = vm.readFile(string.concat(vm.projectRoot(), "/", artifactPath));

        if (artifactJson.keyExists(".deployedBytecode.object")) {
            return artifactJson.readBytes(".deployedBytecode.object");
        }

        return artifactJson.readBytes(".deployedBytecode");
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
