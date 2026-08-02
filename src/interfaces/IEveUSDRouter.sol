// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IEveUSDRouter {
    error ZeroAddress();
    error ZeroAmount();
    error ContractExpected(address account);
    error InvalidPoolToken(address token, address expectedPool, address actualPool);
    error InvalidPoolAsset(address provided, address expected);
    error UnexpectedCollateralProfile(uint256 expectedProfileId, uint256 actualProfileId);
    error OutputBelowMinimum(uint256 actual, uint256 minimum);
    error SharesAboveMaximum(uint256 required, uint256 maximum);
    error ResidualRouterBalance(address token, uint256 expectedBalance, uint256 actualBalance);
    error ResidualRouterERC1155Balance(address token, uint256 id, uint256 expectedBalance, uint256 actualBalance);
    error ResidualRouterNativeBalance(uint256 expectedBalance, uint256 actualBalance);
    error UnexpectedETH(address sender);
    error NativeTransferFailed(address receiver, uint256 amount);

    event ETHDeposited(
        address indexed caller,
        address indexed eveUSDReceiver,
        address indexed shareReceiver,
        uint256 profileId,
        uint256 seriesId,
        uint256 ethAmount,
        uint256 eveUSDMinted,
        uint256 sharesMinted
    );
    event WETHDeposited(
        address indexed caller,
        address indexed eveUSDReceiver,
        address indexed shareReceiver,
        uint256 profileId,
        uint256 seriesId,
        uint256 wethAmount,
        uint256 eveUSDMinted,
        uint256 sharesMinted
    );
    event RecombinedToWETH(
        address indexed caller,
        address indexed receiver,
        uint256 indexed seriesId,
        uint256 eveUSDBurned,
        uint256 sharesBurned,
        uint256 wethOut
    );
    event RecombinedToETH(
        address indexed caller,
        address indexed receiver,
        uint256 indexed seriesId,
        uint256 eveUSDBurned,
        uint256 sharesBurned,
        uint256 ethOut
    );

    function depositETH(address eveUSDReceiver, address shareReceiver, uint256 minEveUSD, uint256 minShares)
        external
        payable
        returns (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted);

    function depositWETH(
        uint256 wethAmount,
        address eveUSDReceiver,
        address shareReceiver,
        uint256 minEveUSD,
        uint256 minShares
    ) external returns (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted);

    function recombineToWETH(
        uint256 seriesId,
        uint256 eveUSDAmount,
        uint256 maxSharesIn,
        address receiver,
        uint256 minWETHOut
    ) external returns (uint256 wethOut);

    function recombineToETH(
        uint256 seriesId,
        uint256 eveUSDAmount,
        uint256 maxSharesIn,
        address receiver,
        uint256 minETHOut
    ) external returns (uint256 ethOut);
}
