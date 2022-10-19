pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

contract ImplementationV1Mock is Initializable{

    uint public data;

    constructor(){}

    function initialize(uint _data) external initializer(){
        data=_data;
    }

    function getVersion() external pure returns(uint){
        return 1;
    }

}
