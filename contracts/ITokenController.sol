pragma solidity ^0.4.18;

/// @dev The token controller contract must implement these functions
interface ITokenController {
    /// @notice Called when `_owner` sends ether to the MiniMe Token contract
    /// @param _owner The address that sent the ether to create tokens
    function proxyPayment(address _owner) public payable;

    /// @notice Notifies the controller about a token transfer allowing the
    ///  controller to react if desired
    /// @param _from The origin of the transfer
    /// @param _to The destination of the transfer
    /// @param _amount The amount of the transfer
    function onTransfer(address _from, address _to, uint _amount, bytes data) public;
}
