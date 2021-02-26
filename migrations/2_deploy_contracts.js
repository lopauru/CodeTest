const GhostToken = artifacts.require("GhostToken");
const GhostTalons = artifacts.require("GhostTalons");
const GhostFarmContract = artifacts.require("GhostFarmContract");

module.exports = async function (deployer,_network,addresses) {
    const [admin, _] = addresses;
    
      await deployer.deploy(GhostToken);
      const ghostToken = await GhostToken.deployed();

      await deployer.deploy(
        GhostTalons, // CONTRACT
        admin, //GhostToken _Ghost,
      );
    const ghostTalons = await GhostTalons.deployed();

    await deployer.deploy(
        GhostFarmContract, // CONTRACT
        admin, //GhostToken _Ghost,
        ghostTalons.address, // GhostTalons _talons,
        admin, //address _devAddr,
        1, //uint256 _GhostStartBlock,
        1, //uint256 _startBlock,
        4, //uint256 _bonusEndBlock,
        4, //uint256 _bonusEndBulkBlockSize,
        4, //uint256 _bonusBeforeBulkBlockSize,
        4, //int256 _bonusBeforeCommonDifference,
        10, //uint256 _bonusEndCommonDifference,
        100, //uint256 _GhostBonusEndBlock,
        100, //uint256 _maxRewardBlockNumber
      );
};
