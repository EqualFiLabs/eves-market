// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";

interface ICurveLifecycleFacet {
    function postCurve(
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId,
        LibEveMarket.PositionTokenType positionTokenType
    ) external returns (uint256 curveId);

    function postBidCurve(
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId,
        LibEveMarket.PositionTokenType positionTokenType
    ) external returns (uint256 curveId);

    function postCurvesBatch(
        bytes32 marketId,
        LibEveMarket.PositionTokenType positionTokenType,
        CurveCLOBTypes.CurveCreationParams[] calldata params
    ) external returns (uint256[] memory curveIds);

    function postBidCurvesBatch(
        bytes32 marketId,
        LibEveMarket.PositionTokenType positionTokenType,
        CurveCLOBTypes.CurveCreationParams[] calldata params
    ) external returns (uint256[] memory curveIds);

    function postCurvesMultiMarket(CurveCLOBTypes.MarketCurvePostParams[] calldata batches)
        external
        returns (uint256[][] memory curveIds);

    function postBidCurvesMultiMarket(CurveCLOBTypes.MarketCurvePostParams[] calldata batches)
        external
        returns (uint256[][] memory curveIds);

    function updateCurve(uint256 curveId, uint256 newPacked, uint32 expectedGeneration) external;
    function updateCurvesBatch(CurveCLOBTypes.CurveUpdateParams[] calldata params) external;
    function updateCurveFromNow(uint256 curveId, uint256 newPacked, uint32 expectedGeneration) external;
    function updateCurvesFromNowBatch(CurveCLOBTypes.CurveUpdateParams[] calldata params) external;
    function topUpCurvesBatch(bytes32 marketId, CurveCLOBTypes.CurveTopUpParams[] calldata params) external;
    function topUpCurvesMultiMarket(CurveCLOBTypes.MarketCurveTopUpParams[] calldata batches) external;

    function splitAndTopUpCurvesBatch(bytes32 marketId, CurveCLOBTypes.CurveTopUpParams[] calldata params)
        external
        returns (uint128 sharesMinted);

    function splitAndTopUpCurvesMultiMarket(CurveCLOBTypes.MarketCurveTopUpParams[] calldata batches)
        external
        returns (uint128[] memory sharesMinted);

    function cancelCurve(uint256 curveId) external;
    function cancelCurvesBatch(uint256[] calldata curveIds) external;
}
