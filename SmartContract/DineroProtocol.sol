// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import  "./VerifyBase.sol";
import "./SignatureData.sol"; 
// import "@openzeppelin/contracts@4.9.6/utils/Strings.sol";
import "@openzeppelin/contracts@4.9.6/access/Ownable.sol";
import "@openzeppelin/contracts@4.9.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";




contract DOrderContract is Ownable {

    string public chainId;

    address public oracleAddress;

    address public feeAddress;

    uint256 public platformFee = 2;     //platform fee 

    address public tradeToken;


    struct DOrderModel {
        address buyer;
        address seller;
        uint256 price;
        uint256 balance;

        //1. waiting for buyer  2. waiting for seller  3.both are payed 4.cancel with buyer  5.cancel with seller 6.appeal with buyer 7. appeal with seller 8.cancel    100.finish
        int status;  
    }

    mapping(string => DOrderModel) public orderList;


    event UpdateOrderStatus(
        DOrderModel order
    );


    modifier canCreateOrder(string memory orderId,uint256 totalPrice,int cmd)  {
        require(tradeToken != address(0), "Invalid tradeToken address");

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

    //set chainId
    function setChainId(string memory _chainId) external onlyOwner {
        chainId = _chainId;
    }

    //set trade token
    function setTradeToken(address tokenAddress) external onlyOwner {
        tradeToken = tokenAddress;
    }

    //set Oracle Address 
    function setOracleAddress(address _address) external onlyOwner {
        oracleAddress = _address;
    }

    //set Fee Address 
    function setFeeAddress(address _feeAddress) external onlyOwner {
        feeAddress = _feeAddress;
    }

    //set platformFee 
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
        (bool success, uint256 amount) = SafeMath.tryAdd(totalPrice,orderList[orderId].balance);
        require(success, "SafeMath.tryAdd amount fail");
        orderList[orderId].balance = amount;
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
        uint256 fee = orderList[orderId].price*platformFee/100;
        (bool success,uint256 amount) = SafeMath.trySub(orderList[orderId].balance,fee);
        require(success, "SafeMath.tryAdd amount fail");
        IERC20 paymentToken = IERC20(tradeToken);
        paymentToken.transfer(msg.sender, amount);

        uint256 feeAmount = orderList[orderId].balance - amount;
        paymentToken.transfer(feeAddress, feeAmount);

        orderList[orderId].balance = 0;
    }

    function _cancelAndFinishOrder(string memory orderId) internal {

        //refund to buyer and seller
        uint256 fee = orderList[orderId].price*platformFee/100;
        (bool success,uint256 amount) = SafeMath.trySub(orderList[orderId].balance,fee);
        require(success, "SafeMath.tryAdd amount fail");


        IERC20 paymentToken = IERC20(tradeToken);
        paymentToken.transfer(orderList[orderId].buyer, amount/2);
        paymentToken.transfer(orderList[orderId].seller, amount/2);

        uint256 feeAmount = orderList[orderId].balance - amount;
        paymentToken.transfer(feeAddress, feeAmount);

        orderList[orderId].balance = 0;
    }

    function _confirmOrderByBuyer(string memory orderId) internal {
        require(orderList[orderId].buyer == msg.sender, "Can't find your order");
        require(orderList[orderId].seller != address(0), "The order can't finish,because can't find the seller");

        orderList[orderId].status = 100;

        uint256 fee = orderList[orderId].price/100*platformFee;
        (bool success,uint256 amount) = SafeMath.trySub(orderList[orderId].balance,fee);
        require(success, "SafeMath.tryAdd amount fail");

        IERC20 paymentToken = IERC20(tradeToken);
        paymentToken.transfer(orderList[orderId].seller, amount);


        uint256 feeAmount = orderList[orderId].balance - amount;
        paymentToken.transfer(feeAddress, feeAmount);

        orderList[orderId].balance = 0;
    }

    function _finishOrderBySeller(string memory orderId,string memory passData) internal {
        require(orderList[orderId].seller == msg.sender, "Can't find your order");
        require(orderList[orderId].buyer != address(0), "The order can't finish,because can't find the buyer");
        require(orderList[orderId].balance > 0, "The order balance is 0");

        bool isSignatureValid = callVerifySignature(chainId, address(this), oracleAddress, msg.sender, "100", orderId,passData);
        require(isSignatureValid, "Invalid signature");


        orderList[orderId].status = 100;

        IERC20 paymentToken = IERC20(tradeToken);
        uint256 totalPrice = orderList[orderId].balance - orderList[orderId].price/100*platformFee ;
        paymentToken.transfer(orderList[orderId].seller, totalPrice);

        uint256 feeAmount = orderList[orderId].balance - totalPrice;
        paymentToken.transfer(feeAddress, feeAmount);

        orderList[orderId].balance = 0;
    }

    function callVerifySignature(
        string memory _chainId,
        address contractAddress,
        address serverAddress,
        address userAddress,
        string memory signatureType,
        string memory s1,
        string memory serverSignature
    ) public view returns (bool) {
        // 创建 SignatureData 实例
        SignatureData memory signatureData = SignatureData({
            chainId: _chainId,
            contractAddress: contractAddress,
            serverAddress: serverAddress,
            userAddress: userAddress,
            signatureType: signatureType,
            s1: s1
        });

        // call verifySignature of VerifyBase
        return  verifySignature(signatureData, serverSignature);
    }



    /*************************************************************************************************************************
    *************************************************     verify base   ************************************************
    *************************************************************************************************************************/

    function strCmp(string memory left, string memory right) internal pure returns (bool) {
        bytes memory leftBytes = bytes(left);
        bytes memory rightBytes = bytes(right);
        if (leftBytes.length != rightBytes.length) {
            return false;
        }
        uint256 n = leftBytes.length;
        for (uint i = 0; i < n; i ++) {
            if(leftBytes[i] != rightBytes[i]) {
                return false;
            }
        }
        return true;
    }

    function bytesToHexString(bytes memory data) internal pure returns (string memory) {
        uint256 dataLength = data.length;
        uint256 textBytesLength = dataLength * 2;
        bytes memory textBytes = new bytes(textBytesLength);
        for (uint256 i = 0; i < dataLength; i++) {
            uint32 value = uint32(uint8(data[i]));
            uint32 hi = value >> 4;
            uint32 lo = value & 0x0f;
            uint32 c1 = hi + 48 + (hi / 10) * 39;
            uint32 c2 = lo + 48 + (lo / 10) * 39;
            textBytes[i * 2] = bytes1(uint8(c1));
            textBytes[i * 2 + 1] = bytes1(uint8(c2));
        }
        string memory text = string(textBytes);
        return text;
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

    function bytes20FromHexString(string memory text) internal pure returns (bytes20) {
        bytes memory dataBytes = bytesFromHexString(text);
        uint256 dataLength = dataBytes.length;
        require(dataLength == 20, "The text is not bytes20 hex format");
        bytes20 data;
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

    // Verify ECDSA signature
    function verifySignatureImpl(
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

    function toPackedBytes(string memory str) public pure returns (bytes memory) {
        bytes memory packedBytes = abi.encodePacked(
            bytes(str).length, // 32 bytes
            str
        );
        return packedBytes;
    }

    function toPackedMessage(
        SignatureData memory signatureData
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            toPackedBytes(signatureData.chainId),
            signatureData.contractAddress, // 20 bytes
            signatureData.serverAddress, // 20 bytes
            signatureData.userAddress, // 20 bytes
            toPackedBytes(signatureData.signatureType),
            toPackedBytes(signatureData.s1)
        );
    }

    function verifySignature(SignatureData memory signatureData, string memory serverSignature) public view returns (bool) {
        require(strCmp(signatureData.chainId, chainId));
        require(signatureData.contractAddress == address(this));
        require(signatureData.serverAddress == oracleAddress);
        require(signatureData.userAddress == msg.sender);

        bytes memory packedMessage = toPackedMessage(signatureData);
        bytes32 messageHash = toEthSignedMessageHash(packedMessage);
        bool isSignatureValid = verifySignatureImpl(oracleAddress, messageHash, serverSignature);
        return isSignatureValid;
    }

}