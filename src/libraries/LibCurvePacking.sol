// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library LibCurvePacking {
    error CurvePriceOutOfRange();
    error CurveDurationOutOfRange();
    error CurveTickPresetOutOfRange();
    error CurveProfileParamsOutOfRange();

    uint256 internal constant START_PRICE_OFFSET = 0;
    uint256 internal constant END_PRICE_OFFSET = 72;
    uint256 internal constant DURATION_OFFSET = 144;
    uint256 internal constant PROFILE_OFFSET = 164;
    uint256 internal constant RESERVED_OFFSET = 172;
    uint256 internal constant CURVE_TICK_PRESET_OFFSET = 172;
    uint256 internal constant CURVE_TICK_PRESET_BITS = 5;
    uint256 internal constant PROFILE_PARAM_OFFSET = 177;
    uint256 internal constant PROFILE_PARAM_BITS = 43;

    uint256 internal constant PRICE_MASK = (uint256(1) << 72) - 1;
    uint256 internal constant DURATION_MASK = (uint256(1) << 20) - 1;
    uint256 internal constant PROFILE_MASK = (uint256(1) << 8) - 1;
    uint256 internal constant RESERVED_MASK = (uint256(1) << 48) - 1;
    uint256 internal constant CURVE_TICK_PRESET_MASK = (uint256(1) << CURVE_TICK_PRESET_BITS) - 1;
    uint256 internal constant PROFILE_PARAM_MASK = (uint256(1) << PROFILE_PARAM_BITS) - 1;

    uint72 internal constant PRICE_SCALE = 1_000_000_000;
    uint72 internal constant MAX_PRICE = type(uint72).max;
    uint24 internal constant MAX_DURATION = uint24(DURATION_MASK);
    uint8 internal constant MAX_CURVE_TICK_PRESET_ID = 29;
    uint8 internal constant DEFAULT_TICK_PRESET_SENTINEL = type(uint8).max;

    struct CurveParams {
        uint72 startPrice;
        uint72 endPrice;
        uint24 durationMinutes;
        uint8 profileId;
        uint8 tickPresetId;
        bytes32 profileParams;
    }

    function pack(CurveParams memory params) internal pure returns (uint256 packed) {
        return pack(
            params.startPrice,
            params.endPrice,
            params.durationMinutes,
            params.profileId,
            params.tickPresetId,
            params.profileParams
        );
    }

    function pack(uint72 startPrice, uint72 endPrice, uint24 durationMinutes, uint8 profileId)
        internal
        pure
        returns (uint256 packed)
    {
        return pack(startPrice, endPrice, durationMinutes, profileId, 0, bytes32(0));
    }

    function pack(
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId,
        uint8 tickPresetId,
        bytes32 profileParams
    ) internal pure returns (uint256 packed) {
        if (startPrice > MAX_PRICE || endPrice > MAX_PRICE) {
            revert CurvePriceOutOfRange();
        }
        if (durationMinutes > MAX_DURATION) {
            revert CurveDurationOutOfRange();
        }
        if (tickPresetId > MAX_CURVE_TICK_PRESET_ID) {
            revert CurveTickPresetOutOfRange();
        }
        if (uint256(profileParams) > PROFILE_PARAM_MASK) {
            revert CurveProfileParamsOutOfRange();
        }

        packed = uint256(startPrice);
        packed |= uint256(endPrice) << END_PRICE_OFFSET;
        packed |= uint256(durationMinutes) << DURATION_OFFSET;
        packed |= uint256(profileId) << PROFILE_OFFSET;
        packed |= uint256(tickPresetId) << CURVE_TICK_PRESET_OFFSET;
        packed |= uint256(profileParams) << PROFILE_PARAM_OFFSET;
    }

    function unpack(uint256 packed) internal pure returns (CurveParams memory params) {
        params.startPrice = uint72((packed >> START_PRICE_OFFSET) & PRICE_MASK);
        params.endPrice = uint72((packed >> END_PRICE_OFFSET) & PRICE_MASK);
        params.durationMinutes = uint24((packed >> DURATION_OFFSET) & DURATION_MASK);
        params.profileId = uint8((packed >> PROFILE_OFFSET) & PROFILE_MASK);
        params.tickPresetId = extractTickPresetId(packed);
        params.profileParams = extractCustomProfileParams(packed);
    }

    function extractTickPresetId(uint256 packed) internal pure returns (uint8 tickPresetId) {
        tickPresetId = uint8((packed >> CURVE_TICK_PRESET_OFFSET) & CURVE_TICK_PRESET_MASK);
    }

    function extractCustomProfileParams(uint256 packed) internal pure returns (bytes32 profileParams) {
        profileParams = bytes32((packed >> PROFILE_PARAM_OFFSET) & PROFILE_PARAM_MASK);
    }
}
