// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {EveUSDC} from "../../src/EveUSDC.sol";
import {Faucet} from "../../src/Faucet.sol";
import {MakerLendingRouter} from "../../src/MakerLendingRouter.sol";
import {SEveUSDCLending} from "../../src/SEveUSDCLending.sol";
import {SEveUSDCVault} from "../../src/SEveUSDCVault.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {IComboCoreFacet} from "../../src/interfaces/IComboCoreFacet.sol";
import {IComboSettlementFacet} from "../../src/interfaces/IComboSettlementFacet.sol";
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
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IParlayFacet} from "../../src/interfaces/IParlayFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {IResolverRegistryFacet} from "../../src/interfaces/IResolverRegistryFacet.sol";
import {IComboMarketFacet} from "../../src/interfaces/IComboMarketFacet.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {IVaultRouter} from "../../src/interfaces/IVaultRouter.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {IConditionalTokens} from "../../src/interfaces/IConditionalTokens.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {EveIdentity} from "../../src/tokens/EveIdentity.sol";
import {EveETH} from "../../src/tokens/EveETH.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";
import {NativePositionTypes} from "../../src/types/NativePositionTypes.sol";

import {DeployScript} from "../../script/Deploy.s.sol";

import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";
import {MockEveToken} from "../helpers/MockEveToken.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract ConfigProbeFacet {
    struct ConfigSnapshot {
        address conditionalTokens;
        address collateralToken;
        address eveToken;
        address eveTreasury;
        address stakingVault;
        address parimutuelShareToken;
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
        snapshot.stakingVault = config.stakingVault;
        snapshot.parimutuelShareToken = config.parimutuelShareToken;
        snapshot.orderbookEntryFeeBps = config.orderbookFeeConfig.entryFeeBps;
        snapshot.orderbookMakerFeeBps = config.orderbookFeeConfig.makerFeeBps;
        snapshot.orderbookCreatorFeeBps = config.orderbookFeeConfig.creatorFeeBps;
        snapshot.orderbookProtocolFeeBps = config.orderbookFeeConfig.protocolFeeBps;
        snapshot.orderbookVaultFeeBps = config.orderbookFeeConfig.vaultFeeBps;
        snapshot.spotTradeFeeBps = config.spotFeeConfig.tradeFeeBps;
        snapshot.spotMakerFeeBps = config.spotFeeConfig.makerFeeBps;
        snapshot.spotProtocolFeeBps = config.spotFeeConfig.protocolFeeBps;
        snapshot.spotVaultFeeBps = config.spotFeeConfig.vaultFeeBps;
        snapshot.comboTradeFeeBps = config.comboFeeConfig.tradeFeeBps;
        snapshot.comboMakerFeeBps = config.comboFeeConfig.makerFeeBps;
        snapshot.comboCreatorFeeBps = config.comboFeeConfig.creatorFeeBps;
        snapshot.comboProtocolFeeBps = config.comboFeeConfig.protocolFeeBps;
        snapshot.comboVaultFeeBps = config.comboFeeConfig.vaultFeeBps;
        snapshot.parimutuelEntryFeeBps = config.parimutuelFeeConfig.entryFeeBps;
        snapshot.parimutuelCreatorFeeBps = config.parimutuelFeeConfig.creatorFeeBps;
        snapshot.parimutuelProtocolFeeBps = config.parimutuelFeeConfig.protocolFeeBps;
        snapshot.parimutuelVaultFeeBps = config.parimutuelFeeConfig.vaultFeeBps;
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

contract DeployScriptTest is Test {
    struct NativeComboLifecycle {
        bytes32 marketA;
        bytes32 marketB;
        bytes32 comboYesBookId;
        uint256 comboYes;
        uint256 curveId;
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
            stakingVault: address(0),
            evesPositionManager: address(0),
            parimutuelShareToken: address(0),
            parlayTicketToken: address(0),
            parlayFeeRecipient: treasury,
            parlayUnderwritingFee: 3e18,
            parlayVaultFeeBps: 0,
            parlayFeeRecipientBps: 10_000,
            orderbookEntryFeeBps: 100,
            orderbookMakerFeeBps: 8_500,
            orderbookCreatorFeeBps: 400,
            orderbookProtocolFeeBps: 1_000,
            orderbookVaultFeeBps: 100,
            spotTradeFeeBps: 75,
            spotMakerFeeBps: 8_500,
            spotProtocolFeeBps: 1_400,
            spotVaultFeeBps: 100,
            comboTradeFeeBps: 80,
            comboMakerFeeBps: 8_500,
            comboCreatorFeeBps: 400,
            comboProtocolFeeBps: 1_000,
            comboVaultFeeBps: 100,
            parimutuelEntryFeeBps: 250,
            parimutuelCreatorFeeBps: 500,
            parimutuelProtocolFeeBps: 9_500,
            parimutuelVaultFeeBps: 0,
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
            delayedOrderProcessingMode: uint8(LibEveMarket.ProcessingMode.ProtocolOnly)
        });

        DeployScript.Deployment memory deployment = deployScript.deploy(config, address(deployScript));

        deployScript.verifyDeployment(deployment);

        assertEq(OwnershipFacet(deployment.diamond).owner(), protocolOwner);
        assertEq(DiamondLoupeFacet(deployment.diamond).facetAddresses().length, 39);
        assertTrue(deployment.parimutuelShareToken != address(0));
        assertTrue(deployment.parlayTicketToken != address(0));
        assertTrue(deployment.eveIdentity != address(0));
        assertEq(ParimutuelShareToken(deployment.parimutuelShareToken).diamond(), deployment.diamond);
        assertEq(EveIdentity(deployment.eveIdentity).diamond(), deployment.diamond);
        assertEq(IResolverRegistryFacet(deployment.diamond).resolverPoolCapacity(), 50);
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
        assertEq(snapshot.stakingVault, address(0));
        assertEq(snapshot.parimutuelShareToken, deployment.parimutuelShareToken);
        assertEq(snapshot.orderbookEntryFeeBps, 100);
        assertEq(snapshot.orderbookVaultFeeBps, 100);
        assertEq(snapshot.spotTradeFeeBps, 75);
        assertEq(snapshot.spotMakerFeeBps, 8_500);
        assertEq(snapshot.spotProtocolFeeBps, 1_400);
        assertEq(snapshot.spotVaultFeeBps, 100);
        assertEq(snapshot.comboTradeFeeBps, 80);
        assertEq(snapshot.comboMakerFeeBps, 8_500);
        assertEq(snapshot.comboCreatorFeeBps, 400);
        assertEq(snapshot.comboProtocolFeeBps, 1_000);
        assertEq(snapshot.comboVaultFeeBps, 100);
        assertEq(snapshot.parimutuelEntryFeeBps, 250);
        assertEq(snapshot.parimutuelCreatorFeeBps, 500);
        assertEq(snapshot.parimutuelProtocolFeeBps, 9_500);
        assertEq(snapshot.parimutuelVaultFeeBps, 0);
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
            stakingVault: address(0),
            evesPositionManager: address(0),
            parimutuelShareToken: address(0),
            parlayTicketToken: address(0),
            parlayFeeRecipient: treasury,
            parlayUnderwritingFee: 3e18,
            parlayVaultFeeBps: 0,
            parlayFeeRecipientBps: 10_000,
            orderbookEntryFeeBps: 100,
            orderbookMakerFeeBps: 8_500,
            orderbookCreatorFeeBps: 400,
            orderbookProtocolFeeBps: 1_000,
            orderbookVaultFeeBps: 100,
            spotTradeFeeBps: 75,
            spotMakerFeeBps: 8_500,
            spotProtocolFeeBps: 1_400,
            spotVaultFeeBps: 100,
            comboTradeFeeBps: 80,
            comboMakerFeeBps: 8_500,
            comboCreatorFeeBps: 400,
            comboProtocolFeeBps: 1_000,
            comboVaultFeeBps: 100,
            parimutuelEntryFeeBps: 250,
            parimutuelCreatorFeeBps: 500,
            parimutuelProtocolFeeBps: 9_500,
            parimutuelVaultFeeBps: 0,
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
            delayedOrderProcessingMode: uint8(LibEveMarket.ProcessingMode.ProtocolOnly)
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
            stakingVault: address(0),
            evesPositionManager: address(0),
            parimutuelShareToken: address(0),
            parlayTicketToken: address(0),
            parlayFeeRecipient: treasury,
            parlayUnderwritingFee: 3e18,
            parlayVaultFeeBps: 0,
            parlayFeeRecipientBps: 10_000,
            orderbookEntryFeeBps: 100,
            orderbookMakerFeeBps: 8_500,
            orderbookCreatorFeeBps: 400,
            orderbookProtocolFeeBps: 1_000,
            orderbookVaultFeeBps: 100,
            spotTradeFeeBps: 75,
            spotMakerFeeBps: 8_500,
            spotProtocolFeeBps: 1_400,
            spotVaultFeeBps: 100,
            comboTradeFeeBps: 80,
            comboMakerFeeBps: 8_500,
            comboCreatorFeeBps: 400,
            comboProtocolFeeBps: 1_000,
            comboVaultFeeBps: 100,
            parimutuelEntryFeeBps: 250,
            parimutuelCreatorFeeBps: 8_000,
            parimutuelProtocolFeeBps: 3_000,
            parimutuelVaultFeeBps: 0,
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
            delayedOrderProcessingMode: uint8(LibEveMarket.ProcessingMode.ProtocolOnly)
        });

        vm.expectRevert(bytes("invalid parimutuel fee split"));
        deployScript.deploy(config, address(deployScript));
    }

    function test_DeployFullStackAutoDeploysVaultLendingAndDiamondRouters() public {
        DeployScript deployScript = new DeployScript();
        address protocolOwner = address(deployScript);
        address treasury = makeAddr("treasury");

        DeployScript.DeploymentConfig memory marketConfig = DeployScript.DeploymentConfig({
            owner: protocolOwner,
            conditionalTokens: address(0),
            conditionalTokensArtifactPath: "",
            collateralToken: address(0),
            eveToken: address(0),
            eveTreasury: treasury,
            stakingVault: address(0),
            evesPositionManager: address(0),
            parimutuelShareToken: address(0),
            parlayTicketToken: address(0),
            parlayFeeRecipient: treasury,
            parlayUnderwritingFee: 3e18,
            parlayVaultFeeBps: 0,
            parlayFeeRecipientBps: 10_000,
            orderbookEntryFeeBps: 100,
            orderbookMakerFeeBps: 8_500,
            orderbookCreatorFeeBps: 400,
            orderbookProtocolFeeBps: 1_000,
            orderbookVaultFeeBps: 100,
            spotTradeFeeBps: 75,
            spotMakerFeeBps: 8_500,
            spotProtocolFeeBps: 1_400,
            spotVaultFeeBps: 100,
            comboTradeFeeBps: 80,
            comboMakerFeeBps: 8_500,
            comboCreatorFeeBps: 400,
            comboProtocolFeeBps: 1_000,
            comboVaultFeeBps: 100,
            parimutuelEntryFeeBps: 250,
            parimutuelCreatorFeeBps: 500,
            parimutuelProtocolFeeBps: 9_500,
            parimutuelVaultFeeBps: 0,
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
            delayedOrderProcessingMode: uint8(LibEveMarket.ProcessingMode.ProtocolOnly)
        });

        DeployScript.FullDeploymentConfig memory config = DeployScript.FullDeploymentConfig({
            market: marketConfig,
            usdcToken: address(0),
            eveUSDC: address(0),
            seveUsdcLending: address(0),
            makerLendingRouter: address(0),
            eveUsdcOnramp: address(0),
            eveUsdcOfframp: address(0),
            feeRecipient: address(0),
            aumFeeBps: 200,
            lendingMaxLtvBps: 9_500,
            lendingOriginationFeeBps: 100,
            lendingExtensionFeeBps: 50,
            lendingFeeRecipientBps: 3_000,
            lendingMinDurationSeconds: 1 days,
            lendingMaxDurationSeconds: 400 days,
            lendingGracePeriodSeconds: 1 days,
            initialUsdcMint: 5_000_000e6,
            initialEveMint: 1_000_000e18,
            initialVaultBootstrap: 0,
            faucetOwner: protocolOwner,
            wethToken: address(0),
            eveETH: address(0),
            eveEthPayoutUnit: 0.0005 ether,
            eveEthMarketCreationFee: 0.01 ether,
            eveEthParimutuelCreationSeedAmount: 0.0003 ether,
            eveEthParimutuelMinEntry: 0.0001 ether,
            eveEthParlayUnderwritingFee: 0.0002 ether,
            faucetUsdcEnabled: true,
            faucetEveEnabled: true,
            deployMockWeth: true,
            deployEveETH: true,
            enableEveEthMarkets: true,
            faucetUsdcClaimAmount: 1_000e6,
            faucetEveClaimAmount: 10_000e18,
            faucetUsdcFundAmount: 250_000e6,
            faucetEveFundAmount: 2_500_000e18
        });

        DeployScript.FullDeployment memory deployment = deployScript.deployFullStack(config, protocolOwner);
        MarketFactoryTypes.MarketConfigView memory marketView =
            IMarketFactoryFacet(deployment.market.diamond).getMarketConfig();
        uint256 bootstrapUsdc = 1e6;
        uint256 bootstrapAssets = 1e18;

        assertTrue(deployment.usdcToken != address(0));
        assertTrue(deployment.eveToken != address(0));
        assertTrue(deployment.eveUSDC != address(0));
        assertTrue(deployment.seveUsdcVault != address(0));
        assertTrue(deployment.seveUsdcLending != address(0));
        assertTrue(deployment.makerLendingRouter != address(0));
        assertTrue(deployment.faucet != address(0));
        assertTrue(deployment.wethToken != address(0));
        assertTrue(deployment.eveETH != address(0));
        assertTrue(deployment.market.parimutuelShareToken != address(0));

        assertEq(OwnershipFacet(deployment.market.diamond).owner(), protocolOwner);
        assertEq(EveUSDC(deployment.eveUSDC).usdc(), deployment.usdcToken);
        assertEq(EveUSDC(deployment.eveUSDC).onramp(), protocolOwner);
        assertEq(EveUSDC(deployment.eveUSDC).offramp(), protocolOwner);

        assertEq(SEveUSDCVault(deployment.seveUsdcVault).asset(), deployment.eveUSDC);
        assertEq(SEveUSDCVault(deployment.seveUsdcVault).owner(), protocolOwner);
        assertEq(SEveUSDCVault(deployment.seveUsdcVault).feeRecipient(), treasury);
        assertEq(SEveUSDCVault(deployment.seveUsdcVault).lendingContract(), deployment.seveUsdcLending);
        assertEq(SEveUSDCVault(deployment.seveUsdcVault).totalSupply(), bootstrapAssets);
        assertEq(SEveUSDCVault(deployment.seveUsdcVault).balanceOf(protocolOwner), bootstrapAssets);

        assertEq(address(SEveUSDCLending(deployment.seveUsdcLending).vault()), deployment.seveUsdcVault);
        assertEq(address(SEveUSDCLending(deployment.seveUsdcLending).eveUSDC()), deployment.eveUSDC);
        assertTrue(SEveUSDCLending(deployment.seveUsdcLending).approvedRouters(deployment.makerLendingRouter));
        assertEq(CanonicalWETH9(payable(deployment.wethToken)).symbol(), "WETH");
        assertEq(EveETH(deployment.eveETH).weth(), deployment.wethToken);

        assertEq(
            DiamondLoupeFacet(deployment.market.diamond).facetAddress(IVaultRouter.wrapAndDeposit.selector),
            deployment.market.vaultRouterFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.market.diamond).facetAddress(IVaultRouter.redeemAndUnwrap.selector),
            deployment.market.vaultRouterFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.market.diamond).facetAddress(IVaultRouter.wrapETHToEveETH.selector),
            deployment.market.vaultRouterFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.market.diamond).facetAddress(ITradeRouter.buyWithEveUSDC.selector),
            deployment.market.tradeRouterFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.market.diamond).facetAddress(ITradeRouter.buyWithUSDC.selector),
            deployment.market.tradeRouterFacet
        );
        assertEq(
            DiamondLoupeFacet(deployment.market.diamond).facetAddress(IParimutuelFacet.buyShares.selector),
            deployment.market.parimutuelFacet
        );

        assertEq(MakerLendingRouter(deployment.makerLendingRouter).usdc(), deployment.usdcToken);
        assertEq(MakerLendingRouter(deployment.makerLendingRouter).eveUSDC(), deployment.eveUSDC);
        assertEq(MakerLendingRouter(deployment.makerLendingRouter).vault(), deployment.seveUsdcVault);
        assertEq(MakerLendingRouter(deployment.makerLendingRouter).lending(), deployment.seveUsdcLending);
        assertEq(MakerLendingRouter(deployment.makerLendingRouter).diamond(), deployment.market.diamond);
        assertEq(
            MakerLendingRouter(deployment.makerLendingRouter).defaultConditionalTokens(),
            deployment.market.conditionalTokens
        );

        assertEq(marketView.collateralToken, deployment.eveUSDC);
        assertEq(marketView.eveToken, deployment.eveToken);
        assertEq(marketView.stakingVault, deployment.seveUsdcVault);
        assertEq(marketView.parimutuelShareToken, deployment.market.parimutuelShareToken);
        assertEq(marketView.comboFeeConfig.tradeFeeBps, config.market.comboTradeFeeBps);
        assertEq(marketView.comboFeeConfig.makerFeeBps, config.market.comboMakerFeeBps);
        assertEq(marketView.comboFeeConfig.creatorFeeBps, config.market.comboCreatorFeeBps);
        assertEq(marketView.comboFeeConfig.protocolFeeBps, config.market.comboProtocolFeeBps);
        assertEq(marketView.comboFeeConfig.vaultFeeBps, config.market.comboVaultFeeBps);
        assertEq(marketView.parimutuelFeeConfig.entryFeeBps, config.market.parimutuelEntryFeeBps);
        assertEq(marketView.parimutuelFeeConfig.creatorFeeBps, config.market.parimutuelCreatorFeeBps);
        assertEq(marketView.parimutuelFeeConfig.protocolFeeBps, config.market.parimutuelProtocolFeeBps);
        assertEq(marketView.parimutuelFeeConfig.vaultFeeBps, config.market.parimutuelVaultFeeBps);
        assertEq(marketView.parimutuelMinEntry, config.market.parimutuelMinEntry);
        assertEq(marketView.parimutuelCreationSeedAmount, config.market.parimutuelCreationSeedAmount);
        assertEq(marketView.comboMarketCreationFee, config.market.comboMarketCreationFee);
        assertEq(marketView.marketCreationBatchCap, config.market.marketCreationBatchCap);
        MarketFactoryTypes.CollateralProfileView memory eveEthProfile =
            IMarketFactoryFacet(deployment.market.diamond).getCollateralProfile(1);
        assertEq(eveEthProfile.collateralToken, deployment.eveETH);
        assertEq(eveEthProfile.wrapperToken, deployment.wethToken);
        assertEq(eveEthProfile.payoutUnit, config.eveEthPayoutUnit);
        assertEq(eveEthProfile.marketCreationFee, config.eveEthMarketCreationFee);
        assertTrue(eveEthProfile.enabled);
        (uint128 eveEthParimutuelSeed, uint128 eveEthParimutuelMinEntry) =
            IMarketFactoryFacet(deployment.market.diamond).getCollateralProfileParimutuelConfig(1);
        assertEq(eveEthParimutuelSeed, config.eveEthParimutuelCreationSeedAmount);
        assertEq(eveEthParimutuelMinEntry, config.eveEthParimutuelMinEntry);
        assertEq(
            IMarketFactoryFacet(deployment.market.diamond).getCollateralProfileParlayUnderwritingFee(1),
            config.eveEthParlayUnderwritingFee
        );

        assertEq(MockUSDC(deployment.usdcToken).balanceOf(protocolOwner), config.initialUsdcMint - bootstrapUsdc);
        assertEq(MockEveToken(deployment.eveToken).balanceOf(protocolOwner), config.initialEveMint);
        assertEq(MockEveToken(deployment.eveToken).delegates(protocolOwner), protocolOwner);

        _assertFaucetDeployment(deployment, config, protocolOwner);

        vm.startPrank(protocolOwner);
        MockUSDC(deployment.usdcToken).approve(deployment.eveUSDC, 1_000e6);
        EveUSDC(deployment.eveUSDC).wrap(1_000e6, protocolOwner);
        EveUSDC(deployment.eveUSDC).approve(deployment.market.diamond, type(uint256).max);

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
                deployment.eveUSDC,
                4,
                keccak256("bootstrap-regression-book")
            );
        vm.stopPrank();

        assertTrue(marketId != bytes32(0));
        assertTrue(bookId != bytes32(0));

        _assertNativeComboLifecycle(deployment, protocolOwner, config.market.disputeWindow);
    }

    function _attachConfigProbe(address diamond, address owner, address probeFacet) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ConfigProbeFacet.getConfig.selector;

        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](1);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: probeFacet, action: DiamondCutFacet.FacetCutAction.Add, functionSelectors: selectors
        });

        vm.prank(owner);
        DiamondCutFacet(diamond).diamondCut(cuts, address(0), new bytes(0));
    }

    function _assertNativeComboLifecycle(
        DeployScript.FullDeployment memory deployment,
        address protocolOwner,
        uint64 disputeWindow
    ) internal {
        address taker = makeAddr("nativeComboTaker");
        uint128 amount = 10e18;
        NativeComboLifecycle memory lifecycle = _postNativeComboAsk(deployment, protocolOwner, amount);

        _fillNativeComboAsk(deployment, taker, lifecycle, amount);
        _resolveMarketYes(deployment.market.diamond, protocolOwner, lifecycle.marketA, disputeWindow);

        vm.prank(taker);
        NativePositionTypes.CompressionResult memory compression =
            IComboSettlementFacet(deployment.market.diamond).compressCombo(lifecycle.comboYes, amount, taker);
        assertEq(compression.positionAmount, amount);
        assertEq(compression.collateralOut, 0);
        assertTrue(compression.newPositionId != 0);

        _resolveMarketYes(deployment.market.diamond, protocolOwner, lifecycle.marketB, disputeWindow);

        uint256 takerBalanceBefore = EveUSDC(deployment.eveUSDC).balanceOf(taker);
        vm.prank(taker);
        uint128 collateralOut =
            IComboSettlementFacet(deployment.market.diamond).redeemCombo(compression.newPositionId, amount, taker);

        assertEq(collateralOut, amount);
        assertEq(EveUSDC(deployment.eveUSDC).balanceOf(taker), takerBalanceBefore + amount);
    }

    function _postNativeComboAsk(DeployScript.FullDeployment memory deployment, address protocolOwner, uint128 amount)
        internal
        returns (NativeComboLifecycle memory lifecycle)
    {
        address diamond = deployment.market.diamond;
        address maker = makeAddr("nativeComboMaker");
        uint72 halfPrice = 500_000_000;

        vm.startPrank(protocolOwner);
        lifecycle.marketA = IMarketFactoryFacet(diamond)
            .createMarket(
                "Will the native combo launch regression leg A resolve yes?",
                "launch",
                "Test-only launch regression source A.",
                uint64(block.timestamp),
                uint64(block.timestamp) + 2 days,
                0,
                true
            );
        lifecycle.marketB = IMarketFactoryFacet(diamond)
            .createMarket(
                "Will the native combo launch regression leg B resolve yes?",
                "launch",
                "Test-only launch regression source B.",
                uint64(block.timestamp),
                uint64(block.timestamp) + 3 days,
                0,
                true
            );

        vm.stopPrank();

        MockUSDC(deployment.usdcToken).mint(maker, 900e6);
        vm.startPrank(maker);
        MockUSDC(deployment.usdcToken).approve(deployment.eveUSDC, 900e6);
        EveUSDC(deployment.eveUSDC).wrap(900e6, maker);
        EveUSDC(deployment.eveUSDC).approve(diamond, type(uint256).max);
        bytes32[] memory marketIds = new bytes32[](2);
        marketIds[0] = lifecycle.marketA;
        marketIds[1] = lifecycle.marketB;
        bool[] memory yesLegs = new bool[](2);
        yesLegs[0] = true;
        yesLegs[1] = true;
        IComboMarketFacet.ComboMarketPreparation memory preparation =
            IComboMarketFacet(diamond).createComboMarket(marketIds, yesLegs);
        IComboCoreFacet(diamond).splitCombo(preparation.conditionId, amount, maker, maker);
        lifecycle.comboYes = preparation.yesPositionId;
        lifecycle.comboYesBookId = preparation.yesBookId;
        assertEq(
            IComboMarketFacet(diamond).getComboBook(deployment.market.evesPositionManager, preparation.noPositionId),
            preparation.noBookId
        );

        EvesPositionManager(deployment.market.evesPositionManager).setApprovalForAll(diamond, true);
        lifecycle.curveId = IBookOrderFacet(diamond)
            .postBookCurve(lifecycle.comboYesBookId, LibEveMarket.CurveSide.ASK, amount, halfPrice, halfPrice, 30, 0, 0);
        vm.stopPrank();
    }

    function _fillNativeComboAsk(
        DeployScript.FullDeployment memory deployment,
        address taker,
        NativeComboLifecycle memory lifecycle,
        uint128 amount
    ) internal {
        address diamond = deployment.market.diamond;

        MockUSDC(deployment.usdcToken).mint(taker, 25e6);
        vm.startPrank(taker);
        MockUSDC(deployment.usdcToken).approve(deployment.eveUSDC, 25e6);
        EveUSDC(deployment.eveUSDC).wrap(25e6, taker);
        EveUSDC(deployment.eveUSDC).approve(diamond, type(uint256).max);

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(diamond).getCurveCommitment(lifecycle.curveId);
        uint256[] memory curveIds = new uint256[](1);
        curveIds[0] = lifecycle.curveId;
        uint32[] memory generations = new uint32[](1);
        generations[0] = generation;
        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = commitment;

        IBookTradeFacet(diamond)
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: lifecycle.comboYesBookId,
                    maxQuoteIn: 6e18,
                    minBaseOut: amount,
                    maxAveragePrice: 505_000_000,
                    curveIds: curveIds,
                    expectedGenerations: generations,
                    expectedCommitments: commitments,
                    payer: taker,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(
            EvesPositionManager(deployment.market.evesPositionManager).balanceOf(taker, lifecycle.comboYes), amount
        );
    }

    function _resolveMarketYes(address diamond, address protocolOwner, bytes32 marketId, uint64 disputeWindow)
        internal
    {
        vm.startPrank(protocolOwner);
        IOBRResolutionFacet(diamond).settleMarketEarly(marketId, uint8(LibEveMarket.MarketOutcome.Yes));
        vm.warp(block.timestamp + disputeWindow + 1);
        IOBRResolutionFacet(diamond).finalizeResolution(marketId);
        vm.stopPrank();
    }

    function _isGnosisConditionalTokensBytecode(address conditionalTokens) internal view returns (bool) {
        string memory deployedArtifact =
            vm.readFile("../../conditional-tokens-contracts/out/ConditionalTokens.sol/ConditionalTokens.json");
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
