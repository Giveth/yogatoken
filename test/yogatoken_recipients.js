/* eslint-env mocha */
/* eslint-disable no-await-in-loop */
const TestRPC = require('ethereumjs-testrpc');
const Web3 = require('web3');
const chai = require('chai');

const YogaToken = require('../index.js').YogaToken;
const YogaTokenFactory = require('../index.js').YogaTokenFactory;
const YogaTokenState = require('../index.js').YogaTokenState;
const tr = require('../js/testrecipients.js');

const ensSimulator = require('ens-simulator');

const assert = chai.assert;

describe('YogaToken recipient test', () => {
  let testrpc;
  let web3;
  let ens;
  let accounts;
  let yogaToken;
  let yogaTokenState;

  before(async () => {
    testrpc = TestRPC.server({
      ws: true,
      gasLimit: 5800000,
      total_accounts: 10,
    });

    testrpc.listen(8546, '127.0.0.1');

    web3 = new Web3('ws://localhost:8546');
    accounts = await web3.eth.getAccounts();
    ens = await ensSimulator.deployENSSimulator(web3);
  });

  after((done) => {
    testrpc.close();
    done();
  });

  it('should deploy all the contracts', async () => {
    const tokenFactory = await YogaTokenFactory.new(web3);
    yogaToken = await YogaToken.new(web3,
      tokenFactory.$address,
      0,
      0,
      'Yoga Test Token',
      18,
      'MMT',
      true);
    assert.ok(yogaToken.$address);
    yogaTokenState = new YogaTokenState(yogaToken);
  }).timeout(20000);

  it('Should generate tokens for address 1', async () => {
    await yogaToken['generateTokens(address,uint256)'](accounts[1], 10, { from: accounts[0], gas: 300000 });
//    await yogaToken.generateTokens(accounts[1], 10, '0x', { gas: 300000 });
    const st = await yogaTokenState.getState();
    assert.equal(st.totalSupply, 10);
    assert.equal(st.balances[accounts[1]], 10);
  }).timeout(6000);

  it('Should transfer ERC20 compatible token', async () => {
    const recipient = await tr.RecipientERC20.new(web3, { from: accounts[0], gas: 2000000 });
    await yogaToken.approve(recipient.$address, 1, { from: accounts[1], gas: 200000 });
    await recipient.collect(yogaToken.$address, 1, { from: accounts[1], gas: 200000 });
    const b = await yogaToken.balanceOf(recipient.$address);
    assert.equal(b, 1);
  }).timeout(6000);

  it('Should not be able to transfer to a normal contract', async () => {
    const recipient = await tr.ExternalContract.new(web3);
    try {
      await yogaToken['send(address,uint256)'](recipient.$address, 1, { from: accounts[1], gas: 400000 });
    } catch (e) {
      return true;
    }
    throw new Error('Transfer to normal contract does not throw');
  }).timeout(6000);

  it('Should be able to transfer ERC223 contract', async () => {
    const recipient = await tr.RecipientERC223.new(web3, { from: accounts[0], gas: 2000000 });
    await yogaToken['send(address,uint256,bytes)'](recipient.$address, 1, '0x01', { from: accounts[1], gas: 400000 });
    const b = await yogaToken.balanceOf(recipient.$address);
    assert.equal(b, 1);
  });

  it('Should NOT be able to transfer ERC223 contract if fallbackToken throws', async () => {
    const recipient = await tr.RecipientERC223.new(web3, { from: accounts[0], gas: 2000000 });
    try {
      await yogaToken['send(address,uint256,bytes)'](recipient.$address, 1, '0x00', { from: accounts[1], gas: 400000 });
    } catch (e) {
      return true;
    }
    throw new Error('Transfer to ERC223 contract thet tokenFallback trows does not throw');
  });

  it('Should be able to transfer to normal account', async () => {
    await yogaToken['send(address,uint256,bytes)'](accounts[2], 1, '0x01', { from: accounts[1], gas: 400000 });
    const b = await yogaToken.balanceOf(accounts[2]);
    assert.equal(b, 1);
  });

  it('Should not be able to transfer to normal account with proxyReject', async () => {
    const proxy = await tr.ProxyReject.new(web3, { from: accounts[0], gas: 2000000 });

    await ensSimulator.setProxyInterface(ens, accounts[3], 'ITokenFallback', proxy.$address);
    try {
      await yogaToken['send(address,uint256)'](accounts[3], 1, { from: accounts[1], gas: 400000 });
    } catch (e) {
      return true;
    }
    throw new Error('Transfer to proxyReject normal account does not throw');
  });

  it('Should be able to transfer to normal account with proxyAccept', async () => {
    const proxy = await tr.ProxyAccept.new(web3, { from: accounts[0], gas: 2000000 });

    await ensSimulator.setProxyInterface(ens, accounts[3], 'ITokenFallback', proxy.$address);
    await yogaToken['send(address,uint256)'](accounts[3], 1, { from: accounts[1], gas: 400000 });
    const b = await yogaToken.balanceOf(accounts[3]);
    assert.equal(b, 1);
  });
});
