const tr = require('../build/testRecipient.sol');

const generateClass = require('eth-contract-class').default;

module.exports.RecipientERC20 = generateClass(
    tr.RecipientERC20Abi, tr.RecipientERC20ByteCode);
module.exports.RecipientERC223 = generateClass(
    tr.RecipientERC223Abi, tr.RecipientERC223ByteCode);
module.exports.ExternalContract = generateClass(
    tr.ExternalContractAbi, tr.ExternalContractByteCode);
module.exports.ProxyAccept = generateClass(
    tr.ProxyAcceptAbi, tr.ProxyAcceptByteCode);
module.exports.ProxyReject = generateClass(
    tr.ProxyRejectAbi, tr.ProxyRejectByteCode);
