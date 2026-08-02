// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {ISeniorCapitalFacet} from "../interfaces/ISeniorCapitalFacet.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibSeniorCapital} from "../libraries/LibSeniorCapital.sol";

contract SeniorCapitalFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function depositSeniorCapital(uint256 assets) external nonReentrant returns (uint256 credited) {
        if (assets == 0) revert ISeniorCapitalFacet.SeniorCapitalZeroAmount();
        address asset = _asset();
        IERC20 token = IERC20(asset);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), assets);
        credited = token.balanceOf(address(this)) - balanceBefore;
        if (credited != assets) revert ISeniorCapitalFacet.SeniorCapitalNonExactTransfer(assets, credited);

        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        LibSeniorCapital.Account storage account = state.accounts[msg.sender];
        uint256 eligibleAt = LibSeniorCapital.addPending(account, credited);
        state.pendingPrincipal += credited;
        emit ISeniorCapitalFacet.SeniorCapitalDeposited(msg.sender, credited, eligibleAt);
    }

    function withdrawPendingSeniorCapital(uint256 assets, address receiver)
        external
        nonReentrant
        returns (uint256 withdrawn)
    {
        if (assets == 0) revert ISeniorCapitalFacet.SeniorCapitalZeroAmount();
        if (receiver == address(0)) revert ISeniorCapitalFacet.SeniorCapitalZeroAddress();
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        LibSeniorCapital.Account storage account = state.accounts[msg.sender];
        if (assets > account.pendingPrincipal) {
            revert ISeniorCapitalFacet.SeniorCapitalInsufficientPending(assets, account.pendingPrincipal);
        }
        account.pendingPrincipal -= assets;
        state.pendingPrincipal -= assets;
        if (account.pendingPrincipal == 0) account.pendingSince = 0;
        _transferExact(receiver, assets);
        emit ISeniorCapitalFacet.SeniorCapitalPendingWithdrawn(msg.sender, receiver, assets);
        withdrawn = assets;
    }

    function activateSeniorCapital() external nonReentrant returns (uint256 principal, uint256 storedUnits) {
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        LibSeniorCapital.Account storage account = state.accounts[msg.sender];
        uint256 pending = account.pendingPrincipal;
        if (pending == 0) revert ISeniorCapitalFacet.SeniorCapitalZeroAmount();
        uint256 eligibleAt = uint256(account.pendingSince) + LibSeniorCapital.ACTIVATION_DELAY;
        if (block.timestamp < eligibleAt) revert ISeniorCapitalFacet.SeniorCapitalActivationPending(eligibleAt);
        if (account.activeExitId != 0) {
            revert ISeniorCapitalFacet.SeniorCapitalExitAlreadyPending(account.activeExitId);
        }

        if (account.stored != 0 && account.epoch != state.currentEpoch) {
            _claimAccount(state, account, msg.sender, msg.sender);
        }

        LibSeniorCapital.Epoch storage epoch = LibSeniorCapital.currentEpoch(state);
        storedUnits = Math.mulDiv(pending, LibSeniorCapital.RAY, epoch.scaleRay);
        if (storedUnits == 0) revert ISeniorCapitalFacet.SeniorCapitalAmountTooSmall(pending);
        principal = Math.mulDiv(storedUnits, epoch.scaleRay, LibSeniorCapital.RAY);
        if (principal == 0) revert ISeniorCapitalFacet.SeniorCapitalAmountTooSmall(pending);

        account.pendingPrincipal -= principal;
        state.pendingPrincipal -= principal;
        if (account.pendingPrincipal == 0) account.pendingSince = 0;
        LibSeniorCapital.activateStored(state, account, msg.sender, storedUnits, principal);
        emit ISeniorCapitalFacet.SeniorCapitalActivated(msg.sender, state.currentEpoch, principal, storedUnits);
    }

    function requestSeniorCapitalExit(uint256 principal, address receiver)
        external
        nonReentrant
        returns (uint256 exitId, uint256 principalQueued, uint256 storedUnits)
    {
        if (principal == 0) revert ISeniorCapitalFacet.SeniorCapitalZeroAmount();
        if (receiver == address(0)) revert ISeniorCapitalFacet.SeniorCapitalZeroAddress();
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        LibSeniorCapital.Account storage account = state.accounts[msg.sender];
        if (account.activeExitId != 0) {
            revert ISeniorCapitalFacet.SeniorCapitalExitAlreadyPending(account.activeExitId);
        }
        uint256 available = LibSeniorCapital.effectiveFor(state, account.epoch, account.stored);
        if (principal > available) {
            revert ISeniorCapitalFacet.SeniorCapitalInsufficientPrincipal(principal, available);
        }

        LibSeniorCapital.settleAccount(state, account);
        uint256 scale = state.epochs[state.currentEpoch].scaleRay;
        storedUnits = Math.mulDiv(principal, LibSeniorCapital.RAY, scale, Math.Rounding.Ceil);
        if (storedUnits > account.stored) storedUnits = account.stored;
        uint256 beforeExit = LibSeniorCapital.exitEffective(state);
        account.stored -= storedUnits;
        state.totalExitStored += storedUnits;
        principalQueued = LibSeniorCapital.exitEffective(state) - beforeExit;
        if (principalQueued == 0) revert ISeniorCapitalFacet.SeniorCapitalAmountTooSmall(principal);
        LibSeniorCapital.removeProviderStored(state, msg.sender, account.epoch, storedUnits);

        exitId = state.nextExitId == 0 ? 1 : state.nextExitId;
        state.nextExitId = exitId + 1;
        if (state.exitHead == 0) state.exitHead = exitId;
        state.exitTail = exitId;
        LibSeniorCapital.ExitRequest storage request = state.exits[exitId];
        request.owner = msg.sender;
        request.receiver = receiver;
        request.epoch = state.currentEpoch;
        request.stored = storedUnits;
        request.feeCheckpointRay = state.epochs[state.currentEpoch].fees.accPerStoredRay;
        if (account.stored == 0) {
            request.accruedFees = account.accruedFees;
            account.accruedFees = 0;
        }
        account.activeExitId = exitId;
        emit ISeniorCapitalFacet.SeniorCapitalExitRequested(
            exitId, msg.sender, receiver, state.currentEpoch, principalQueued, storedUnits
        );
    }

    function cancelSeniorCapitalExit(uint256 exitId) external nonReentrant returns (uint256 principalRestored) {
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        LibSeniorCapital.ExitRequest storage request = state.exits[exitId];
        if (request.owner == address(0) || request.stored == 0) {
            revert ISeniorCapitalFacet.SeniorCapitalExitNotFound(exitId);
        }
        if (request.owner != msg.sender) {
            revert ISeniorCapitalFacet.SeniorCapitalExitNotOwner(exitId, msg.sender);
        }
        LibSeniorCapital.settleExit(state, request);
        LibSeniorCapital.Account storage account = state.accounts[msg.sender];
        uint256 storedUnits = request.stored;

        if (request.epoch == state.currentEpoch) {
            principalRestored = LibSeniorCapital.restoreExit(state, account, request);
        } else {
            LibSeniorCapital.Epoch storage oldEpoch = state.epochs[request.epoch];
            LibSeniorCapital.removeOutstanding(oldEpoch, storedUnits);
            uint256 payout = LibSeniorCapital.feePayout(state, request.epoch, request.accruedFees, true);
            if (payout != 0) _transferExact(msg.sender, payout);
        }

        request.stored = 0;
        request.accruedFees = 0;
        request.cancelled = true;
        account.activeExitId = 0;
        emit ISeniorCapitalFacet.SeniorCapitalExitCancelled(exitId, msg.sender, principalRestored, storedUnits);
    }

    function processSeniorCapitalExits(uint256 maxRequests)
        external
        nonReentrant
        returns (uint256 inspected, uint256 completed, uint256 principalPaid, uint256 feesPaid)
    {
        if (maxRequests == 0 || maxRequests > LibSeniorCapital.MAX_EXIT_BATCH) {
            revert ISeniorCapitalFacet.SeniorCapitalInvalidExitBatch(maxRequests, LibSeniorCapital.MAX_EXIT_BATCH);
        }
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        uint256 exitId = state.exitHead;
        uint256 tail = state.exitTail;
        while (exitId != 0 && exitId <= tail && inspected < maxRequests) {
            ++inspected;
            uint256 processedExitId = exitId;
            LibSeniorCapital.ExitRequest storage request = state.exits[exitId];
            if (request.stored == 0) {
                ++exitId;
                state.exitHead = exitId > tail ? 0 : exitId;
                continue;
            }

            LibSeniorCapital.settleExit(state, request);
            uint256 principalOut;
            uint256 storedRemoved;
            bool stale = request.epoch != state.currentEpoch;
            if (stale) {
                storedRemoved = request.stored;
            } else {
                uint256 effectiveBefore = LibSeniorCapital.effectiveFor(state, request.epoch, request.stored);
                uint256 liquid = state.unreservedPrincipal;
                if (liquid != 0) {
                    if (liquid >= effectiveBefore) {
                        storedRemoved = request.stored;
                        principalOut = effectiveBefore;
                    } else {
                        uint256 scale = state.epochs[state.currentEpoch].scaleRay;
                        storedRemoved = Math.mulDiv(liquid, LibSeniorCapital.RAY, scale);
                        if (storedRemoved > request.stored) storedRemoved = request.stored;
                        if (storedRemoved != 0) {
                            uint256 effectiveAfter =
                                LibSeniorCapital.effectiveFor(state, request.epoch, request.stored - storedRemoved);
                            principalOut = effectiveBefore - effectiveAfter;
                        }
                    }
                }
            }

            bool cleared = storedRemoved == request.stored && storedRemoved != 0;
            if (storedRemoved != 0) {
                request.stored -= storedRemoved;
                LibSeniorCapital.removeOutstanding(state.epochs[request.epoch], storedRemoved);
                if (!stale) {
                    state.totalStored -= storedRemoved;
                    state.totalExitStored -= storedRemoved;
                    state.totalPrincipal -= principalOut;
                    state.unreservedPrincipal -= principalOut;
                }
            }

            uint256 feeOut = LibSeniorCapital.feePayout(state, request.epoch, request.accruedFees, cleared);
            request.accruedFees = 0;
            if (cleared) {
                state.accounts[request.owner].activeExitId = 0;
                ++completed;
                ++exitId;
                state.exitHead = exitId > tail ? 0 : exitId;
            }
            if (!stale && cleared && state.totalStored == 0) LibSeniorCapital.rollEmptyEpoch(state);

            principalPaid += principalOut;
            feesPaid += feeOut;
            uint256 claimable = principalOut + feeOut;
            LibSeniorCapital.accrueExitClaim(state, request.owner, claimable);
            emit ISeniorCapitalFacet.SeniorCapitalExitProcessed(
                processedExitId, request.owner, request.receiver, principalOut, feeOut, request.stored
            );
            if (claimable != 0) {
                emit ISeniorCapitalFacet.SeniorCapitalExitClaimAccrued(request.owner, processedExitId, claimable);
            }
            if (!cleared) break;
        }
    }

    function claimSeniorCapitalExit(address receiver) external nonReentrant returns (uint256 assets) {
        if (receiver == address(0)) revert ISeniorCapitalFacet.SeniorCapitalZeroAddress();
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        assets = LibSeniorCapital.takeExitClaim(state, msg.sender);
        _transferExact(receiver, assets);
        emit ISeniorCapitalFacet.SeniorCapitalExitClaimed(msg.sender, receiver, assets);
    }

    function claimSeniorCapitalFees(address receiver) external nonReentrant returns (uint256 amount) {
        if (receiver == address(0)) revert ISeniorCapitalFacet.SeniorCapitalZeroAddress();
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        LibSeniorCapital.Account storage account = state.accounts[msg.sender];
        amount = _claimAccount(state, account, msg.sender, receiver);
    }

    function donateSeniorCapitalFees(uint256 assets) external nonReentrant returns (uint256 credited) {
        if (assets == 0) revert ISeniorCapitalFacet.SeniorCapitalZeroAmount();
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        if (state.totalStored == 0) revert ISeniorCapitalFacet.SeniorCapitalNoEligiblePrincipal();
        IERC20 token = IERC20(_asset());
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), assets);
        credited = token.balanceOf(address(this)) - balanceBefore;
        if (credited != assets) revert ISeniorCapitalFacet.SeniorCapitalNonExactTransfer(assets, credited);
        LibSeniorCapital.accrueFees(
            state, credited, LibSeniorCapital.FEE_SOURCE_DONATION, bytes32(uint256(uint160(msg.sender)))
        );
        emit ISeniorCapitalFacet.SeniorCapitalFeesDonated(msg.sender, credited);
    }

    function _claimAccount(
        LibSeniorCapital.Storage storage state,
        LibSeniorCapital.Account storage account,
        address owner,
        address receiver
    ) private returns (uint256 amount) {
        LibSeniorCapital.settleAccount(state, account);
        bool stale = account.stored != 0 && account.epoch != state.currentEpoch;
        if (stale) {
            uint256 stored = account.stored;
            account.stored = 0;
            LibSeniorCapital.removeOutstanding(state.epochs[account.epoch], stored);
            LibSeniorCapital.removeProviderStored(state, owner, account.epoch, stored);
        }
        amount = LibSeniorCapital.feePayout(state, account.epoch, account.accruedFees, stale);
        account.accruedFees = 0;
        if (amount != 0) _transferExact(receiver, amount);
        if (owner != address(0) && amount != 0) {
            emit ISeniorCapitalFacet.SeniorCapitalFeesClaimed(owner, receiver, amount);
        }
    }

    function _asset() private view returns (address asset) {
        asset = LibEveMarket.store().marginAsset;
        if (asset == address(0)) revert ISeniorCapitalFacet.SeniorCapitalAssetNotSet();
    }

    function _transferExact(address receiver, uint256 assets) private {
        IERC20 token = IERC20(_asset());
        uint256 receiverBefore = token.balanceOf(receiver);
        token.safeTransfer(receiver, assets);
        uint256 receiverAfter = token.balanceOf(receiver);
        uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (received != assets) revert ISeniorCapitalFacet.SeniorCapitalNonExactTransfer(assets, received);
    }
}
