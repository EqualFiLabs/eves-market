// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IMakerLendingRouter {
    error ZeroAmount();
    error ZeroAddress();
    error InvalidReceiver(address receiver);
    error InvalidMarketCollateral(address collateralToken, address expected);
    error NotLoanBorrower(address caller, address borrower);
    error NotOwner(address caller);
    error ResidualRouterBalance(address token, uint256 expectedBalance, uint256 actualBalance);
    error ResidualRouterPosition(uint256 positionId, uint256 actualBalance);

    event ERC20Rescued(address indexed token, address indexed receiver, uint256 amount);
    event ERC1155Rescued(address indexed token, uint256 indexed id, address indexed receiver, uint256 amount);

    event Onramped(
        address indexed caller,
        address indexed borrower,
        bytes32 indexed marketId,
        uint256 usdcAmount,
        uint256 netBorrowed,
        uint256 debtPrincipal,
        uint256 originationFee,
        uint256 loanId,
        uint128 positionSharesMinted,
        address receiver
    );
    event ParimutuelOnramped(
        address indexed caller,
        address indexed borrower,
        bytes32 indexed marketId,
        bool isYes,
        uint256 usdcAmount,
        uint256 netBorrowed,
        uint256 debtPrincipal,
        uint256 originationFee,
        uint256 loanId,
        uint128 sharesMinted,
        address receiver
    );
    event OfframpedToShares(
        address indexed caller,
        address indexed borrower,
        uint256 loanId,
        bytes32 indexed marketId,
        uint128 positionSharesMerged,
        uint256 mergeEveUSDCOut,
        uint256 debtRepaid,
        uint256 excessEveUSDC
    );
    event OfframpedToUSDC(
        address indexed caller,
        address indexed borrower,
        uint256 loanId,
        bytes32 indexed marketId,
        uint128 positionSharesMerged,
        uint256 mergeEveUSDCOut,
        uint256 debtRepaid,
        uint256 redeemedCollateralEveUSDC,
        uint256 usdcAmount,
        address receiver
    );

    function onramp(
        uint256 usdcAmount,
        uint256 borrowAmount,
        uint256 durationSeconds,
        bytes32 marketId,
        address receiver
    ) external returns (uint256 loanId, uint128 positionSharesMinted);

    function onrampParimutuel(
        uint256 usdcAmount,
        uint256 borrowAmount,
        uint256 durationSeconds,
        bytes32 marketId,
        bool isYes,
        uint128 minSharesOut,
        address receiver
    ) external returns (uint256 loanId, uint128 sharesMinted);

    function offrampToShares(uint256 loanId, bytes32 marketId, uint128 positionShareAmount) external;

    function offrampToUSDC(uint256 loanId, bytes32 marketId, uint128 positionShareAmount, address receiver)
        external
        returns (uint256 usdcOut);

    function previewOnramp(uint256 usdcAmount, uint256 borrowAmount, bytes32 marketId)
        external
        view
        returns (uint256 vaultSharesMinted, uint128 positionSharesMinted, uint256 originationFee, uint256 debtPrincipal);

    function previewParimutuelOnramp(uint256 usdcAmount, uint256 borrowAmount, bytes32 marketId)
        external
        view
        returns (
            uint256 vaultSharesMinted,
            uint128 sharesMinted,
            uint128 entryFee,
            uint256 originationFee,
            uint256 debtPrincipal
        );

    function previewOfframpToShares(uint256 loanId, bytes32 marketId, uint128 positionShareAmount)
        external
        view
        returns (uint256 mergeEveUSDCOut, uint256 repaymentAmount, uint256 excessEveUSDC);

    function previewOfframpToUSDC(uint256 loanId, bytes32 marketId, uint128 positionShareAmount)
        external
        view
        returns (uint256 mergeEveUSDCOut, uint256 redeemedCollateralEveUSDC, uint256 repaymentAmount, uint256 usdcOut);

    function rescueERC20(address token, address receiver, uint256 amount) external;

    function rescueERC1155(address token, uint256 id, address receiver, uint256 amount) external;
}
