const YogaTokenAbi = require('../build/YogaToken.sol').YogaTokenAbi;
const YogaTokenByteCode = require('../build/YogaToken.sol').YogaTokenByteCode;
const generateClass = require('eth-contract-class').default;

module.exports = generateClass(YogaTokenAbi, YogaTokenByteCode);
