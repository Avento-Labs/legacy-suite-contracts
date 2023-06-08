require("dotenv").config("../.env");
const { ethers } = require("hardhat");

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function main() {
  const [admin, authorizer, owner, _] = await ethers.getSigners();
  try {
    const [admin, authorizer, owner, wallet1, wallet2, wallet3, _] =
      await ethers.getSigners();

    const LegacyAssetManagerFactory = await ethers.getContractFactory(
      "contracts/main/LegacyAssetManager.sol:LegacyAssetManager",
      admin
    );
    const LegacyVaultFactoryArtifact = await ethers.getContractFactory(
      "contracts/main/LegacyVaultFactory.sol:LegacyVaultFactory",
      admin
    );

    const LegacyAssetManager = await (
      await LegacyAssetManagerFactory.deploy(3)
    ).deployed();

    await sleep(5000);
    console.log("LegacyAssetManager: " + LegacyAssetManager.address);

    const LegacyVaultFactory = await LegacyVaultFactoryArtifact.deploy(
      LegacyAssetManager.address,
      5
    );
    await LegacyVaultFactory.deployed();

    await sleep(5000);
    console.log("LegacyVaultFactory: " + LegacyVaultFactory.address);

    await LegacyAssetManager.grantRole(
      LegacyAssetManager.ASSET_AUTHORIZER(),
      authorizer.address
    );
    await sleep(5000);

    await LegacyAssetManager.setVaultFactory(LegacyVaultFactory.address);
    await sleep(5000);

    await LegacyVaultFactory.grantRole(
      await LegacyVaultFactory.ADMIN_ROLE(),
      LegacyAssetManager.address
    );
    await sleep(5000);

    await LegacyVaultFactory.grantRole(
      await LegacyVaultFactory.ADMIN_ROLE(),
      admin.address
    );
    await sleep(5000);

    await sleep(5000);
  } catch (error) {
    console.log(error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
