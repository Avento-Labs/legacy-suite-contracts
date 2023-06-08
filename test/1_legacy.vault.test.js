const { expect } = require("chai");
const { ethers } = require("hardhat");

async function deploy() {
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
    await LegacyAssetManagerFactory.deploy(1)
  ).deployed();
  const LegacyVaultFactory = await LegacyVaultFactoryArtifact.deploy(
    LegacyAssetManager.address,
    5
  );
  await LegacyVaultFactory.deployed();

  await LegacyAssetManager.grantRole(
    LegacyAssetManager.ASSET_AUTHORIZER(),
    authorizer.address
  );
  await LegacyAssetManager.setVaultFactory(LegacyVaultFactory.address);
  await LegacyVaultFactory.grantRole(
    await LegacyVaultFactory.ADMIN_ROLE(),
    LegacyAssetManager.address
  );
  await LegacyVaultFactory.grantRole(
    await LegacyVaultFactory.ADMIN_ROLE(),
    admin.address
  );
  await LegacyVaultFactory.setLegacyAssetManagerAddress(
    LegacyAssetManager.address
  );

  const ownerAssetManager = LegacyAssetManagerFactory.connect(owner).attach(
    LegacyAssetManager.address
  );
  const ownerVaultFactory = LegacyVaultFactoryArtifact.connect(owner).attach(
    LegacyVaultFactory.address
  );
  const wallet1VaultFactory = LegacyVaultFactoryArtifact.connect(
    wallet1
  ).attach(LegacyVaultFactory.address);
  const wallet2VaultFactory = LegacyVaultFactoryArtifact.connect(
    wallet2
  ).attach(LegacyVaultFactory.address);
  const wallet3VaultFactory = LegacyVaultFactoryArtifact.connect(
    wallet3
  ).attach(LegacyVaultFactory.address);

  return {
    admin,
    authorizer,
    owner,
    LegacyAssetManager,
    LegacyVaultFactory,
    ownerAssetManager,
    ownerVaultFactory,
    wallet1,
    wallet2,
    wallet3,
    wallet1VaultFactory,
    wallet2VaultFactory,
    wallet3VaultFactory,
  };
}

describe("LegacyAssetManager - vault", async function () {
  context("Create & Get User Vault", async function () {
    it("Should create a User vault with valid params", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        LegacyVaultFactory,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(16)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "uint256"],
          [owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      console.log(await LegacyVaultFactory.createVault('lora', owner.address));
      console.log(await LegacyVaultFactory.getVault(owner.address));
      // await expect(ownerAssetManager.createUserVault(userId, nonce, signature))
      //   .to.emit(LegacyVaultFactory, "UserVaultCreated")
      //   .withArgs(
      //     userId,
      //     owner.address,
      //     await LegacyVaultFactory.getVault(owner.address)
      //   );
    });
    it("Should add multiple wallets to same vault", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        LegacyVaultFactory,
        wallet1,
        wallet2,
        wallet3,
        wallet1VaultFactory,
        wallet2VaultFactory,
        wallet3VaultFactory,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(16)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "uint256"],
          [owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.createUserVault(userId, nonce, signature);

      await wallet1VaultFactory.addWallet(userId, owner.address);
      await wallet2VaultFactory.addWallet(userId, owner.address);
      await wallet3VaultFactory.addWallet(userId, owner.address);
      expect(await LegacyVaultFactory.getVault(wallet1.address)).to.be.equals(
        await LegacyVaultFactory.getVault(owner.address)
      );
      expect(await LegacyVaultFactory.getVault(wallet2.address)).to.be.equals(
        await LegacyVaultFactory.getVault(owner.address)
      );
      expect(await LegacyVaultFactory.getVault(wallet3.address)).to.be.equals(
        await LegacyVaultFactory.getVault(owner.address)
      );
    });
    it("Should retrieve same vault from different listed addresses", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        LegacyVaultFactory,
        wallet1,
        wallet2,
        wallet3,
        wallet1VaultFactory,
        wallet2VaultFactory,
        wallet3VaultFactory,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(16)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "uint256"],
          [owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.createUserVault(userId, nonce, signature);

      await wallet1VaultFactory.addWallet(userId, owner.address);
      await wallet2VaultFactory.addWallet(userId, owner.address);
      await wallet3VaultFactory.addWallet(userId, owner.address);
      expect(await LegacyVaultFactory.getVault(wallet1.address)).to.be.equals(
        await LegacyVaultFactory.getVault(owner.address)
      );
      expect(await LegacyVaultFactory.getVault(wallet2.address)).to.be.equals(
        await LegacyVaultFactory.getVault(owner.address)
      );
      expect(await LegacyVaultFactory.getVault(wallet3.address)).to.be.equals(
        await LegacyVaultFactory.getVault(owner.address)
      );
    });
    it("Should fail to retrieve user vault from non listed address", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        LegacyVaultFactory,
        wallet1,
        wallet2,
        wallet3,
        wallet1VaultFactory,
        wallet2VaultFactory,
        wallet3VaultFactory,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(16)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "uint256"],
          [owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.createUserVault(userId, nonce, signature);

      await wallet1VaultFactory.addWallet(userId, owner.address);
      await wallet2VaultFactory.addWallet(userId, owner.address);

      await expect(
        LegacyVaultFactory.getVault(wallet3.address)
      ).to.be.revertedWith("LegacyVaultFactory: User vault not deployed");
    });
  });

  context("Remove Wallets from Listed Wallets", async function () {
    it("Should remove multiple listed wallets when called by the main wallet", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        ownerVaultFactory,
        LegacyVaultFactory,
        wallet1,
        wallet2,
        wallet3,
        wallet1VaultFactory,
        wallet2VaultFactory,
        wallet3VaultFactory,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(16)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "uint256"],
          [owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.createUserVault(userId, nonce, signature);

      await wallet1VaultFactory.addWallet(userId, owner.address);
      await wallet2VaultFactory.addWallet(userId, owner.address);
      await wallet3VaultFactory.addWallet(userId, owner.address);

      await expect(
        ownerVaultFactory.removeWallet(userId, wallet1.address)
      ).to.emit(LegacyVaultFactory, "WalletRemoved");
    });
    it("Should failt to remove listed wallet when called by the other wallet", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        ownerVaultFactory,
        LegacyVaultFactory,
        wallet1,
        wallet2,
        wallet3,
        wallet1VaultFactory,
        wallet2VaultFactory,
        wallet3VaultFactory,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(16)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "uint256"],
          [owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.createUserVault(userId, nonce, signature);

      await wallet1VaultFactory.addWallet(userId, owner.address);
      await wallet2VaultFactory.addWallet(userId, owner.address);
      await wallet3VaultFactory.addWallet(userId, owner.address);

      await expect(
        wallet3VaultFactory.removeWallet(userId, wallet1.address)
      ).to.be.revertedWith("LegacyVaultFactory: User vault not deployed");
    });
    it("Should failt to remove unlisted wallet", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        ownerVaultFactory,
        LegacyVaultFactory,
        wallet1,
        wallet2,
        wallet3,
        wallet1VaultFactory,
        wallet2VaultFactory,
        wallet3VaultFactory,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(16)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "uint256"],
          [owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.createUserVault(userId, nonce, signature);

      await wallet1VaultFactory.addWallet(userId, owner.address);
      await wallet2VaultFactory.addWallet(userId, owner.address);

      await expect(
        ownerVaultFactory.removeWallet(userId, wallet3.address)
      ).to.be.revertedWith("LegacyVaultFactory: Invalid address provided");
    });
  });
});
