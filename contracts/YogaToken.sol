pragma solidity ^0.4.18;

/*
    Copyright 2016, Jordi Baylina

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/// @title Yoga Token Contract
/// @author Jordi Baylina
/// @dev This token contract's goal is to make it easy for anyone to clone this
///  token using the token distribution at a given block, this will allow DAO's
///  and DApps to upgrade their features in a decentralized manner without
///  affecting the original token
/// @dev It is ERC223 compliant and also implements some ERC20 functions to
///  maintain backwards compatibility.

import "./Controlled.sol";
import "../node_modules/eip672/contracts/EIP672.sol";
import "./ITokenFallback.sol";
import "./ITokenController.sol";

contract IApproveAndCallFallBack {
    function receiveApproval(address from, uint256 _amount, address _token, bytes _data) public;
}

/// @dev The actual token contract, the default controller is the msg.sender
///  that deploys the contract, so usually this token will be deployed by a
///  token controller contract, which Giveth will call a "Campaign"
contract YogaToken is Controlled, EIP672 {

    string public name;                //The Token's name: e.g. DigixDAO Tokens
    uint8 public decimals;             //Number of decimals of the smallest unit
    string public symbol;              //An identifier: e.g. REP
    string public version = 'YogaToken_1.0'; //An arbitrary versioning scheme


    /// @dev `Checkpoint` is the structure that attaches a block number to a
    ///  given value, the block number attached is the one that last changed the
    ///  value
    struct  Checkpoint {

        // `fromBlock` is the block number that the value was generated from
        uint128 fromBlock;

        // `value` is the amount of tokens at a specific block number
        uint128 value;
    }

    // `parentToken` is the Token address that was cloned to produce this token;
    //  it will be 0x0 for a token that was not cloned
    YogaToken public parentToken;

    // `parentSnapShotBlock` is the block number from the Parent Token that was
    //  used to determine the initial distribution of the Clone Token
    uint public parentSnapShotBlock;

    // `creationBlock` is the block number that the Clone Token was created
    uint public creationBlock;

    // `balances` is the map that tracks the balance of each address, in this
    //  contract when the balance changes the block number that the change
    //  occurred is also included in the map
    mapping (address => Checkpoint[]) balances;

    // `allowed` tracks any extra transfer rights as in all ERC20 tokens
    mapping (address => mapping (address => uint256)) allowed;


    mapping (address => bool) globallyAuthorizedOperators;
    mapping (address => mapping (address => bool)) authorizedOperators;

    // Tracks the history of the `totalSupply` of the token
    Checkpoint[] totalSupplyHistory;

    // Flag that determines if the token is transferable or not.
    bool public sendsEnabled;

    // The factory used to create new clone tokens
    YogaTokenFactory public tokenFactory;

////////////////
// Constructor
////////////////

    /// @notice Constructor to create a YogaToken
    /// @param _tokenFactory The address of the YogaTokenFactory contract that
    ///  will create the Clone token contracts, the token factory needs to be
    ///  deployed first
    /// @param _parentToken Address of the parent token, set to 0x0 if it is a
    ///  new token
    /// @param _parentSnapShotBlock Block of the parent token that will
    ///  determine the initial distribution of the clone token, set to 0 if it
    ///  is a new token
    /// @param _tokenName Name of the new token
    /// @param _decimalUnits Number of decimals of the new token
    /// @param _tokenSymbol Token Symbol for the new token
    /// @param _sendsEnabled If true, tokens will be able to be transferred
    function YogaToken(
        address _tokenFactory,
        address _parentToken,
        uint _parentSnapShotBlock,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol,
        bool _sendsEnabled
    ) public {
        tokenFactory = YogaTokenFactory(_tokenFactory);
        name = _tokenName;                                 // Set the name
        decimals = _decimalUnits;                          // Set the decimals
        symbol = _tokenSymbol;                             // Set the symbol
        parentToken = YogaToken(_parentToken);
        parentSnapShotBlock = _parentSnapShotBlock;
        sendsEnabled = _sendsEnabled;
        creationBlock = block.number;
        setInterfaceImplementation("IYogaToken", address(this));
    }


///////////////////
// ERC223 Methods
///////////////////

    /// @notice Send `_amount` tokens to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be sent
    function send(address _to, uint256 _amount) public {
        require(sendsEnabled);
        return doSend(msg.sender, _to, _amount, "", 0);
    }

    /// @notice Send `_amount` tokens to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be transferred
    /// @param _data Date to be transfered to the receipt interface
    function send(address _to, uint256 _amount, bytes _data) public {
        require(sendsEnabled);
        return doSend(msg.sender, _to, _amount, _data, 0);
    }

    /// @notice Send `_amount` tokens to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be sent
    /// @param _data Data to be sent to the receipt interface
    /// @param _ref Reference payment for accounting purpuses
    function send(address _to, uint256 _amount, bytes _data, bytes32 _ref) public {
        require(sendsEnabled);
        return doSend(msg.sender, _to, _amount, _data, _ref);
    }


    function operatorSend(address _from, address _to, uint256 _amount, bytes _data, bytes32 _ref) public {
        require( isOperatorAuthorizedFor(msg.sender, _from));
        doSend(_from, _to, _amount, _data, _ref);
    }

    /// @dev This is the actual send function in the token contract, it can
    ///  only be called by other functions in this contract.
    /// @param _from The address holding the tokens being sent
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be sent
    /// @param _data Data to be sent to the receipt interface
    /// @param _ref Reference payment for accounting purpuses
    function doSend(address _from, address _to, uint _amount, bytes _data, bytes32 _ref
    ) internal {

        require(parentSnapShotBlock < block.number);

        // Do not allow transfer to 0x0 or the token contract itself
        require((_to != 0) && (_to != address(this)));

        // If the amount being transfered is more than the balance of the
        //  account the transfer throw
        var previousBalanceFrom = balanceOfAt(_from, block.number);
        require (previousBalanceFrom >= _amount);

        address controllerImpl = interfaceAddr(controller, "ITokenController");
        if (controllerImpl != 0) {
            ITokenController(controllerImpl).onSend(_from, _to, _amount, _data, _ref);
        }

        address fallbackImpl = interfaceAddr(_to, "ITokenFallback");

        // If ITokenFallback is not implemented for _to only allow
        // transfers to normal address and not to contracts.
        // It allows transfer also if msg.sender is the recipient
        //   This situation tipically happen after approve in ERC20 compatible.
        require (fallbackImpl != 0 || (!isContract(_to)) || (_to == msg.sender));

        // First update the balance array with the new value for the address
        //  sending the tokens
        updateValueAtNow(balances[_from], previousBalanceFrom - _amount);

        // Then update the balance array with the new value for the address
        //  receiving the tokens
        var previousBalanceTo = balanceOfAt(_to, block.number);
        require(previousBalanceTo + _amount >= previousBalanceTo); // Check for overflow
        updateValueAtNow(balances[_to], previousBalanceTo + _amount);


        if (fallbackImpl != 0) {
            ITokenFallback(fallbackImpl).tokenFallback(_from, _to, _amount, _data, _ref);
        }

        // An event to make the sends easy to find on the blockchain
        Transfer(_from, _to, _amount);      // For ERC20 compatibility
        Send(_from, _to, _amount, _data, _ref);

    }

///////////////////
// Operators functions
///////////////////

    function authorizeOperator(address _operator, bool _authorized) public {
        authorizedOperators[msg.sender][_operator] = _authorized;
        AuthorizeOperator(msg.sender, _operator, _authorized);
    }

    function authorizeGlobalOperator(address _operator, bool _authorized)  onlyController public {
        globallyAuthorizedOperators[_operator] = _authorized;
        AuthorizeGlobalOperator(_operator, _authorized);
    }

    function isOperatorAuthorizedFor(address _operator, address _tokenHoler) public constant returns (bool) {
        return globallyAuthorizedOperators[_operator] || authorizedOperators[_tokenHoler][_operator];
    }

    function isOperatorGloballyAuthorized(address _operator) public constant returns (bool) {
        return globallyAuthorizedOperators[_operator];
    }

///////////////////
// ERC20 Compatible Methods
///////////////////

    /// @notice Send `_amount` tokens to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be transferred
    function transfer(address _to, uint256 _amount) public returns(bool) {
        require(isContract(msg.sender));
        require(sendsEnabled);
        doSend(msg.sender, _to, _amount, "", 0);
        return true; // For backwards compatibility.
    }

    /// @notice Send `_amount` tokens to `_to` from `_from` on the condition it
    ///  is approved by `_from`
    /// @param _from The address holding the tokens being transferred
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be transferred
    function transferFrom(address _from, address _to, uint256 _amount
    ) public returns (bool) {
        require(isContract(msg.sender));
        require(sendsEnabled);
        require(allowed[_from][msg.sender] >= _amount);
        if (allowed[_from][msg.sender] < uint(-1)) allowed[_from][msg.sender] -= _amount;
        doSend(_from, _to, _amount, "", 0);
        return true; // For backwards compatibility.
    }


    /// @notice `msg.sender` approves `_spender` to spend `_amount` tokens on
    ///  its behalf. This is a modified version of the ERC20 approve function
    ///  to be a little bit safer
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _amount The amount of tokens to be approved for transfer
    function approve(address _spender, uint256 _amount) public returns(bool) {
        require(sendsEnabled);

        // To change the approve amount you first have to reduce the addresses`
        //  allowance to zero by calling `approve(_spender,0)` if it is not
        //  already 0 to mitigate the race condition described here:
        //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        require((_amount == 0) || (allowed[msg.sender][_spender] == 0));

        allowed[msg.sender][_spender] = _amount;
        Approval(msg.sender, _spender, _amount);
        return true;  // For backwards compatibility
    }

///////////////////
// Constant functions
///////////////////

    /// @param _owner The address that's balance is being requested
    /// @return The balance of `_owner` at the current block
    function balanceOf(address _owner) public constant returns (uint256 balance) {
        return balanceOfAt(_owner, block.number);
    }

    /// @dev This function makes it easy to read the `allowed[]` map
    /// @param _owner The address of the account that owns the token
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens of _owner that _spender is allowed
    ///  to spend
    function allowance(address _owner, address _spender
    ) public constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    /// @dev This function makes it easy to get the total number of tokens
    /// @return The total number of tokens
    function totalSupply() public constant returns (uint) {
        return totalSupplyAt(block.number);
    }


////////////////
// Query balance and totalSupply in History
////////////////

    /// @dev Queries the balance of `_owner` at a specific `_blockNumber`
    /// @param _owner The address from which the balance will be retrieved
    /// @param _blockNumber The block number when the balance is queried
    /// @return The balance at `_blockNumber`
    function balanceOfAt(address _owner, uint _blockNumber) public constant
        returns (uint) {

        // These next few lines are used when the balance of the token is
        //  requested before a check point was ever created for this token, it
        //  requires that the `parentToken.balanceOfAt` be queried at the
        //  genesis block for that token as this contains initial balance of
        //  this token
        if ((balances[_owner].length == 0)
            || (balances[_owner][0].fromBlock > _blockNumber)) {
            if (address(parentToken) != 0) {
                return parentToken.balanceOfAt(_owner, min(_blockNumber, parentSnapShotBlock));
            } else {
                // Has no parent
                return 0;
            }

        // This will return the expected balance during normal situations
        } else {
            return getValueAt(balances[_owner], _blockNumber);
        }
    }

    /// @notice Total amount of tokens at a specific `_blockNumber`.
    /// @param _blockNumber The block number when the totalSupply is queried
    /// @return The total amount of tokens at `_blockNumber`
    function totalSupplyAt(uint _blockNumber) public constant returns(uint) {

        // These next few lines are used when the totalSupply of the token is
        //  requested before a check point was ever created for this token, it
        //  requires that the `parentToken.totalSupplyAt` be queried at the
        //  genesis block for this token as that contains totalSupply of this
        //  token at this block number.
        if ((totalSupplyHistory.length == 0)
            || (totalSupplyHistory[0].fromBlock > _blockNumber)) {
            if (address(parentToken) != 0) {
                return parentToken.totalSupplyAt(min(_blockNumber, parentSnapShotBlock));
            } else {
                return 0;
            }

        // This will return the expected totalSupply during normal situations
        } else {
            return getValueAt(totalSupplyHistory, _blockNumber);
        }
    }

////////////////
// Clone Token Method
////////////////

    /// @notice Creates a new clone token with the initial distribution being
    ///  this token at `_snapshotBlock`
    /// @param _cloneTokenName Name of the clone token
    /// @param _cloneDecimalUnits Number of decimals of the smallest unit
    /// @param _cloneTokenSymbol Symbol of the clone token
    /// @param _snapshotBlock Block when the distribution of the parent token is
    ///  copied to set the initial distribution of the new clone token;
    ///  if the block is zero than the actual block, the current block is used
    /// @param _sendsEnabled True if transfers are allowed in the clone
    /// @return The address of the new YogaToken Contract
    function createCloneToken(
        string _cloneTokenName,
        uint8 _cloneDecimalUnits,
        string _cloneTokenSymbol,
        uint _snapshotBlock,
        bool _sendsEnabled
        ) public returns(address) {
        if (_snapshotBlock == 0) _snapshotBlock = block.number;
        YogaToken cloneToken = tokenFactory.createCloneToken(
            this,
            _snapshotBlock,
            _cloneTokenName,
            _cloneDecimalUnits,
            _cloneTokenSymbol,
            _sendsEnabled
            );

        cloneToken.changeController(msg.sender);

        // An event to make the token easy to find on the blockchain
        NewCloneToken(address(cloneToken), _snapshotBlock);
        return address(cloneToken);
    }

////////////////
// Generate and destroy tokens
////////////////
    /// @notice Generates `_amount` tokens that are assigned to `_owner`
    /// @param _owner The address that will be assigned the new tokens
    /// @param _amount The quantity of tokens generated
    function generateTokens(address _owner, uint _amount
    ) public {
        generateTokens(_owner, _amount, "", 0);
    }


    /// @notice Generates `_amount` tokens that are assigned to `_owner`
    /// @param _owner The address that will be assigned the new tokens
    /// @param _amount The quantity of tokens generated
    /// @param _data The data to be sended to tokenFallback
    /// @param _ref The reference of the generation
    /// @return True if the tokens are generated correctly
    function generateTokens(address _owner, uint _amount, bytes _data, bytes32 _ref
    ) public onlyController {

        address fallbackImpl = interfaceAddr(_owner, "ITokenFallback");

        // If ITokenFallback is not implemented for _to only allow
        // transfers to normal address and not to contracts.
        require (fallbackImpl != 0 || (!isContract(_owner)));

        uint curTotalSupply = totalSupply();
        require(curTotalSupply + _amount >= curTotalSupply); // Check for overflow

        uint previousBalanceTo = balanceOf(_owner);
        require(previousBalanceTo + _amount >= previousBalanceTo); // Check for overflow

        updateValueAtNow(totalSupplyHistory, curTotalSupply + _amount);
        updateValueAtNow(balances[_owner], previousBalanceTo + _amount);

        if (fallbackImpl != 0) {
            ITokenFallback(fallbackImpl).tokenFallback(0, _owner, _amount, _data, _ref);
        }

        Transfer(0, _owner, _amount);
        Send(_owner, 0, _amount, _data, _ref);
    }

    /// @notice Burns `_amount` tokens from `_owner`
    /// @param _owner The address that will lose the tokens
    /// @param _amount The quantity of tokens to burn
    function destroyTokens(address _owner, uint _amount
    ) public {
        destroyTokens(_owner, _amount, 0);
    }

    /// @notice Burns `_amount` tokens from `_owner`
    /// @param _owner The address that will lose the tokens
    /// @param _amount The quantity of tokens to burn
    /// @param _ref Referenci of the destroy
    function destroyTokens(address _owner, uint _amount, bytes32 _ref
    ) onlyController public {
        uint curTotalSupply = totalSupply();
        require(curTotalSupply >= _amount);
        uint previousBalanceFrom = balanceOf(_owner);
        require(previousBalanceFrom >= _amount);
        updateValueAtNow(totalSupplyHistory, curTotalSupply - _amount);
        updateValueAtNow(balances[_owner], previousBalanceFrom - _amount);

        Transfer(_owner, 0, _amount);
        Send(_owner, 0, _amount, "", _ref);
    }

////////////////
// Enable tokens transfers
////////////////


    /// @notice Enables token holders to transfer their tokens freely if true
    /// @param _sendsEnabled True if transfers are allowed in the clone
    function enableSends(bool _sendsEnabled) public onlyController {
        sendsEnabled = _sendsEnabled;
    }

////////////////
// Internal helper functions to query and set a value in a snapshot array
////////////////

    /// @dev `getValueAt` retrieves the number of tokens at a given block number
    /// @param checkpoints The history of values being queried
    /// @param _block The block number to retrieve the value at
    /// @return The number of tokens being queried
    function getValueAt(Checkpoint[] storage checkpoints, uint _block
    ) constant internal returns (uint) {
        if (checkpoints.length == 0) return 0;

        // Shortcut for the actual value
        if (_block >= checkpoints[checkpoints.length-1].fromBlock)
            return checkpoints[checkpoints.length-1].value;
        if (_block < checkpoints[0].fromBlock) return 0;

        // Binary search of the value in the array
        uint min = 0;
        uint max = checkpoints.length-1;
        while (max > min) {
            uint mid = (max + min + 1)/ 2;
            if (checkpoints[mid].fromBlock<=_block) {
                min = mid;
            } else {
                max = mid-1;
            }
        }
        return checkpoints[min].value;
    }

    /// @dev `updateValueAtNow` used to update the `balances` map and the
    ///  `totalSupplyHistory`
    /// @param checkpoints The history of data being updated
    /// @param _value The new number of tokens
    function updateValueAtNow(Checkpoint[] storage checkpoints, uint _value
    ) internal  {
        if ((checkpoints.length == 0)
        || (checkpoints[checkpoints.length -1].fromBlock < block.number)) {
               Checkpoint storage newCheckPoint = checkpoints[ checkpoints.length++ ];
               newCheckPoint.fromBlock =  uint128(block.number);
               newCheckPoint.value = uint128(_value);
           } else {
               Checkpoint storage oldCheckPoint = checkpoints[checkpoints.length-1];
               oldCheckPoint.value = uint128(_value);
           }
    }

    /// @dev Helper function to return a min betwen the two uints
    function min(uint a, uint b) pure internal returns (uint) {
        return a < b ? a : b;
    }

    /// @notice The fallback function: If the contract's controller has not been
    ///  set to 0, then the `proxyPayment` method is called which relays the
    ///  ether and creates tokens as described in the token controller contract
    function () public payable {
        address controllerImpl = interfaceAddr(controller, "ITokenController");
        require(controllerImpl != 0);
        ITokenController(controllerImpl).proxyPayment.value(msg.value)(msg.sender);
    }

//////////
// Safety Methods
//////////

    /// @notice This method can be used by the controller to extract mistakenly
    ///  sent tokens to this contract.
    /// @param _token The address of the token contract that you want to recover
    ///  set to 0 in case you want to extract ether.
    function claimTokens(address _token) public onlyController {
        if (_token == 0x0) {
            controller.transfer(this.balance);
            return;
        }

        YogaToken token = YogaToken(_token);
        uint balance = token.balanceOf(this);
        token.transfer(controller, balance);
        ClaimedTokens(_token, controller, balance);
    }

////////////////
// Events
////////////////
    event ClaimedTokens(address indexed token, address indexed controller, uint amount);
    event Send(address indexed from, address indexed to, uint256 amount, bytes data,bytes32 indexed ref);
    event NewCloneToken(address indexed cloneToken, uint snapshotBlock);
    event AuthorizeOperator(address indexed holder, address indexed operator, bool authorize);
    event AuthorizeGlobalOperator(address indexed operator, bool authorize);

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _amount
        );

}


////////////////
// YogaTokenFactory
////////////////

/// @dev This contract is used to generate clone contracts from a contract.
///  In solidity this is the way to create a contract from a contract of the
///  same class
contract YogaTokenFactory {

    /// @notice Update the DApp by creating a new token with new functionalities
    ///  the msg.sender becomes the controller of this clone token
    /// @param _parentToken Address of the token being cloned
    /// @param _snapshotBlock Block of the parent token that will
    ///  determine the initial distribution of the clone token
    /// @param _tokenName Name of the new token
    /// @param _decimalUnits Number of decimals of the new token
    /// @param _tokenSymbol Token Symbol for the new token
    /// @param _transfersEnabled If true, tokens will be able to be transferred
    /// @return The address of the new token contract
    function createCloneToken(
        address _parentToken,
        uint _snapshotBlock,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol,
        bool _transfersEnabled
    ) public returns (YogaToken) {
        YogaToken newToken = new YogaToken(
            this,
            _parentToken,
            _snapshotBlock,
            _tokenName,
            _decimalUnits,
            _tokenSymbol,
            _transfersEnabled
            );

        newToken.changeController(msg.sender);
        return newToken;
    }
}
