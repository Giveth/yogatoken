pragma solidity ^0.4.18;

interface ITokenFallback {
    function tokenFallback(address _from, address _to, uint _value, bytes _data, bytes32 _ref) public;
}
