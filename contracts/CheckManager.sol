


import "../node_modules/solidity-stl/contracts/src/codec/RLP.sol";


import "../node_modules/eip672/contracts/EIP672.sol";

contract ERC20 {
    function transferFrom(address from, address to, uint amount) public returns(bool);
}

contract IYogaToken {
    function operatorSend(address from, address to, uint amount, bytes data, bytes32 ref) public returns(bool);
}

contract CheckManager is EIP672 {
    using RLP for RLP.RLPItem;
    using RLP for RLP.Iterator;
    using RLP for bytes;

    address public token;
    bool public isLegacyToken;

    struct Recipient {
        address recipient;
        uint amount;
        bytes data;
    }

    struct Check {
        address from;
        uint id;
        uint expiration;
        uint amount;
        Recipient[] recipients;
    }

    mapping(address => mapping(uint => bool)) usedChecks;

    function CheckManager(address _token) {
        token = interfaceAddr(_token, "IYogaToken");
        if (token == 0) {
            token = _token;
            isLegacyToken = true;
        }
    }

    function doSend(address from, address to, uint amount, bytes data, bytes32 ref) internal {
        if (isLegacyToken) {
            require(data.length == 0);
            require(ERC20(token).transferFrom(from, to, amount));
        } else {
            IYogaToken(token).operatorSend(from, to, amount, data, ref);
        }
    }

    function processChecks(bytes rlpChecks, address remainingAddr, bytes remainingData) {
        Check[] memory checks = parseRlpChecks(rlpChecks);
        for (uint i=0; i<checks.length; i++) {
            Check memory c = checks[i];
            uint remainingAmount = c.amount;
            for (uint j = 0; j<c.recipients.length; j++) {
                Recipient memory r = c.recipients[j];
                require(r.amount <= remainingAmount);

                doSend(c.from, r.recipient, r.amount, r.data, bytes32(c.id));
                remainingAmount -= r.amount;
            }
            if (remainingAmount > 0) {
                doSend(c.from, remainingAddr, remainingAmount, remainingData, bytes32(c.id));
            }
        }
    }

    function isCheck(RLP.RLPItem itm) internal returns(bool) {
        return (itm.iterator().next().iterator().next().isList() == false);
    }

    function parseRlpChecks(bytes rlpChecks) internal returns (Check[] memory checks) {
        var itm = rlpChecks.toRLPItem(true);

        if (isCheck(itm)) {
            checks = new Check[](1);
            parseCheck(checks[0], itm);
        } else {
            require (itm.isList());
            checks = new Check[](itm.items());
            var itrChecks = itm.iterator();

            for (uint i=0; i < checks.length; i++) {
                var itmCheck = itrChecks.next();
                parseCheck(checks[i], itmCheck);
            }
        }
    }


    function parseRecipients(RLP.RLPItem itmRecipients) view internal returns (Recipient[] memory recipients) {

        require (itmRecipients.isList());
        var itrRecipients = itmRecipients.iterator();
        recipients = new Recipient[](itmRecipients.items());

        for (uint i = 0; i < recipients.length; i++) {
            var itmRecipient = itrRecipients.next();
            require (itmRecipient.isList());
            var itrRecipient = itmRecipient.iterator();

            recipients[i].recipient = itrRecipient.next().toAddress();
            recipients[i].amount = itrRecipient.next().toUint();
            recipients[i].data = itrRecipient.next().toBytes();
        }

        return recipients;
    }

    function parseCheck(Check memory check, RLP.RLPItem itmCheck) view internal {
        require (itmCheck.isList());
        var itrCheck = itmCheck.iterator();

        var itmData = itrCheck.next();
        bytes32 hash = keccak256(itmData.toBytes());
        require (itmData.isList());
        var itrData = itmData.iterator();
        check.from = itrData.next().toAddress();
        check.id = itrData.next().toUint();
        check.expiration = itrData.next().toUint();
        check.amount = itrData.next().toUint();

        if (itrData.hasNext()) {
            check.recipients = parseRecipients(itrData.next());
        } else {
            check.recipients = new Recipient[](0);
        }

        var itmSignature = itrCheck.next();
        require (itmSignature.isList());
        var itrSignature = itmSignature.iterator();
        uint8 v = uint8(itrSignature.next().toByte());
        bytes32 r = itrSignature.next().toBytes32();
        bytes32 s = itrSignature.next().toBytes32();

        require( ecrecover(hash, v, r, s) == check.from );
        require( check.id != 0);
        require( check.expiration >= now );
        require( !usedChecks[check.from][check.id]);
    }


}
