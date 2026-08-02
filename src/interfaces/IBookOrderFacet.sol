// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";

interface IBookOrderFacet {
    function postBookCurve(
        bytes32 bookId,
        LibEveMarket.CurveSide curveSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId,
        uint8 tickPresetId
    ) external returns (uint256 curveId);

    function postBookCurvesBatch(
        bytes32 bookId,
        LibEveMarket.CurveSide curveSide,
        CurveCLOBTypes.CurveCreationParams[] calldata params
    ) external returns (uint256[] memory curveIds);

    function topUpBookCurvesBatch(bytes32 bookId, CurveCLOBTypes.CurveTopUpParams[] calldata params) external;

    function reactivateBookCurve(
        bytes32 bookId,
        uint256 curveId,
        uint128 newVolume,
        uint256 newPacked,
        uint32 expectedGeneration
    ) external;
}
