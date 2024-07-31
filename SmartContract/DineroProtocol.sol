// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.9.6/utils/Strings.sol";
import "@openzeppelin/contracts@4.9.6/access/Ownable.sol";
import "@openzeppelin/contracts@4.9.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.9.6/utils/Math/Math.sol";




contract DOrderContract is Ownable {
    address public oracleAddress;

    uint256 public platformFee = 2;     //platform fee 

    address public tradeToken;


    struct DOrderModel {
        address buyer;
        address seller;
        uint256 price;
        uint256 balance;

        //1. waiting for buyer  2. waiting for seller  3.both are payed 4.cancel with buyer  5.cancel with seller 6.appeal with buyer 7. appeal with seller 8.cancel 100.finish
        int status;  
    }

    mapping(string => DOrderModel) public orderList;


    event UpdateOrderStatus(
        DOrderModel order
    );


    modifier canCreateOrder(string memory orderId,uint256 totalPrice,int cmd)  {
        // require(tradeToken != address(0), "Invalid tradeToken address");

        IERC20 paymentToken = IERC20(tradeToken);
        require(totalPrice > 0, "Invalid totalPrice");
        uint256 amount = totalPrice;
        require(
            paymentToken.allowance(msg.sender, address(this)) >= amount,
                "Insufficient token allowance"
        );
        require(
            paymentToken.balanceOf(msg.sender) >= amount,
            "Insufficient token balance"
        );

        _;
    }

    //set trade token
    function setTradeToken(address tokenAddress) external onlyOwner {
        tradeToken = tokenAddress;
    }

    //set Oracle Address 
    function setOracleAddress(address _address) external onlyOwner {
        oracleAddress = _address;
    }

    //set Oracle platformFee 
    function setPlatformFee(uint256  _platformFee) external onlyOwner {
        platformFee = _platformFee;
    }

 

    /* createOrder
    orderId : order id, Global Unique ID  
    totalPrice:  total price for this order
    cmd : 1. is sell  2.is buy
    */
    function createOrder(string memory orderId,uint256 totalPrice,int cmd)  
    external canCreateOrder(orderId, totalPrice,cmd)
    {
        if (totalPrice > 0) {
            //transfer token to this contract
            IERC20 paymentToken = IERC20(tradeToken);
            paymentToken.transferFrom(msg.sender, address(this), totalPrice);

            //set this order's info.
            _createOrderInfo(orderId,totalPrice,cmd);

            emit UpdateOrderStatus(
                orderList[orderId]
            );
        }
    }

    /*  payOrder
    orderId : order id, Global Unique ID  
    totalPrice:  total price for this order
    cmd : 1. is sell  2.is buy
    */
    function payOrder(string memory orderId,uint256 totalPrice,int cmd) public{
        if (totalPrice > 0) {
            //transfer token to this contract
            IERC20 paymentToken = IERC20(tradeToken);
            paymentToken.transferFrom(msg.sender, address(this), totalPrice);

            //set this order's info.
            _payOrderInfo(orderId,totalPrice,cmd);

            emit UpdateOrderStatus(
                orderList[orderId]
            );
        }
    }


    /*  cancelOrder
     *   orderId : order id, Global Unique ID  
     */
    function cancelOrder(string memory orderId) public{
        _cancelOrderInfo(orderId);

        //set this order's info.
        emit UpdateOrderStatus(
            orderList[orderId]
        );
    }


    /*  FinishOrder
     *   orderId : order id, Global Unique ID  
     */
    function confirmOrderByBuyer(string memory orderId) public{
        _confirmOrderByBuyer(orderId);

        emit UpdateOrderStatus(
            orderList[orderId]
        );
    }


    /*
     *   orderId : order id, Global Unique ID  
     *   passData: the pass from oracle
     */
    function finishOrderBySeller(string memory orderId,string memory passData) public{
        _finishOrderBySeller(orderId,passData);

        emit UpdateOrderStatus(
            orderList[orderId]
        );
    }





    /*************************************************************************************************************************
    *************************************************     private functions   ************************************************
    *************************************************************************************************************************/

    // Function to create order info   
    function _createOrderInfo(string memory orderId,uint256 totalPrice,int cmd) internal {
        require(orderList[orderId].status == 0, "The order is created before");

        if (cmd == 1){
            orderList[orderId].seller = msg.sender;
            orderList[orderId].status = 1;

        }else {
            orderList[orderId].buyer = msg.sender;
            orderList[orderId].status = 2;
        }
        orderList[orderId].price = totalPrice;
        orderList[orderId].balance = totalPrice;

    }


    function _payOrderInfo(string memory orderId,uint256 totalPrice,int cmd) internal{
        require(orderList[orderId].status < 3, "The order can't payed");
        require(cmd == 1 || cmd == 2 , "cmd error");


        if (cmd == 1){
            require(orderList[orderId].status != 1, "The order can't payed");

            orderList[orderId].seller = msg.sender;
            if (orderList[orderId].status == 2) {
                orderList[orderId].status = 3;
            }else {
                orderList[orderId].status = 1;
            }
        }else if (cmd == 2) {
            require(orderList[orderId].status != 2, "The order can't payed");

            orderList[orderId].buyer = msg.sender;
            if (orderList[orderId].status == 1) {
                orderList[orderId].status = 3;
            }else {
                orderList[orderId].status = 2;
            }
        }
        orderList[orderId].price = totalPrice;
        orderList[orderId].balance = totalPrice + orderList[orderId].balance;
    }


    function _cancelOrderInfo(string memory orderId) internal {
        require(orderList[orderId].seller == msg.sender || orderList[orderId].buyer == msg.sender, "Can't find your order");

        if (orderList[orderId].seller == msg.sender) {
            if(orderList[orderId].buyer == address(0)){ // nobody pay for seller
                _cancelOrder(orderId);
                return;
            }

            if (orderList[orderId].status == 4){
                orderList[orderId].status = 8;
                _cancelAndFinishOrder(orderId);
            }else {
                //waiting for the other cancel
                orderList[orderId].status = 5;
            }
        } else {
            if(orderList[orderId].seller == address(0)){ // nobody pay for buyer
                _cancelOrder(orderId);
                return;
            }

            if (orderList[orderId].status == 5){
                orderList[orderId].status = 8;
                _cancelAndFinishOrder(orderId);
            }else { 
                //waiting for the other cancel
                orderList[orderId].status = 4;
            }
        }
    }

    function _cancelOrder(string memory orderId) internal {

        //refund to buyer and seller
        IERC20 paymentToken = IERC20(tradeToken);
        uint256 totalPrice = orderList[orderId].balance - orderList[orderId].price/100*platformFee;
        paymentToken.transfer(msg.sender, totalPrice);
        orderList[orderId].balance = 0;
    }

    function _cancelAndFinishOrder(string memory orderId) internal {

        //refund to buyer and seller
        IERC20 paymentToken = IERC20(tradeToken);
        uint256 totalPrice = orderList[orderId].balance/2 - orderList[orderId].price/100*platformFee;
        paymentToken.transfer(orderList[orderId].buyer, totalPrice);
        paymentToken.transfer(orderList[orderId].seller, totalPrice);
        orderList[orderId].balance = 0;
    }

    function _confirmOrderByBuyer(string memory orderId) internal {
        require(orderList[orderId].buyer == msg.sender, "Can't find your order");
        require(orderList[orderId].seller != address(0), "The order can't finish,because can't find the seller");

        orderList[orderId].status = 100;

        IERC20 paymentToken = IERC20(tradeToken);
        uint256 totalPrice = orderList[orderId].balance - orderList[orderId].price/100*platformFee;
        paymentToken.transfer(orderList[orderId].seller, totalPrice);
        orderList[orderId].balance = 0;
    }



    function _finishOrderBySeller(string memory orderId,string memory passData) internal {
        require(orderList[orderId].buyer == msg.sender, "Can't find your order");
        require(orderList[orderId].seller != address(0), "The order can't finish,because can't find the seller");

        //verify passData
        bytes memory packedMessage = toPackedMessage(orderId, msg.sender, 100); //type = 2 is finish
        bytes32 messageHash = toEthSignedMessageHash(packedMessage);
        bool isSignatureValid = verifySignature(oracleAddress, messageHash, passData);
        require(isSignatureValid, "Invalid signature");
        //verify end

        orderList[orderId].status = 100;

        IERC20 paymentToken = IERC20(tradeToken);
        uint256 totalPrice = orderList[orderId].balance - orderList[orderId].price/100*platformFee ;
        paymentToken.transfer(orderList[orderId].seller, totalPrice);
        orderList[orderId].balance = 0;
    }



    /*
     * verify for oracel
     */
    function toPackedMessage(
        string memory orderId, // 32 bytes
        address _address, // 20 bytes
        uint8 _signType // 1 byte
    ) internal view returns (bytes memory) {
        address contractAddress = address(this); // 20 bytes
        return abi.encodePacked(orderId, _address, contractAddress, _signType);
    }

    // Verify ECDSA signature
    function verifySignature(
        address _address,
        bytes32 _hash,
        string memory _signature
    ) internal pure returns (bool) {
        bytes memory signatureBytes = bytes(_signature);
        // 目前只能用assembly (内联汇编)来从签名中获得r,s,v的值
        bytes memory r_bytes = new bytes(64);
        bytes memory s_bytes = new bytes(64);
        bytes memory v_bytes = new bytes(2);
        assembly {
            mstore(add(r_bytes, 0x20), mload(add(signatureBytes, 0x20)))
            mstore(add(r_bytes, 0x40), mload(add(signatureBytes, 0x40)))
            mstore(add(s_bytes, 0x20), mload(add(signatureBytes, 0x60)))
            mstore(add(s_bytes, 0x40), mload(add(signatureBytes, 0x80)))
            mstore(add(v_bytes, 0x20), mload(add(signatureBytes, 0xA0)))
        }
        bytes32 r = (bytes32FromHexString(string(r_bytes)));
        bytes32 s = (bytes32FromHexString(string(s_bytes)));
        uint8 v = uint8(bytes1FromHexString(string(v_bytes)));
        address signer = ecrecover(_hash, v, r, s);
        if (signer == address(0)) {
            return false;
        }
        if (signer != _address) {
            return false;
        }
        return true;
    }


    function bytesFromHexString(string memory text) internal pure returns (bytes memory) {
        bytes memory textBytes = bytes(text);
        uint256 textBytesLength = textBytes.length;
        require(textBytesLength % 2 == 0, "The text is not hex format");
        uint256 dataLength = textBytesLength / 2;
        bytes memory data = new bytes(dataLength);
        for (uint256 i = 0; i < dataLength; i++) {
            uint32 c1 = uint32(uint8(textBytes[i * 2]));
            uint32 c2 = uint32(uint8(textBytes[i * 2 + 1]));
            require((c1 >= 48 && c1 <= 57) || (c1 >= 65 && c1 <= 70) || (c1 >= 97 && c1 <= 102), "The text is not hex format");
            require((c2 >= 48 && c2 <= 57) || (c2 >= 65 && c2 <= 70) || (c2 >= 97 && c2 <= 102), "The text is not hex format");
            uint32 hi = c1 - 48 - (c1 / 65) * 7 - (c1 / 97) * 32;
            uint32 lo = c2 - 48 - (c2 / 65) * 7 - (c2 / 97) * 32;
            uint32 value = (hi << 4) + lo;
            data[i] = bytes1(uint8(value));
        } 
        return data;
    }

    function bytes1FromHexString(string memory text) internal pure returns (bytes1) {
        bytes memory dataBytes = bytesFromHexString(text);
        uint256 dataLength = dataBytes.length;
        require(dataLength == 1, "The text is not bytes1 hex format");
        bytes1 data;
        assembly {
            data := mload(add(dataBytes, 0x20))
        }
        return data;
    }

    function bytes32FromHexString(string memory text) internal pure returns (bytes32) {
        bytes memory dataBytes = bytesFromHexString(text);
        uint256 dataLength = dataBytes.length;
        require(dataLength == 32, "The text is not bytes32 hex format");
        bytes32 data;
        assembly {
            data := mload(add(dataBytes, 0x20))
        }
        return data;
    }

    function toEthSignedMessageHash(bytes memory _message) internal pure returns (bytes32) {
        // The length of origin_message
        string memory len = Strings.toString(_message.length);
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", len, _message));
    }
}
