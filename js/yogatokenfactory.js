const YogaTokenFactoryAbi = require('../build/YogaToken.sol').YogaTokenFactoryAbi;
const YogaTokenFactoryByteCode = require('../build/YogaToken.sol').YogaTokenFactoryByteCode;
const generateClass = require('eth-contract-class').default;

module.exports = generateClass(YogaTokenFactoryAbi, YogaTokenFactoryByteCode);
