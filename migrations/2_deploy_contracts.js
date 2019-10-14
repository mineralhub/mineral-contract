const nftToken = artifacts.require('./token/MineralNFT.sol');
const mineralToken = artifacts.require('./token/Mineral.sol');
const nftMarket = artifacts.require('./MineralNFTMarket.sol');
const fs = require('fs');

module.exports = function(deployer) {
  deployer.deploy(nftToken, "MineralNFT", "FSI").then(() => {
    saveABI(nftToken);
    return deployer.deploy(mineralToken);
  }).then(() => {
    saveABI(mineralToken);
    return deployer.deploy(nftMarket, nftToken.address, mineralToken.address);
  }).then(() => {
    saveABI(nftMarket);
  });
};

function saveABI(contract) {
  if (contract._json) {
    fs.writeFile(
      'deployed/' + contract._json.contractName + '_deployedABI',
      JSON.stringify(contract._json.abi, 2),
      (err) => {
        if (err) throw err
        console.log(`The abi of ${contract._json.contractName} is recorded on deployedABI file`)
      });
  }

  fs.writeFile(
    'deployed/' + contract._json.contractName + '_deployedAddress',
    contract.address,
    (err) => {
      if (err) throw err
      console.log(`The deployed contract address * ${contract.address} * is recorded on deployedAddress file`)
  })
}