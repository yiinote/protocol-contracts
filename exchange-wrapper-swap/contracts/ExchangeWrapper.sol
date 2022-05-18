// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "@rarible/exchange-v2/contracts/lib/LibTransfer.sol";
import "@rarible/exchange-v2/contracts/lib/BpLibrary.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@rarible/exchange-interfaces/contracts/IWyvernExchange.sol";
import "@rarible/exchange-interfaces/contracts/IExchangeV2.sol";
import "@rarible/royalties/contracts/LibPart.sol";

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);

    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);

    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);

//    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
//    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
//    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
//    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
//    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

contract ExchangeWrapperSwap is OwnableUpgradeable {
    using LibTransfer for address;
    using BpLibrary for uint;
    using SafeMathUpgradeable for uint;

    IUniswapV2Router02 swapRouter;
    IWyvernExchange public wyvernExchange;
    IExchangeV2 public exchangeV2;

    enum Markets {
        ExchangeV2,
        WyvernExchange
    }

    struct PurchaseDetails {
        Markets marketId;
        uint256 amount;
        bytes data;
        IERC20 tokenAddress;
    }

    function __ExchangeWrapperSwap_init(
        IWyvernExchange _wyvernExchange,
        IExchangeV2 _exchangeV2,
        IUniswapV2Router02 _swapRouter
    ) external initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        wyvernExchange = _wyvernExchange;
        exchangeV2 = _exchangeV2;
        swapRouter = _swapRouter;
    }

    function setWyvern(IWyvernExchange _wyvernExchange) external onlyOwner {
        wyvernExchange = _wyvernExchange;
    }

    function setExchange(IExchangeV2 _exchangeV2) external onlyOwner {
        exchangeV2 = _exchangeV2;
    }

    function singleSwapPurchase(PurchaseDetails memory purchaseDetails, uint[] memory fees) external payable {
        swap(purchaseDetails);
        purchase(purchaseDetails);

        feesTransfer(msg.value, fees);

        changeTransfer();
    }

    function swap(PurchaseDetails memory purchaseDetails) {
        if (purchaseDetails.tokenAddress == address(0)) {

        } else {

        }
    }

    function bulkPurchase(PurchaseDetails[] memory purchaseDetails, uint[] memory fees) external payable {
        for (uint i = 0; i < purchaseDetails.length; i++) {
            purchase(purchaseDetails[i]);
        }

        feesTransfer(msg.value, fees);

        changeTransfer();
    }

    function purchase(PurchaseDetails memory purchaseDetails) internal {
        uint paymentAmount = purchaseDetails.amount;
        if (purchaseDetails.marketId == Markets.WyvernExchange) {
            (bool success,) = address(wyvernExchange).call{value : paymentAmount}(purchaseDetails.data);
            require(success, "transfer failed");
        } else if (purchaseDetails.marketId == Markets.ExchangeV2) {
            (LibOrder.Order memory sellOrder, bytes memory sellOrderSignature) = abi.decode(purchaseDetails.data, (LibOrder.Order, bytes));
            matchExchangeV2(sellOrder, sellOrderSignature, paymentAmount);
        } else {
            revert("Unknown purchase details");
        }
    }

    function feesTransfer(uint amount, uint[] memory fees) internal {
        uint spent = amount.sub(address(this).balance);
        for (uint i = 0; i < fees.length; i++) {
            uint feeValue = spent.bp(uint(fees[i] >> 160));
            if (feeValue > 0) {
                LibTransfer.transferEth(address(fees[i]), feeValue);
            }
        }
    }

    function changeTransfer() internal {
        uint ethAmount = address(this).balance;
        if (ethAmount > 0) {
            address(_msgSender()).transferEth(ethAmount);
        }
    }

    /*Transfer by ExchangeV2 sellOrder is in input, buyOrder is generated inside method */
    function matchExchangeV2(
        LibOrder.Order memory sellOrder,
        bytes memory sellOrderSignature,
        uint amount
    ) internal {
        LibOrder.Order memory buyerOrder;
        buyerOrder.maker = address(this);
        buyerOrder.makeAsset = sellOrder.takeAsset;
        buyerOrder.takeAsset = sellOrder.makeAsset;

        /*set buyer in payout*/
        LibPart.Part[] memory payout = new LibPart.Part[](1);
        payout[0].account = _msgSender();
        payout[0].value = 10000;
        LibOrderDataV2.DataV2 memory data;
        data.payouts = payout;
        buyerOrder.data = abi.encode(data);
        buyerOrder.dataType = bytes4(keccak256("V2"));

        bytes memory buyOrderSignature; //empty signature is enough for buyerOrder

        IExchangeV2(exchangeV2).matchOrders{value : amount }(sellOrder, sellOrderSignature, buyerOrder, buyOrderSignature);
    }

    receive() external payable {}
}