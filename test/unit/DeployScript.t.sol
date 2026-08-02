// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {StaticsDollar} from "@statics/dollar/StaticsDollar.sol";
import {IStaticsDollarCore} from "@statics/dollar/core/interfaces/IStaticsDollarCore.sol";
import {IStaticsDollarCoreTypes} from "@statics/dollar/interfaces/IStaticsDollarCoreTypes.sol";

import {Faucet} from "../../src/Faucet.sol";
import {MLOInsuranceFund} from "../../src/MLOInsuranceFund.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {CollateralTradeRouterFacet} from "../../src/facets/CollateralTradeRouterFacet.sol";
import {CollateralTradeRouterExactFacet} from "../../src/facets/CollateralTradeRouterExactFacet.sol";
import {CollateralTradeRouterSellFacet} from "../../src/facets/CollateralTradeRouterSellFacet.sol";
import {CollateralTradeRouterPreviewFacet} from "../../src/facets/CollateralTradeRouterPreviewFacet.sol";
import {StaticsDollarTradeRouterFacet} from "../../src/facets/StaticsDollarTradeRouterFacet.sol";
import {CollateralTradeExecutionFacet} from "../../src/facets/CollateralTradeExecutionFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookSellFacet} from "../../src/facets/BookSellFacet.sol";
import {IComboCoreFacet} from "../../src/interfaces/IComboCoreFacet.sol";
import {IComboSettlementFacet} from "../../src/interfaces/IComboSettlementFacet.sol";
import {IComboViewFacet} from "../../src/interfaces/IComboViewFacet.sol";
import {INegRiskConfigFacet} from "../../src/interfaces/INegRiskConfigFacet.sol";
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
import {IMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {IMLOPredictionAdapterFacet} from "../../src/interfaces/IMLOPredictionAdapterFacet.sol";
import {IMLOProfitShareFacet} from "../../src/interfaces/IMLOProfitShareFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IParlayFacet} from "../../src/interfaces/IParlayFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {IResolverRegistryFacet} from "../../src/interfaces/IResolverRegistryFacet.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {IComboMarketFacet} from "../../src/interfaces/IComboMarketFacet.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {IConditionalTokens} from "../../src/interfaces/IConditionalTokens.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {EveIdentity} from "../../src/tokens/EveIdentity.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";
import {NativePositionTypes} from "../../src/types/NativePositionTypes.sol";

import {DeployScript} from "../../script/Deploy.s.sol";

import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";
import {StaticsDollarCoreFixture} from "../helpers/StaticsDollarCoreFixture.sol";
import {MockEveToken} from "../helpers/MockEveToken.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {MLOPredictionTypes} from "../../src/types/MLOPredictionTypes.sol";
import {MLOProfitShareTypes} from "../../src/types/MLOProfitShareTypes.sol";
import {QuoteEnvelopeTypes} from "../../src/types/QuoteEnvelopeTypes.sol";

contract ConfigProbeFacet {
    struct ConfigSnapshot {
        address conditionalTokens;
        address collateralToken;
        address eveToken;
        address eveTreasury;
        address parimutuelShareToken;
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
        uint16 marketCreationBatchCap;
        uint8 maxEscalation;
        bool permissionlessCreationEnabled;
    }

    function getConfig() external view returns (ConfigSnapshot memory snapshot) {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;

        snapshot.conditionalTokens = config.defaultConditionalTokens;
        snapshot.collateralToken = config.collateralToken;
        snapshot.eveToken = config.eveToken;
        snapshot.eveTreasury = config.eveTreasury;
        snapshot.parimutuelShareToken = config.parimutuelShareToken;
        snapshot.orderbookEntryFeeBps = config.orderbookFeeConfig.entryFeeBps;
        snapshot.orderbookMakerFeeBps = config.orderbookFeeConfig.makerFeeBps;
        snapshot.orderbookCreatorFeeBps = config.orderbookFeeConfig.creatorFeeBps;
        snapshot.orderbookProtocolFeeBps = config.orderbookFeeConfig.protocolFeeBps;
        snapshot.orderbookSeniorPoolFeeBps = config.orderbookFeeConfig.seniorPoolFeeBps;
        snapshot.orderbookResolverFeeBps = config.orderbookFeeConfig.resolverFeeBps;
        snapshot.spotTradeFeeBps = config.spotFeeConfig.tradeFeeBps;
        snapshot.spotMakerFeeBps = config.spotFeeConfig.makerFeeBps;
        snapshot.spotProtocolFeeBps = config.spotFeeConfig.protocolFeeBps;
        snapshot.spotSeniorPoolFeeBps = config.spotFeeConfig.seniorPoolFeeBps;
        snapshot.spotResolverFeeBps = config.spotFeeConfig.resolverFeeBps;
        snapshot.comboTradeFeeBps = config.comboFeeConfig.tradeFeeBps;
        snapshot.comboMakerFeeBps = config.comboFeeConfig.makerFeeBps;
        snapshot.comboCreatorFeeBps = config.comboFeeConfig.creatorFeeBps;
        snapshot.comboProtocolFeeBps = config.comboFeeConfig.protocolFeeBps;
        snapshot.comboSeniorPoolFeeBps = config.comboFeeConfig.seniorPoolFeeBps;
        snapshot.comboResolverFeeBps = config.comboFeeConfig.resolverFeeBps;
        snapshot.parimutuelEntryFeeBps = config.parimutuelFeeConfig.entryFeeBps;
        snapshot.parimutuelCreatorFeeBps = config.parimutuelFeeConfig.creatorFeeBps;
        snapshot.parimutuelProtocolFeeBps = config.parimutuelFeeConfig.protocolFeeBps;
        snapshot.parimutuelSeniorPoolFeeBps = config.parimutuelFeeConfig.seniorPoolFeeBps;
        snapshot.parimutuelResolverFeeBps = config.parimutuelFeeConfig.resolverFeeBps;
        snapshot.parimutuelMinEntry = config.parimutuelMinEntry;
        snapshot.parimutuelCreationSeedAmount = config.parimutuelCreationSeedAmount;
        snapshot.marketCreationFee = config.marketCreationFee;
        snapshot.spotBookCreationFee = config.spotBookCreationFee;
        snapshot.comboMarketCreationFee = config.comboMarketCreationFee;
        snapshot.marketCreationBond = config.marketCreationBond;
        snapshot.bondToken = config.bondToken;
        snapshot.resolutionBondL1 = config.resolutionBondL1;
        snapshot.resolutionBondL2 = config.resolutionBondL2;
        snapshot.minMarketDuration = config.minMarketDuration;
        snapshot.maxMarketDuration = config.maxMarketDuration;
        snapshot.disputeWindow = config.disputeWindow;
        snapshot.creatorSettleGrace = config.creatorSettleGrace;
        snapshot.openResolutionTimeout = config.openResolutionTimeout;
        snapshot.marketCreationBatchCap = config.marketCreationBatchCap;
        snapshot.maxEscalation = config.maxEscalation;
        snapshot.permissionlessCreationEnabled = config.permissionlessCreationEnabled;
    }
}

contract DeployScriptTest is Test, StaticsDollarCoreFixture {
    uint256 internal constant EIP170_MAX_CODE_SIZE = 24_576;

    function test_ProductionTradeRouterFacetsRemainDeployable() public {
        assertLe(address(new CollateralTradeRouterFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new CollateralTradeRouterExactFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new CollateralTradeRouterSellFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new CollateralTradeRouterPreviewFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new StaticsDollarTradeRouterFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new CollateralTradeExecutionFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new BookTradeFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new BookSellFacet()).code.length, EIP170_MAX_CODE_SIZE);
    }

    function test_ProductionDelayedOrderExecutionLibrariesRemainDeployable() public {
        _assertMaxCodeSize(deployCode("LibDelayedOrderEscrowAskFill.sol:LibDelayedOrderEscrowAskFill"));
        _assertMaxCodeSize(deployCode("LibDelayedOrderMLOAskFill.sol:LibDelayedOrderMLOAskFill"));
        _assertMaxCodeSize(deployCode("LibDelayedOrderSellFill.sol:LibDelayedOrderSellFill"));
    }

    function test_DeployAutoDeploysConditionalTokensWhenConfigOmitsAddress() public {
        DeployScript deployScript = new DeployScript();
        MockUSDC collateralToken = new MockUSDC();
        MockEveToken eveToken = new MockEveToken();
        address protocolOwner = makeAddr("protocolOwner");
        address treasury = makeAddr("treasury");

        DeployScript.DeploymentConfig memory config = DeployScript.DeploymentConfig({
            owner: protocolOwner,
            conditionalTokens: address(0),
            conditionalTokensArtifactPath: "",
            collateralToken: address(collateralToken),
            eveToken: address(eveToken),
            eveTreasury: treasury,
            evesPositionManager: address(0),
            parimutuelShareToken: address(0),
            parlayTicketToken: address(0),
            parlayFeeRecipient: treasury,
            parlayUnderwritingFee: 3e18,
            parlaySeniorPoolFeeBps: 0,
            parlayFeeRecipientBps: 10_000,
            orderbookEntryFeeBps: 100,
            orderbookMakerFeeBps: 4_000,
            orderbookCreatorFeeBps: 500,
            orderbookProtocolFeeBps: 1_000,
            orderbookSeniorPoolFeeBps: 4_000,
            orderbookResolverFeeBps: 500,
            spotTradeFeeBps: 75,
            spotMakerFeeBps: 4_000,
            spotProtocolFeeBps: 1_500,
            spotSeniorPoolFeeBps: 4_000,
            spotResolverFeeBps: 500,
            comboTradeFeeBps: 80,
            comboMakerFeeBps: 4_000,
            comboCreatorFeeBps: 500,
            comboProtocolFeeBps: 1_000,
            comboSeniorPoolFeeBps: 4_000,
            comboResolverFeeBps: 500,
            parimutuelEntryFeeBps: 250,
            parimutuelCreatorFeeBps: 500,
            parimutuelProtocolFeeBps: 5_000,
            parimutuelSeniorPoolFeeBps: 4_000,
            parimutuelResolverFeeBps: 500,
            parimutuelMinEntry: 1e18,
            parimutuelCreationSeedAmount: 25e18,
            parimutuelEpochWindowCap: 30 days,
            marketCreationBatchCap: 24,
            marketCreationFee: 50e18,
            spotBookCreationFee: 250e18,
            comboMarketCreationFee: 250e18,
            marketCreationBond: 100e18,
            bondToken: address(eveToken),
            resolutionBondL1: 0.1 ether,
            resolutionBondL2: 0.5 ether,
            minMarketDuration: 1 hours,
            maxMarketDuration: 90 days,
            disputeWindow: 2 hours,
            creatorSettleGrace: 24 hours,
            openResolutionTimeout: 2 days,
            maxEscalation: 2,
            permissionlessCreationEnabled: true,
            delayedOrderProtectionDelayBlocks: 2,
            delayedOrderExecutionGraceBlocks: 20,
            delayedOrderRestingDurationMinutes: 180,
            delayedOrderProcessorFeeShareBps: 0,
            delayedOrderProcessingMode: uint8(LibEveMarket.ProcessingMode.ProtocolOnly),
            maxDelayedOrderRouteLength: 64,
            minDelayedOrderQuoteWad: 1e18,
            minDelayedOrderBaseWad: 1e18,
            mloDefaultFundingRatePerSecondWad: 1e10
        });

        DeployScript.Deployment memory deployment = deployScript.deploy(config, address(deployScript));

        deployScript.verifyDeployment(deployment);
        _assertDiamondFacetSizes(deployment.diamond);

        assertEq(OwnershipFacet(deployment.diamond).owner(), protocolOwner);
        assertEq(DiamondLoupeFacet(deployment.diamond).facetAddresses().length, 67);
        MLOProfitShareTypes.ProfitSplit memory profitSplit =
            IMLOProfitShareFacet(deployment.diamond).activeMLOProfitSplit();
        assertEq(profitSplit.makerBps, 7_500);
        assertEq(profitSplit.seniorBps, 2_000);
        assertEq(profitSplit.insuranceBps, 500);
        assertEq(profitSplit.version, 1);
        assertTrue(deployment.negRiskAdapter != address(0));
        assertTrue(deployment.ctfSettlementAdapter != address(0));
        assertEq(INegRiskConfigFacet(deployment.diamond).negRiskAdapter(), deployment.negRiskAdapter);
        assertEq(INegRiskConfigFacet(deployment.diamond).ctfSettlementAdapter(), deployment.ctfSettlementAdapter);
        assertEq(
            DiamondLoupeFacet(deployment.diamond)
                .facetAddress(bytes4(keccak256("prepareNativeNegRiskCondition(bytes32,uint8)"))),
            address(0)
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond)
                .facetAddress(bytes4(keccak256("splitComboOnCondition(uint256,bytes32,uint128,address,address)"))),
            address(0)
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond)
                .facetAddress(bytes4(keccak256("compressCombo(uint256,uint128,address)"))),
            address(0)
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond)
                .facetAddress(bytes4(keccak256("previewComboCompression(uint256,uint128)"))),
            address(0)
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond).facetAddress(bytes4(keccak256("setMarginRiskManager(address)"))),
            address(0)
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond).facetAddress(bytes4(keccak256("recordBucketDebt(bytes32,uint256)"))),
            address(0)
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond).facetAddress(bytes4(keccak256("setBucketState(bytes32,uint8)"))),
            address(0)
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond).facetAddress(bytes4(keccak256("riskDomainRiskParams(bytes32)"))),
            address(0)
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond)
                .facetAddress(bytes4(keccak256("setRiskDomainRiskParams(bytes32,uint16,uint16)"))),
            address(0)
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond).facetAddress(bytes4(keccak256("clearRiskDomainRiskParams(bytes32)"))),
            address(0)
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond).facetAddress(IMarginAccountFacet.riskDomainRiskParams.selector),
            deployment.marginAccountFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond).facetAddress(IMarginAccountFacet.setRiskDomainRiskParams.selector),
            deployment.marginAccountFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond).facetAddress(IMarginAccountFacet.clearRiskDomainRiskParams.selector),
            deployment.marginAccountFacet
        );
        assertTrue(deployment.parimutuelShareToken != address(0));
        assertTrue(deployment.parlayTicketToken != address(0));
        assertTrue(deployment.eveIdentity != address(0));
        assertEq(ParimutuelShareToken(deployment.parimutuelShareToken).diamond(), deployment.diamond);
        assertEq(EveIdentity(deployment.eveIdentity).diamond(), deployment.diamond);
        assertEq(EvesPositionManager(deployment.evesPositionManager).diamond(), deployment.diamond);
        assertEq(IResolverRegistryFacet(deployment.diamond).activeResolverEpochSize(), 16);
        assertEq(IMarginAccountFacet(deployment.diamond).marginConfig().marginAsset, address(collateralToken));
        MarginTypes.FundingConfig memory funding =
            IMarginAccountFacet(deployment.diamond).defaultFundingConfig(MarginTypes.BucketKind.MLO);
        assertEq(uint8(funding.mode), uint8(MarginTypes.FundingMode.BorrowRate));
        assertEq(funding.ratePerSecondWad, 1e10);
        MarginTypes.RiskParams memory mloRisk =
            IMarginAccountFacet(deployment.diamond).defaultRiskParams(MarginTypes.BucketKind.MLO);
        assertEq(mloRisk.initialMarginBps, 10_000);
        assertEq(mloRisk.maintenanceMarginBps, 9_000);
        uint256 identityId = IResolverRegistryFacet(deployment.diamond).mintIdentity();
        assertEq(EveIdentity(deployment.eveIdentity).ownerOf(identityId), address(this));
        assertEq(
            DiamondLoupeFacet(deployment.diamond)
                .facetAddress(
                    bytes4(
                        keccak256(
                            "createParimutuelMarket((string,string,string,uint64,uint64,uint64,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
                        )
                    )
                ),
            deployment.parimutuelFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.diamond).facetAddress(IParlayFacet.createParlayBudget.selector),
            deployment.parlayBudgetFacet
        );

        ConfigProbeFacet probe = new ConfigProbeFacet();
        _attachConfigProbe(deployment.diamond, protocolOwner, address(probe));

        ConfigProbeFacet.ConfigSnapshot memory snapshot = ConfigProbeFacet(deployment.diamond).getConfig();

        assertTrue(deployment.conditionalTokens != address(0));
        assertEq(snapshot.conditionalTokens, deployment.conditionalTokens);
        assertEq(snapshot.collateralToken, address(collateralToken));
        assertEq(snapshot.eveToken, address(eveToken));
        assertEq(snapshot.eveTreasury, treasury);
        assertEq(snapshot.parimutuelShareToken, deployment.parimutuelShareToken);
        assertEq(snapshot.orderbookEntryFeeBps, 100);
        assertEq(snapshot.orderbookMakerFeeBps, 4_000);
        assertEq(snapshot.orderbookCreatorFeeBps, 500);
        assertEq(snapshot.orderbookProtocolFeeBps, 1_000);
        assertEq(snapshot.orderbookSeniorPoolFeeBps, 4_000);
        assertEq(snapshot.orderbookResolverFeeBps, 500);
        assertEq(snapshot.spotTradeFeeBps, 75);
        assertEq(snapshot.spotMakerFeeBps, 4_000);
        assertEq(snapshot.spotProtocolFeeBps, 1_500);
        assertEq(snapshot.spotSeniorPoolFeeBps, 4_000);
        assertEq(snapshot.spotResolverFeeBps, 500);
        assertEq(snapshot.comboTradeFeeBps, 80);
        assertEq(snapshot.comboMakerFeeBps, 4_000);
        assertEq(snapshot.comboCreatorFeeBps, 500);
        assertEq(snapshot.comboProtocolFeeBps, 1_000);
        assertEq(snapshot.comboSeniorPoolFeeBps, 4_000);
        assertEq(snapshot.comboResolverFeeBps, 500);
        assertEq(snapshot.parimutuelEntryFeeBps, 250);
        assertEq(snapshot.parimutuelCreatorFeeBps, 500);
        assertEq(snapshot.parimutuelProtocolFeeBps, 5_000);
        assertEq(snapshot.parimutuelSeniorPoolFeeBps, 4_000);
        assertEq(snapshot.parimutuelResolverFeeBps, 500);
        assertEq(snapshot.parimutuelMinEntry, 1e18);
        assertEq(snapshot.parimutuelCreationSeedAmount, 25e18);
        assertEq(snapshot.marketCreationFee, 50e18);
        assertEq(snapshot.spotBookCreationFee, 250e18);
        assertEq(snapshot.comboMarketCreationFee, 250e18);
        assertEq(snapshot.marketCreationBond, 100e18);
        assertEq(snapshot.bondToken, address(eveToken));
        assertEq(snapshot.resolutionBondL1, 0.1 ether);
        assertEq(snapshot.resolutionBondL2, 0.5 ether);
        assertEq(snapshot.minMarketDuration, 1 hours);
        assertEq(snapshot.maxMarketDuration, 90 days);
        assertEq(snapshot.disputeWindow, 2 hours);
        assertEq(snapshot.creatorSettleGrace, 24 hours);
        assertEq(snapshot.openResolutionTimeout, 2 days);
        assertEq(snapshot.marketCreationBatchCap, 24);
        assertEq(snapshot.maxEscalation, 2);
        assertTrue(snapshot.permissionlessCreationEnabled);

        bytes32 questionId = keccak256("deploy-script-auto-ct");
        IConditionalTokens(deployment.conditionalTokens).prepareCondition(address(this), questionId, 2);
        assertTrue(_isGnosisConditionalTokensBytecode(deployment.conditionalTokens));
        vm.expectRevert(bytes("condition already prepared"));
        IConditionalTokens(deployment.conditionalTokens).prepareCondition(address(this), questionId, 2);
    }

    function test_DeployUsesExplicitConditionalTokensAddressWhenProvided() public {
        DeployScript deployScript = new DeployScript();
        MockConditionalTokens conditionalTokens = new MockConditionalTokens();
        MockUSDC collateralToken = new MockUSDC();
        MockEveToken eveToken = new MockEveToken();
        address protocolOwner = makeAddr("protocolOwner");
        address treasury = makeAddr("treasury");

        DeployScript.DeploymentConfig memory config = DeployScript.DeploymentConfig({
            owner: protocolOwner,
            conditionalTokens: address(conditionalTokens),
            conditionalTokensArtifactPath: "",
            collateralToken: address(collateralToken),
            eveToken: address(eveToken),
            eveTreasury: treasury,
            evesPositionManager: address(0),
            parimutuelShareToken: address(0),
            parlayTicketToken: address(0),
            parlayFeeRecipient: treasury,
            parlayUnderwritingFee: 3e18,
            parlaySeniorPoolFeeBps: 0,
            parlayFeeRecipientBps: 10_000,
            orderbookEntryFeeBps: 100,
            orderbookMakerFeeBps: 8_500,
            orderbookCreatorFeeBps: 400,
            orderbookProtocolFeeBps: 1_000,
            orderbookSeniorPoolFeeBps: 100,
            orderbookResolverFeeBps: 0,
            spotTradeFeeBps: 75,
            spotMakerFeeBps: 8_500,
            spotProtocolFeeBps: 1_400,
            spotSeniorPoolFeeBps: 100,
            spotResolverFeeBps: 0,
            comboTradeFeeBps: 80,
            comboMakerFeeBps: 8_500,
            comboCreatorFeeBps: 400,
            comboProtocolFeeBps: 1_000,
            comboSeniorPoolFeeBps: 100,
            comboResolverFeeBps: 0,
            parimutuelEntryFeeBps: 250,
            parimutuelCreatorFeeBps: 500,
            parimutuelProtocolFeeBps: 9_500,
            parimutuelSeniorPoolFeeBps: 0,
            parimutuelResolverFeeBps: 0,
            parimutuelMinEntry: 1e18,
            parimutuelCreationSeedAmount: 0,
            parimutuelEpochWindowCap: 30 days,
            marketCreationBatchCap: 24,
            marketCreationFee: 50e18,
            spotBookCreationFee: 250e18,
            comboMarketCreationFee: 250e18,
            marketCreationBond: 100e18,
            bondToken: address(eveToken),
            resolutionBondL1: 0.1 ether,
            resolutionBondL2: 0.5 ether,
            minMarketDuration: 1 hours,
            maxMarketDuration: 90 days,
            disputeWindow: 2 hours,
            creatorSettleGrace: 24 hours,
            openResolutionTimeout: 2 days,
            maxEscalation: 2,
            permissionlessCreationEnabled: true,
            delayedOrderProtectionDelayBlocks: 2,
            delayedOrderExecutionGraceBlocks: 20,
            delayedOrderRestingDurationMinutes: 180,
            delayedOrderProcessorFeeShareBps: 0,
            delayedOrderProcessingMode: uint8(LibEveMarket.ProcessingMode.ProtocolOnly),
            maxDelayedOrderRouteLength: 64,
            minDelayedOrderQuoteWad: 1e18,
            minDelayedOrderBaseWad: 1e18,
            mloDefaultFundingRatePerSecondWad: 0
        });

        DeployScript.Deployment memory deployment = deployScript.deploy(config, address(deployScript));

        assertEq(deployment.conditionalTokens, address(conditionalTokens));

        ConfigProbeFacet probe = new ConfigProbeFacet();
        _attachConfigProbe(deployment.diamond, protocolOwner, address(probe));

        ConfigProbeFacet.ConfigSnapshot memory snapshot = ConfigProbeFacet(deployment.diamond).getConfig();
        assertEq(snapshot.conditionalTokens, address(conditionalTokens));
    }

    function test_RevertWhen_DeployConfigHasInvalidParimutuelFeeSplit() public {
        DeployScript deployScript = new DeployScript();
        MockConditionalTokens conditionalTokens = new MockConditionalTokens();
        MockUSDC collateralToken = new MockUSDC();
        MockEveToken eveToken = new MockEveToken();
        address protocolOwner = makeAddr("protocolOwner");
        address treasury = makeAddr("treasury");

        DeployScript.DeploymentConfig memory config = DeployScript.DeploymentConfig({
            owner: protocolOwner,
            conditionalTokens: address(conditionalTokens),
            conditionalTokensArtifactPath: "",
            collateralToken: address(collateralToken),
            eveToken: address(eveToken),
            eveTreasury: treasury,
            evesPositionManager: address(0),
            parimutuelShareToken: address(0),
            parlayTicketToken: address(0),
            parlayFeeRecipient: treasury,
            parlayUnderwritingFee: 3e18,
            parlaySeniorPoolFeeBps: 0,
            parlayFeeRecipientBps: 10_000,
            orderbookEntryFeeBps: 100,
            orderbookMakerFeeBps: 8_500,
            orderbookCreatorFeeBps: 400,
            orderbookProtocolFeeBps: 1_000,
            orderbookSeniorPoolFeeBps: 100,
            orderbookResolverFeeBps: 0,
            spotTradeFeeBps: 75,
            spotMakerFeeBps: 8_500,
            spotProtocolFeeBps: 1_400,
            spotSeniorPoolFeeBps: 100,
            spotResolverFeeBps: 0,
            comboTradeFeeBps: 80,
            comboMakerFeeBps: 8_500,
            comboCreatorFeeBps: 400,
            comboProtocolFeeBps: 1_000,
            comboSeniorPoolFeeBps: 100,
            comboResolverFeeBps: 0,
            parimutuelEntryFeeBps: 250,
            parimutuelCreatorFeeBps: 8_000,
            parimutuelProtocolFeeBps: 3_000,
            parimutuelSeniorPoolFeeBps: 0,
            parimutuelResolverFeeBps: 0,
            parimutuelMinEntry: 1e18,
            parimutuelCreationSeedAmount: 0,
            parimutuelEpochWindowCap: 30 days,
            marketCreationBatchCap: 24,
            marketCreationFee: 50e18,
            spotBookCreationFee: 250e18,
            comboMarketCreationFee: 250e18,
            marketCreationBond: 100e18,
            bondToken: address(eveToken),
            resolutionBondL1: 0.1 ether,
            resolutionBondL2: 0.5 ether,
            minMarketDuration: 1 hours,
            maxMarketDuration: 90 days,
            disputeWindow: 2 hours,
            creatorSettleGrace: 24 hours,
            openResolutionTimeout: 2 days,
            maxEscalation: 2,
            permissionlessCreationEnabled: true,
            delayedOrderProtectionDelayBlocks: 2,
            delayedOrderExecutionGraceBlocks: 20,
            delayedOrderRestingDurationMinutes: 180,
            delayedOrderProcessorFeeShareBps: 0,
            delayedOrderProcessingMode: uint8(LibEveMarket.ProcessingMode.ProtocolOnly),
            maxDelayedOrderRouteLength: 64,
            minDelayedOrderQuoteWad: 1e18,
            minDelayedOrderBaseWad: 1e18,
            mloDefaultFundingRatePerSecondWad: 0
        });

        vm.expectRevert(bytes("invalid parimutuel fee split"));
        deployScript.deploy(config, address(deployScript));
    }

    function test_DeployFullStackDeploysAndAttachesStaticsDollarThroughSubmodule() public {
        DeployScript deployScript = new DeployScript();
        address temporaryOwner = address(deployScript);
        address protocolOwner = makeAddr("finalProtocolOwner");
        address treasury = makeAddr("treasury");

        DeployScript.DeploymentConfig memory marketConfig = DeployScript.DeploymentConfig({
            owner: protocolOwner,
            conditionalTokens: address(0),
            conditionalTokensArtifactPath: "",
            collateralToken: address(0),
            eveToken: address(0),
            eveTreasury: treasury,
            evesPositionManager: address(0),
            parimutuelShareToken: address(0),
            parlayTicketToken: address(0),
            parlayFeeRecipient: treasury,
            parlayUnderwritingFee: 3e18,
            parlaySeniorPoolFeeBps: 0,
            parlayFeeRecipientBps: 10_000,
            orderbookEntryFeeBps: 100,
            orderbookMakerFeeBps: 8_500,
            orderbookCreatorFeeBps: 400,
            orderbookProtocolFeeBps: 1_000,
            orderbookSeniorPoolFeeBps: 100,
            orderbookResolverFeeBps: 0,
            spotTradeFeeBps: 75,
            spotMakerFeeBps: 8_500,
            spotProtocolFeeBps: 1_400,
            spotSeniorPoolFeeBps: 100,
            spotResolverFeeBps: 0,
            comboTradeFeeBps: 80,
            comboMakerFeeBps: 8_500,
            comboCreatorFeeBps: 400,
            comboProtocolFeeBps: 1_000,
            comboSeniorPoolFeeBps: 100,
            comboResolverFeeBps: 0,
            parimutuelEntryFeeBps: 250,
            parimutuelCreatorFeeBps: 500,
            parimutuelProtocolFeeBps: 9_500,
            parimutuelSeniorPoolFeeBps: 0,
            parimutuelResolverFeeBps: 0,
            parimutuelMinEntry: 1e18,
            parimutuelCreationSeedAmount: 25e18,
            parimutuelEpochWindowCap: 30 days,
            marketCreationBatchCap: 24,
            marketCreationFee: 50e18,
            spotBookCreationFee: 250e18,
            comboMarketCreationFee: 250e18,
            marketCreationBond: 100e18,
            bondToken: address(0),
            resolutionBondL1: 0.1 ether,
            resolutionBondL2: 0.5 ether,
            minMarketDuration: 1 hours,
            maxMarketDuration: 90 days,
            disputeWindow: 2 hours,
            creatorSettleGrace: 24 hours,
            openResolutionTimeout: 2 days,
            maxEscalation: 2,
            permissionlessCreationEnabled: true,
            delayedOrderProtectionDelayBlocks: 2,
            delayedOrderExecutionGraceBlocks: 20,
            delayedOrderRestingDurationMinutes: 180,
            delayedOrderProcessorFeeShareBps: 0,
            delayedOrderProcessingMode: uint8(LibEveMarket.ProcessingMode.ProtocolOnly),
            maxDelayedOrderRouteLength: 64,
            minDelayedOrderQuoteWad: 1e18,
            minDelayedOrderBaseWad: 1e18,
            mloDefaultFundingRatePerSecondWad: 0
        });

        MockUSDC launchUsdc = new MockUSDC();
        ActiveStaticsDollar memory active = _deployActiveStaticsDollar(protocolOwner, launchUsdc);
        IStaticsDollarCore launchCore = IStaticsDollarCore(active.deployment.core);
        StaticsDollar launchStaticsDollar = StaticsDollar(active.deployment.staticsDollar);
        launchUsdc.mint(protocolOwner, 1_000_000e6);

        DeployScript.FullDeploymentConfig memory config = DeployScript.FullDeploymentConfig({
            market: marketConfig,
            usdcToken: address(launchUsdc),
            mloInsuranceFund: address(0),
            feeRecipient: address(0),
            initialEveMint: 1_000_000e18,
            initialMloInsuranceBootstrap: 1_000e6,
            mloFundingSeniorBps: 5_000,
            mloMaxCleanupBatch: 32,
            faucetOwner: protocolOwner,
            staticsDollar: DeployScript.StaticsDollarStackConfig({
                core: active.deployment.core,
                peggedProfileId: active.profileId,
                payoutUnit: 1e18,
                marketCreationFee: 2e18,
                parimutuelCreationSeedAmount: 3e18,
                parimutuelMinEntry: 1e18,
                parlayUnderwritingFee: 4e18,
                enableMarkets: true
            }),
            faucetUsdcEnabled: true,
            faucetEveEnabled: true,
            faucetUsdcClaimAmount: 1_000e6,
            faucetEveClaimAmount: 10_000e18,
            faucetUsdcFundAmount: 250_000e6,
            faucetEveFundAmount: 2_500_000e18
        });

        IStaticsDollarCoreTypes.PeggedMintPreview memory bootstrapPreview =
            launchCore.previewPeggedMint(active.profileId, config.initialMloInsuranceBootstrap * 1e12);
        launchUsdc.mint(temporaryOwner, config.faucetUsdcFundAmount + bootstrapPreview.totalCollateralIn);
        DeployScript.FullDeployment memory deployment = deployScript.deployFullStack(config, temporaryOwner);
        MarketFactoryTypes.MarketConfigView memory marketView =
            IMarketFactoryFacet(deployment.market.diamond).getMarketConfig();
        assertTrue(deployment.usdcToken != address(0));
        assertTrue(deployment.eveToken != address(0));
        assertTrue(deployment.mloInsuranceFund != address(0));
        assertTrue(deployment.faucet != address(0));
        assertTrue(deployment.market.parimutuelShareToken != address(0));

        assertEq(OwnershipFacet(deployment.market.diamond).owner(), protocolOwner);
        ISeniorCapitalFacet.SeniorCapitalState memory seniorState =
            ISeniorCapitalFacet(deployment.market.diamond).seniorCapitalState();
        assertEq(seniorState.asset, deployment.staticsDollar);
        assertEq(seniorState.pendingPrincipal, 0);
        assertEq(seniorState.totalPrincipal, 0);
        assertEq(MLOInsuranceFund(deployment.mloInsuranceFund).asset(), deployment.staticsDollar);
        assertEq(MLOInsuranceFund(deployment.mloInsuranceFund).owner(), protocolOwner);
        assertEq(MLOInsuranceFund(deployment.mloInsuranceFund).riskManager(), deployment.market.diamond);
        assertEq(MLOInsuranceFund(deployment.mloInsuranceFund).availableInsurance(), 1_000e18);
        assertEq(MLOInsuranceFund(deployment.mloInsuranceFund).totalSponsored(), 1_000e18);
        assertEq(deployment.staticsDollarCore, active.deployment.core);
        assertEq(deployment.staticsDollar, address(launchStaticsDollar));
        assertEq(deployment.staticsDiamond, active.deployment.diamond);

        assertEq(
            DiamondLoupeFacet(deployment.market.diamond)
                .facetAddress(ITradeRouter.buyWithCollateralWithPermit.selector),
            deployment.market.tradeRouterFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.market.diamond).facetAddress(ITradeRouter.mintAndBuyWithUSDC.selector),
            deployment.market.staticsDollarTradeRouterFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.market.diamond).facetAddress(ITradeRouter.mintAndBuyWithUSDCPermit.selector),
            deployment.market.staticsDollarTradeRouterFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.market.diamond).facetAddress(IParimutuelFacet.buyShares.selector),
            deployment.market.parimutuelFacet
        );

        assertEq(marketView.collateralToken, deployment.staticsDollar);
        assertEq(marketView.eveToken, deployment.eveToken);
        assertEq(marketView.staticsDollarCore, deployment.staticsDollarCore);
        assertEq(marketView.staticsDiamond, deployment.staticsDiamond);
        assertEq(marketView.usdcToken, deployment.usdcToken);
        assertEq(marketView.peggedProfileId, active.profileId);
        assertEq(marketView.parimutuelShareToken, deployment.market.parimutuelShareToken);
        assertEq(marketView.comboFeeConfig.tradeFeeBps, config.market.comboTradeFeeBps);
        assertEq(marketView.comboFeeConfig.makerFeeBps, config.market.comboMakerFeeBps);
        assertEq(marketView.comboFeeConfig.creatorFeeBps, config.market.comboCreatorFeeBps);
        assertEq(marketView.comboFeeConfig.protocolFeeBps, config.market.comboProtocolFeeBps);
        assertEq(marketView.comboFeeConfig.seniorPoolFeeBps, config.market.comboSeniorPoolFeeBps);
        assertEq(marketView.comboFeeConfig.resolverFeeBps, config.market.comboResolverFeeBps);
        assertEq(marketView.parimutuelFeeConfig.entryFeeBps, config.market.parimutuelEntryFeeBps);
        assertEq(marketView.parimutuelFeeConfig.creatorFeeBps, config.market.parimutuelCreatorFeeBps);
        assertEq(marketView.parimutuelFeeConfig.protocolFeeBps, config.market.parimutuelProtocolFeeBps);
        assertEq(marketView.parimutuelFeeConfig.seniorPoolFeeBps, config.market.parimutuelSeniorPoolFeeBps);
        assertEq(marketView.parimutuelFeeConfig.resolverFeeBps, config.market.parimutuelResolverFeeBps);
        assertEq(marketView.parimutuelMinEntry, config.market.parimutuelMinEntry);
        assertEq(marketView.parimutuelCreationSeedAmount, config.market.parimutuelCreationSeedAmount);
        assertEq(marketView.comboMarketCreationFee, config.market.comboMarketCreationFee);
        assertEq(marketView.marketCreationBatchCap, config.market.marketCreationBatchCap);
        assertEq(marketView.resolutionMode, uint8(LibEveMarket.ResolutionMode.CreatorAdminBootstrap));
        assertEq(marketView.bondToken, deployment.staticsDollar);

        assertEq(MockEveToken(deployment.eveToken).balanceOf(protocolOwner), config.initialEveMint);
        assertEq(MockEveToken(deployment.eveToken).delegates(protocolOwner), protocolOwner);

        _assertFaucetDeployment(deployment, config, protocolOwner);

        vm.startPrank(protocolOwner);
        IStaticsDollarCoreTypes.PeggedMintPreview memory preview =
            launchCore.previewPeggedMint(active.profileId, 1_000e18);
        launchUsdc.approve(deployment.staticsDollarCore, preview.totalCollateralIn);
        launchCore.mintPegged(active.profileId, 1_000e18, preview.totalCollateralIn, protocolOwner);
        launchStaticsDollar.approve(deployment.market.diamond, type(uint256).max);

        bytes32 marketId = IMarketFactoryFacet(deployment.market.diamond)
            .createMarket(
                "bootstrap regression market",
                "launch",
                "Bootstrap regression outcome resolved from the scripted deploy harness.",
                uint64(block.timestamp),
                uint64(block.timestamp) + 2 days,
                0,
                true
            );
        bytes32 bookId = IBookAdminFacet(deployment.market.diamond)
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                deployment.usdcToken,
                0,
                deployment.staticsDollar,
                4,
                keccak256("bootstrap-regression-book")
            );
        vm.stopPrank();

        assertTrue(marketId != bytes32(0));
        assertTrue(bookId != bytes32(0));
        _proveStaticsDollarMLOLaunchLifecycle(
            deployment, launchCore, launchUsdc, active.profileId, protocolOwner, marketId
        );
    }

    function _proveStaticsDollarMLOLaunchLifecycle(
        DeployScript.FullDeployment memory deployment,
        IStaticsDollarCore core,
        MockUSDC usdc,
        uint256 profileId,
        address maker,
        bytes32 marketId
    ) internal {
        address taker = makeAddr("staticsDollarMloTaker");
        IStaticsDollarCoreTypes.PeggedMintPreview memory takerPreview = core.previewPeggedMint(profileId, 100e18);
        usdc.mint(taker, takerPreview.totalCollateralIn);
        vm.startPrank(taker);
        usdc.approve(address(core), takerPreview.totalCollateralIn);
        core.mintPegged(profileId, 100e18, takerPreview.totalCollateralIn, taker);
        vm.stopPrank();

        IERC20 staticsDollar = IERC20(deployment.staticsDollar);
        vm.startPrank(maker);
        staticsDollar.approve(deployment.market.diamond, 500e18);
        ISeniorCapitalFacet(deployment.market.diamond).depositSeniorCapital(500e18);
        vm.warp(block.timestamp + 24 hours);
        ISeniorCapitalFacet(deployment.market.diamond).activateSeniorCapital();
        staticsDollar.approve(deployment.market.diamond, type(uint256).max);
        uint256 materializer = ICurveLifecycleFacet(deployment.market.diamond)
            .postBidCurve(marketId, true, 1e18, 500_000_000, 500_000_000, 120, 0, LibEveMarket.PositionTokenType.CTF);
        ICurveLifecycleFacet(deployment.market.diamond).cancelCurve(materializer);
        IMarginAccountFacet(deployment.market.diamond).depositMargin(300e18, maker);
        bytes32 riskDomain = IMarginAccountFacet(deployment.market.diamond).riskDomainForMarket(marketId);
        bytes32 bucketId = IMarginAccountFacet(deployment.market.diamond).allocateBucketMargin(riskDomain, 300e18, 1);

        bytes32 yesBookId = LibCLOBBook.marketBookId(marketId, true);
        MLOPredictionTypes.PostMLOCurveParams memory post = MLOPredictionTypes.PostMLOCurveParams({
            envelope: QuoteEnvelopeTypes.CreateQuoteEnvelopeParams({
                bucketId: bucketId,
                bookId: yesBookId,
                side: uint8(LibEveMarket.CurveSide.ASK),
                maxVolume: 100e18,
                minPrice: 400_000_000,
                maxPrice: 600_000_000,
                initialVolume: 50e18,
                initialStartPrice: 400_000_000,
                initialEndPrice: 400_000_000,
                expiresAt: uint64(block.timestamp + 2 hours)
            }),
            durationMinutes: 120
        });
        (, uint256 curveId) = IMLOPredictionAdapterFacet(deployment.market.diamond).postMLOCurve(post);
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(deployment.market.diamond).getCurveCommitment(curveId);
        vm.startPrank(taker);
        staticsDollar.approve(deployment.market.diamond, 25e18);
        MLOPredictionTypes.MLOAskFillResult memory fill = IMLOPredictionAdapterFacet(deployment.market.diamond)
            .fillMLOAskCurve(
                MLOPredictionTypes.FillMLOAskCurveParams({
                    curveId: curveId,
                    collateralIn: 25e18,
                    minSharesOut: 1,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
        vm.stopPrank();
        assertGt(fill.fill.sharesOut, 0);

        vm.startPrank(maker);
        IOBRResolutionFacet(deployment.market.diamond).settleMarketEarly(marketId, uint8(LibEveMarket.MarketOutcome.No));
        bytes memory finalizeCall = abi.encodeCall(
            IOBRResolutionFacet.adminFinalizeResolution, (marketId, uint8(LibEveMarket.MarketOutcome.No))
        );
        (, uint64 readyAt) = DiamondCutFacet(deployment.market.diamond).scheduleGovernanceOperation(finalizeCall);
        vm.warp(readyAt);
        IOBRResolutionFacet(deployment.market.diamond)
            .adminFinalizeResolution(marketId, uint8(LibEveMarket.MarketOutcome.No));
        vm.stopPrank();
        uint256[] memory curveIds = new uint256[](1);
        curveIds[0] = curveId;
        IMLOPredictionAdapterFacet(deployment.market.diamond).cleanupMLOCurves(bucketId, curveIds);
        IMLOPredictionAdapterFacet(deployment.market.diamond).settleMLOInventory(bucketId, marketId);

        ISeniorCapitalFacet.SeniorCapitalBucket memory accounting =
            ISeniorCapitalFacet(deployment.market.diamond).seniorCapitalBucket(bucketId);
        assertEq(accounting.activeExposure, 0);
        assertEq(accounting.reservedCapital, 0);

        ISeniorCapitalFacet.SeniorCapitalAccount memory seniorAccount =
            ISeniorCapitalFacet(deployment.market.diamond).seniorCapitalAccount(maker);
        uint256 makerBalanceBeforeExit = staticsDollar.balanceOf(maker);
        vm.prank(maker);
        ISeniorCapitalFacet(deployment.market.diamond).requestSeniorCapitalExit(seniorAccount.effectivePrincipal, maker);
        ISeniorCapitalFacet(deployment.market.diamond).processSeniorCapitalExits(1);

        uint256 exitClaim = ISeniorCapitalFacet(deployment.market.diamond).claimableSeniorCapitalExit(maker);
        assertEq(exitClaim, seniorAccount.effectivePrincipal + seniorAccount.pendingFees);
        vm.prank(maker);
        ISeniorCapitalFacet(deployment.market.diamond).claimSeniorCapitalExit(maker);

        assertEq(staticsDollar.balanceOf(maker) - makerBalanceBeforeExit, exitClaim);
        assertEq(ISeniorCapitalFacet(deployment.market.diamond).seniorCapitalState().totalPrincipal, 0);
    }

    function _attachConfigProbe(address diamond, address owner, address probeFacet) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ConfigProbeFacet.getConfig.selector;

        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](1);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: probeFacet, action: DiamondCutFacet.FacetCutAction.Add, functionSelectors: selectors
        });

        bytes memory callData = abi.encodeCall(DiamondCutFacet.diamondCut, (cuts, address(0), new bytes(0)));
        vm.prank(owner);
        (, uint64 readyAt) = DiamondCutFacet(diamond).scheduleGovernanceOperation(callData);
        vm.warp(readyAt);
        vm.prank(owner);
        DiamondCutFacet(diamond).diamondCut(cuts, address(0), new bytes(0));
    }

    function _assertDiamondFacetSizes(address diamond) internal view {
        address[] memory facets = DiamondLoupeFacet(diamond).facetAddresses();
        for (uint256 index; index < facets.length; ++index) {
            _assertMaxCodeSize(facets[index]);
        }
    }

    function _assertMaxCodeSize(address target) internal view {
        assertLe(target.code.length, EIP170_MAX_CODE_SIZE);
    }

    function _resolveMarketYes(address diamond, address protocolOwner, bytes32 marketId, uint64 disputeWindow)
        internal
    {
        vm.startPrank(protocolOwner);
        IOBRResolutionFacet(diamond).settleMarketEarly(marketId, uint8(LibEveMarket.MarketOutcome.Yes));
        bytes memory finalizeCall = abi.encodeCall(
            IOBRResolutionFacet.adminFinalizeResolution, (marketId, uint8(LibEveMarket.MarketOutcome.Yes))
        );
        (, uint64 readyAt) = DiamondCutFacet(diamond).scheduleGovernanceOperation(finalizeCall);
        uint256 disputeReadyAt = block.timestamp + disputeWindow + 1;
        vm.warp(readyAt > disputeReadyAt ? readyAt : disputeReadyAt);
        IOBRResolutionFacet(diamond).adminFinalizeResolution(marketId, uint8(LibEveMarket.MarketOutcome.Yes));
        vm.stopPrank();
    }

    function _isGnosisConditionalTokensBytecode(address conditionalTokens) internal view returns (bool) {
        string memory deployedArtifact =
            vm.readFile("out/conditional-tokens/ConditionalTokens.sol/ConditionalTokens.json");
        bytes memory expectedRuntime = vm.parseJsonBytes(deployedArtifact, ".deployedBytecode.object");
        return conditionalTokens.codehash == keccak256(expectedRuntime);
    }

    function _assertFaucetDeployment(
        DeployScript.FullDeployment memory deployment,
        DeployScript.FullDeploymentConfig memory config,
        address protocolOwner
    ) internal {
        assertEq(Faucet(deployment.faucet).owner(), protocolOwner);
        (uint256 usdcClaimAmount, bool usdcEnabled, bool usdcExists) =
            Faucet(deployment.faucet).getTokenConfig(deployment.usdcToken);
        (uint256 eveClaimAmount, bool eveEnabled, bool eveExists) =
            Faucet(deployment.faucet).getTokenConfig(deployment.eveToken);
        assertEq(usdcClaimAmount, config.faucetUsdcClaimAmount);
        assertTrue(usdcEnabled);
        assertTrue(usdcExists);
        assertEq(eveClaimAmount, config.faucetEveClaimAmount);
        assertTrue(eveEnabled);
        assertTrue(eveExists);
        assertEq(MockUSDC(deployment.usdcToken).balanceOf(deployment.faucet), config.faucetUsdcFundAmount);
        assertEq(MockEveToken(deployment.eveToken).balanceOf(deployment.faucet), config.faucetEveFundAmount);

        address claimer = makeAddr("claimer");
        vm.prank(claimer);
        Faucet(deployment.faucet).claim();
        assertEq(MockUSDC(deployment.usdcToken).balanceOf(claimer), config.faucetUsdcClaimAmount);
        assertEq(MockEveToken(deployment.eveToken).balanceOf(claimer), config.faucetEveClaimAmount);
    }
}
