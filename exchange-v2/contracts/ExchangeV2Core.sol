// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "@rarible/libraries/contracts/LibFill.sol";
import "@rarible/libraries/contracts/LibOrderData.sol";
import "@rarible/libraries/contracts/LibDeal.sol";
import "@rarible/libraries/contracts/LibFeeSide.sol";
import "@rarible/libraries/contracts/BpLibrary.sol";

import "./OrderValidator.sol";
import "./AssetMatcher.sol";

import "@rarible/transfer-manager/contracts/TransferExecutor.sol";
import "@rarible/exchange-interfaces/contracts/ITransferManager.sol";

abstract contract ExchangeV2Core is Initializable, OwnableUpgradeable, AssetMatcher, TransferExecutor, OrderValidator, ITransferManager {
    using SafeMathUpgradeable for uint;
    using LibTransfer for address;

    uint256 private constant UINT256_MAX = 2 ** 256 - 1;

    //state of the orders
    mapping(bytes32 => uint) public fills;

    //events
    event Cancel(bytes32 hash);
    event Match(uint newLeftFill, uint newRightFill);

    function cancel(LibOrder.Order memory order) external {
        require(_msgSender() == order.maker, "not a maker");
        require(order.salt != 0, "0 salt can't be used");
        bytes32 orderKeyHash = LibOrder.hashKey(order);
        fills[orderKeyHash] = UINT256_MAX;
        emit Cancel(orderKeyHash);
    }

    struct DealBuy {
        address seller;
        address token;
        bytes4 assetType;
        uint tokenId;
        uint tokenAmount;
        uint price;
        uint salt;
        bytes signature;
    }
    struct DealAcceptBid {
        address buyer;
        address tokenPayment;
        address tokenNft;
        bytes4 assetType;
        uint tokenId;
        uint amount;
        uint price;
        uint salt;
        bytes signature;
    }

    function directBuy(
        DealBuy memory deal,
        uint[4] memory ordersData
    ) external payable {
        bytes memory nftAssetData = abi.encode(deal.token, deal.tokenId);
        LibAsset.Asset memory nft = LibAsset.Asset(LibAsset.AssetType(deal.assetType, nftAssetData), deal.tokenAmount);
        LibAsset.Asset memory payment = LibAsset.Asset(LibAsset.AssetType(LibAsset.ETH_ASSET_CLASS, ""), deal.price);
        bytes memory dataV2BytesNft;
        bytes memory dataV2BytesPayment;
        (dataV2BytesNft, dataV2BytesPayment) = formDataOrders(ordersData);

        LibOrder.Order memory orderLeft = LibOrder.Order(deal.seller, nft, address(0), payment, deal.salt, 0, 0, LibOrderDataV2.V2, dataV2BytesNft);
        LibOrder.Order memory orderRight = LibOrder.Order(msg.sender, payment, address(0), nft, 0, 0, 0, LibOrderDataV2.V2, dataV2BytesPayment);
        validateFull(orderLeft, deal.signature);
        validateFull(orderRight, "");
        if (orderLeft.taker != address(0)) {
            require(orderRight.maker == orderLeft.taker, "leftOrder.taker verification failed");
        }
        if (orderRight.taker != address(0)) {
            require(orderRight.taker == orderLeft.maker, "rightOrder.taker verification failed");
        }
        matchAndTransfer(orderLeft, orderRight);
    }

    function directAcceptBid(
        DealAcceptBid memory deal,
        uint[4] memory ordersData
    ) external payable {
        bytes memory paymentAssetData = abi.encode(deal.tokenPayment);
        bytes memory nftAssetData = abi.encode(deal.tokenNft, deal.tokenId);
        LibAsset.Asset memory payment = LibAsset.Asset(LibAsset.AssetType(LibAsset.ERC20_ASSET_CLASS, paymentAssetData), deal.price);
        LibAsset.Asset memory nft = LibAsset.Asset(LibAsset.AssetType(deal.assetType, nftAssetData), deal.amount);
        bytes memory dataV2BytesNft;
        bytes memory dataV2BytesPayment;
        (dataV2BytesNft, dataV2BytesPayment) = formDataOrders(ordersData);

        LibOrder.Order memory orderLeft = LibOrder.Order(deal.buyer, payment, address(0), nft, deal.salt, 0, 0, LibOrderDataV2.V2, dataV2BytesPayment);
        LibOrder.Order memory orderRight = LibOrder.Order(msg.sender, nft, address(0), payment, 0, 0, 0, LibOrderDataV2.V2, dataV2BytesNft);
        validateFull(orderLeft, deal.signature);
        validateFull(orderRight, "");
        if (orderLeft.taker != address(0)) {
            require(orderRight.maker == orderLeft.taker, "leftOrder.taker verification failed");
        }
        if (orderRight.taker != address(0)) {
            require(orderRight.taker == orderLeft.maker, "rightOrder.taker verification failed");
        }
        matchAndTransfer(orderLeft, orderRight);
    }

    function formDataOrders(uint[4] memory ordersData) internal returns (bytes memory dataV2BytesNft, bytes memory dataV2BytesPayment) {
        LibPart.Part[] memory sellPayout = new LibPart.Part[](1);
        sellPayout[0].account = address(ordersData[0]);
        sellPayout[0].value = uint96(ordersData[0] >> 160);

        LibPart.Part[] memory buyPayout = new LibPart.Part[](1);
        buyPayout[0].account = address(ordersData[1]);
        buyPayout[0].value = uint96(ordersData[1] >> 160);

        LibPart.Part[] memory sellOrigin = new LibPart.Part[](1);
        sellOrigin[0].account = address(ordersData[2]);
        sellOrigin[0].value = uint96(ordersData[2] >> 160);

        LibPart.Part[] memory buyOrigin = new LibPart.Part[](1);
        buyOrigin[0].account = address(ordersData[3]);
        buyOrigin[0].value = uint96(ordersData[3] >> 160);

        LibOrderDataV2.DataV2 memory dataNft = LibOrderDataV2.DataV2(sellPayout, sellOrigin, true);
        LibOrderDataV2.DataV2 memory dataPayment = LibOrderDataV2.DataV2(buyPayout, buyOrigin, true);
        dataV2BytesNft = abi.encode(dataNft);
        dataV2BytesPayment = abi.encode(dataPayment);
    }

    function matchOrders(
        LibOrder.Order memory orderLeft,
        bytes memory signatureLeft,
        LibOrder.Order memory orderRight,
        bytes memory signatureRight
    ) external payable {
        validateFull(orderLeft, signatureLeft);
        validateFull(orderRight, signatureRight);
        if (orderLeft.taker != address(0)) {
            require(orderRight.maker == orderLeft.taker, "leftOrder.taker verification failed");
        }
        if (orderRight.taker != address(0)) {
            require(orderRight.taker == orderLeft.maker, "rightOrder.taker verification failed");
        }
        matchAndTransfer(orderLeft, orderRight);
    }

    function matchAndTransfer(LibOrder.Order memory orderLeft, LibOrder.Order memory orderRight) internal {
        (LibAsset.AssetType memory makeMatch, LibAsset.AssetType memory takeMatch) = matchAssets(orderLeft, orderRight);
        bytes32 leftOrderKeyHash = LibOrder.hashKey(orderLeft);
        bytes32 rightOrderKeyHash = LibOrder.hashKey(orderRight);

        LibOrderDataV2.DataV2 memory leftOrderData = LibOrderData.parse(orderLeft);
        LibOrderDataV2.DataV2 memory rightOrderData = LibOrderData.parse(orderRight);

        LibFill.FillResult memory newFill = getFillSetNew(
            orderLeft, 
            orderRight, 
            leftOrderKeyHash, 
            rightOrderKeyHash, 
            leftOrderData.isMakeFill, 
            rightOrderData.isMakeFill
        );

        (uint totalMakeValue, uint totalTakeValue) = doTransfers(
            LibDeal.DealSide(
                LibAsset.Asset( 
                    makeMatch,
                    newFill.leftValue
                ),
                leftOrderData.payouts,
                leftOrderData.originFees,
                proxies[orderLeft.makeAsset.assetType.assetClass],
                orderLeft.maker
            ), 
            LibDeal.DealSide(
                LibAsset.Asset( 
                    takeMatch,
                    newFill.rightValue
                ),
                rightOrderData.payouts,
                rightOrderData.originFees,
                proxies[orderRight.makeAsset.assetType.assetClass],
                orderRight.maker
            ), 
            LibFeeSide.getFeeSide(makeMatch.assetClass, takeMatch.assetClass), 
            getProtocolFee()
        );
        if (makeMatch.assetClass == LibAsset.ETH_ASSET_CLASS) {
            require(takeMatch.assetClass != LibAsset.ETH_ASSET_CLASS);
            require(msg.value >= totalMakeValue, "not enough eth");
            if (msg.value > totalMakeValue) {
                address(msg.sender).transferEth(msg.value.sub(totalMakeValue));
            }
        } else if (takeMatch.assetClass == LibAsset.ETH_ASSET_CLASS) {
            require(msg.value >= totalTakeValue, "not enough eth");
            if (msg.value > totalTakeValue) {
                address(msg.sender).transferEth(msg.value.sub(totalTakeValue));
            }
        }
        emit Match(newFill.rightValue, newFill.leftValue);
    }

    function getFillSetNew(
        LibOrder.Order memory orderLeft,
        LibOrder.Order memory orderRight,
        bytes32 leftOrderKeyHash,
        bytes32 rightOrderKeyHash,
        bool leftMakeFill,
        bool rightMakeFill
    ) internal returns (LibFill.FillResult memory) {
        uint leftOrderFill = getOrderFill(orderLeft.salt, leftOrderKeyHash);
        uint rightOrderFill = getOrderFill(orderRight.salt, rightOrderKeyHash);
        LibFill.FillResult memory newFill = LibFill.fillOrder(orderLeft, orderRight, leftOrderFill, rightOrderFill, leftMakeFill, rightMakeFill);

        require(newFill.rightValue > 0 && newFill.leftValue > 0, "nothing to fill");

        if (orderLeft.salt != 0) {
            if (leftMakeFill) {
                fills[leftOrderKeyHash] = leftOrderFill.add(newFill.leftValue);
            } else {
                fills[leftOrderKeyHash] = leftOrderFill.add(newFill.rightValue);
            }
        }

        if (orderRight.salt != 0) {
            if (rightMakeFill) {
                fills[rightOrderKeyHash] = rightOrderFill.add(newFill.rightValue);
            } else {
                fills[rightOrderKeyHash] = rightOrderFill.add(newFill.leftValue);
            }
        }
        return newFill;
    }

    function getOrderFill(uint salt, bytes32 hash) internal view returns (uint fill) {
        if (salt == 0) {
            fill = 0;
        } else {
            fill = fills[hash];
        }
    }

    function matchAssets(LibOrder.Order memory orderLeft, LibOrder.Order memory orderRight) internal view returns (LibAsset.AssetType memory makeMatch, LibAsset.AssetType memory takeMatch) {
        makeMatch = matchAssets(orderLeft.makeAsset.assetType, orderRight.takeAsset.assetType);
        require(makeMatch.assetClass != 0, "assets don't match");
        takeMatch = matchAssets(orderLeft.takeAsset.assetType, orderRight.makeAsset.assetType);
        require(takeMatch.assetClass != 0, "assets don't match");
    }

    function validateFull(LibOrder.Order memory order, bytes memory signature) internal view {
        LibOrder.validate(order);
        validate(order, signature);
    }

    function getProtocolFee() internal virtual view returns(uint);

    uint256[47] private __gap;
}
