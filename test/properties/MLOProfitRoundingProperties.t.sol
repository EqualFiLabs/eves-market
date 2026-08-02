// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {LibMLOProfitShare} from "../../src/libraries/LibMLOProfitShare.sol";

contract MLOProfitRoundingHarness {
    function cumulativeEntitlements(uint256 profit, uint256 seniorBps, uint256 insuranceBps)
        external
        pure
        returns (uint256 senior, uint256 insurance)
    {
        return LibMLOProfitShare.cumulativeEntitlements(profit, seniorBps, insuranceBps);
    }
}

contract MLOProfitRoundingPropertiesTest is Test {
    MLOProfitRoundingHarness internal harness;

    function setUp() public {
        harness = new MLOProfitRoundingHarness();
    }

    function testFuzz_IncrementalRecipientsNeverExceedRecognizedProfit(
        uint128 priorRaw,
        uint128 incrementRaw,
        uint256 seniorRaw,
        uint256 insuranceRaw
    ) public view {
        uint256 seniorBps = bound(seniorRaw, 0, 10_000);
        uint256 insuranceBps = bound(insuranceRaw, 0, 10_000 - seniorBps);
        uint256 prior = uint256(priorRaw);
        uint256 increment = uint256(incrementRaw);
        (uint256 seniorBefore, uint256 insuranceBefore) = harness.cumulativeEntitlements(prior, seniorBps, insuranceBps);
        (uint256 seniorAfter, uint256 insuranceAfter) =
            harness.cumulativeEntitlements(prior + increment, seniorBps, insuranceBps);

        uint256 incrementalRecipients = seniorAfter - seniorBefore + insuranceAfter - insuranceBefore;
        assertLe(incrementalRecipients, increment);
        assertEq(seniorAfter + insuranceAfter, ((prior + increment) * (seniorBps + insuranceBps)) / 10_000);
        assertGe(seniorAfter, seniorBefore);
        assertGe(insuranceAfter, insuranceBefore);
    }

    function test_SmallProfitGridConservesEveryWholePercentSplitFamily() public view {
        for (uint256 seniorPercent; seniorPercent <= 100; ++seniorPercent) {
            for (uint256 insurancePercent; insurancePercent <= 100 - seniorPercent; ++insurancePercent) {
                uint256 seniorBps = seniorPercent * 100;
                uint256 insuranceBps = insurancePercent * 100;
                uint256 priorSenior;
                uint256 priorInsurance;
                for (uint256 profit = 1; profit <= 32; ++profit) {
                    (uint256 senior, uint256 insurance) =
                        harness.cumulativeEntitlements(profit, seniorBps, insuranceBps);
                    assertLe((senior - priorSenior) + (insurance - priorInsurance), 1);
                    assertEq(senior + insurance, (profit * (seniorBps + insuranceBps)) / 10_000);
                    priorSenior = senior;
                    priorInsurance = insurance;
                }
            }
        }
    }
}
