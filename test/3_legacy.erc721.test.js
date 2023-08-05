const { expect } = require("chai");
const c = require("config");
const { ethers } = require("hardhat");

async function deploy() {
  const [
    admin,
    authorizer,
    owner,
    beneficiary,
    beneficiary1,
    beneficiary2,
    beneficiary3,
    beneficiary4,
    beneficiary5,
    wallet1,
    wallet2,
    wallet3,
    _,
  ] = await ethers.getSigners();

  const ERC721 = await (
    await ethers.getContractFactory("ERC721Mock", admin)
  ).deploy();

  const LegacyAssetManagerFactory = await ethers.getContractFactory(
    "contracts/main/LegacyAssetManager.sol:LegacyAssetManager",
    admin
  );
  const LegacyVaultFactoryArtifact = await ethers.getContractFactory(
    "contracts/main/LegacyVaultFactory.sol:LegacyVaultFactory",
    admin
  );
  const LegacyVaultArtifact = await ethers.getContractFactory(
    "contracts/main/LegacyVault.sol:LegacyVault",
    admin
  );

  const LegacyAssetManager = await (
    await LegacyAssetManagerFactory.deploy(1)
  ).deployed();
  const LegacyVaultFactory = await (
    await LegacyVaultFactoryArtifact.deploy(LegacyAssetManager.address, 5)
  ).deployed();
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
  const beneficiaryAssetManager = LegacyAssetManagerFactory.connect(
    beneficiary
  ).attach(LegacyAssetManager.address);
  const wallets = [wallet1.address, wallet2.address, wallet3.address];
  const userId = ethers.utils.hashMessage(owner.address);
  const nonce = ethers.BigNumber.from(ethers.utils.randomBytes(16)).toString();
  const hashedMessage = ethers.utils.arrayify(
    ethers.utils.solidityKeccak256(
      ["address", "uint256"],
      [owner.address, nonce]
    )
  );
  const signature = await authorizer.signMessage(hashedMessage);
  await ownerAssetManager.createUserVault(userId, nonce, signature);
  const ownerVaultAddress = await LegacyVaultFactory.getVault(owner.address);

  const ownerERC721 = await (
    await ethers.getContractFactory("ERC721Mock", admin)
  )
    .connect(owner)
    .attach(ERC721.address);

  for (let i = 1; i <= 10; i++) {
    await ERC721.mint(owner.address, i);
  }
  await ownerERC721.setApprovalForAll(ownerVaultAddress, true);

  return {
    admin,
    authorizer,
    owner,
    LegacyAssetManager,
    LegacyVaultFactory,
    ownerAssetManager,
    ownerVaultAddress,
    beneficiaryAssetManager,
    ERC721,
    ownerERC721,
    beneficiary,
    beneficiary1,
    beneficiary2,
    beneficiary3,
    beneficiary4,
    beneficiary5,
  };
}

describe("LegacyAssetManager - ERC721 Assets", async function () {
  context("Add ERC721 Assets", async function () {
    it("Should add single ERC721 asset", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        ERC721,
        beneficiary,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await expect(
        ownerAssetManager.addAssets(
          userId,
          [ERC721.address],
          [1],
          [0],
          [[beneficiary.address]],
          [[100]]
        )
      )
        .to.emit(ownerAssetManager, "AssetAdded")
        .withArgs(
          userId,
          owner.address,
          ERC721.address,
          1,
          0,
          [beneficiary.address],
          [100]
        );
    });
    it("Should fail to add single ERC721 asset twice", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        ERC721,
        beneficiary,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.addAssets(
          userId,
          [ERC721.address],
          [1],
          [0],
          [[beneficiary.address]],
          [[100]]
        )

      await expect(
        ownerAssetManager.addAssets(
          userId,
          [ERC721.address],
          [1],
          [0],
          [[beneficiary.address]],
          [[100]]
        )
      ).to.revertedWith("LegacyAssetManager: Asset is already listed");
    });
    it("Should fail to add single ERC721 asset by non-owner", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        ERC721,
        beneficiary,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ERC721.mint(beneficiary.address, 11);

      await expect(
        ownerAssetManager.addAssets(
          userId,
          [ERC721.address],
          [1],
          [0],
          [[beneficiary.address]],
          [[100]]
        )
      ).to.revertedWith("LegacyAssetManager: Caller is not the token owner");
    });
    it("Should fail to add single ERC721 that is not approved", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        ownerERC721,
        ownerVaultAddress,
        ERC721,
        beneficiary,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ownerERC721.setApprovalForAll(ownerVaultAddress, false);
      await ERC721.mint(owner.address, 11);

      await expect(
        ownerAssetManager.addAssets(
          userId,
          [ERC721.address],
          [1],
          [0],
          [[beneficiary.address]],
          [[100]]
        )
      ).to.revertedWith("LegacyAssetManager: Asset not approved");
    });
  });

  context("Claim ERC721 Assets", async function () {
    it("Should claim single ERC721 Asset", async function () {
      const {
        admin,
        authorizer,
        owner,
        ERC721,
        beneficiary,
        ownerAssetManager,
        beneficiaryAssetManager,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const addSignature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.addAssets(
        userId,
        [ERC721.address],
        [1],
        [0],
        [[beneficiary.address]],
        [[100]]
      );

      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC721.address, 1, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);

      await expect(
        beneficiaryAssetManager.claimAsset(
          userId,
          owner.address,
          ERC721.address,
          1,
          nonce + 1,
          [claimSignature]
        )
      )
        .to.emit(beneficiaryAssetManager, "AssetClaimed") // transfer from minter to redeemer
        .withArgs(
          userId,
          owner.address,
          beneficiary.address,
          ERC721.address,
          1,
          0,
          [admin.address]
        );
      expect(await ERC721.ownerOf(1)).to.be.equals(beneficiary.address);
    });
    it("Should fail to claim single ERC721 Asset twice", async function () {
      const {
        admin,
        authorizer,
        owner,
        ERC721,
        beneficiary,
        ownerAssetManager,
        beneficiaryAssetManager,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const addSignature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.addAssets(
          userId,
          [ERC721.address],
          [1],
          [0],
          [[beneficiary.address]],
          [[100]]
        );

      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC721.address, 1, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);

      await beneficiaryAssetManager.claimAsset(
        userId,
        owner.address,
        ERC721.address,
        1,
        nonce + 1,
        [claimSignature]
      );
      
      const claimHashedMessage1 = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC721.address, 1, nonce + 2]
          )
          );
      const claimSignature1 = await admin.signMessage(claimHashedMessage1);
      await expect(
        beneficiaryAssetManager.claimAsset(
          userId,
          owner.address,
          ERC721.address,
          1,
          nonce + 2,
          [claimSignature1]
        )
      ).to.be.revertedWith(
        "LegacyAssetManager: Beneficiary has already claimed the asset"
      );
    });
    it("Should fail to claim single ERC721 by non beneficiary", async function () {
      const {
        admin,
        authorizer,
        owner,
        ERC721,
        beneficiary,
        ownerAssetManager,
        beneficiaryAssetManager,
        beneficiary1,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const addSignature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.addAssets(
        userId,
        [ERC721.address],
        [1],
        [0],
        [[beneficiary.address]],
        [[100]]
      );

      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC721.address, 1, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);

      await expect(
        beneficiaryAssetManager.claimAsset(
          userId,
          owner.address,
          ERC721.address,
          1,
          nonce + 1,
          [claimSignature]
        )
      ).to.be.revertedWith("LegacyAssetManager: Unauthorized claim call");
    });
    it("Should fail to claim single ERC721 when the owner has been changed", async function () {
      const {
        admin,
        authorizer,
        owner,
        ownerERC721,
        ERC721,
        ownerAssetManager,
        beneficiary,
        beneficiaryAssetManager,
        beneficiary1,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const addSignature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.addAssets(
        userId,
        [ERC721.address],
        [1],
        [0],
        [[beneficiary.address]],
        [[100]]
      );

      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC721.address, 1, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);
      await ownerERC721.transferFrom(owner.address, beneficiary1.address, 1);

      await expect(
        beneficiaryAssetManager.claimAsset(
          userId,
          owner.address,
          ERC721.address,
          1,
          nonce + 1,
          [claimSignature]
        )
      ).to.be.revertedWith("ERC721: transfer caller is not owner nor approved");
    });
  });

  context("Remove ERC721 Assets", async function () {
    it("Should remove single ERC721 Asset with valid params", async function () {
      const {
        admin,
        authorizer,
        owner,
        ERC721,
        beneficiary,
        ownerAssetManager,
        beneficiaryAssetManager,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const addSignature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.addAssets(
        userId,
        [ERC721.address],
        [1],
        [0],
        [[beneficiary.address]],
        [[100]]
      );

      await expect(
        ownerAssetManager.removeAsset(userId, ERC721.address, 1)
      )
        .to.emit(ownerAssetManager, "AssetRemoved")
        .withArgs(userId, owner.address, ERC721.address, 1);
    });
    it("Should fail to remove single ERC721 Asset when the asset has been transferred to the beneficiary", async function () {
      const {
        admin,
        authorizer,
        owner,
        ERC721,
        beneficiary,
        ownerAssetManager,
        beneficiaryAssetManager,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const addSignature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.addAssets(
        userId,
        [ERC721.address],
        [1],
        [0],
        [[beneficiary.address]],
        [[100]]
      );

      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC721.address, 1, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);

      await beneficiaryAssetManager.claimAsset(
        userId,
        owner.address,
        ERC721.address,
        1,
        nonce + 1,
        [claimSignature]
      );

      await expect(
        ownerAssetManager.removeAsset(userId, ERC721.address, 1)
      ).to.be.revertedWith(
        "LegacyAssetManager: Asset has been transferred to the beneficiary"
      );
    });
    it("Should remove non-listed ERC721 Asset", async function () {
      const {
        admin,
        authorizer,
        owner,
        ERC721,
        beneficiary,
        ownerAssetManager,
        beneficiaryAssetManager,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const addSignature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.addAssets(
        userId,
        [ERC721.address],
        [1],
        [0],
        [[beneficiary.address]],
        [[100]]
      );

      await expect(
        ownerAssetManager.removeAsset(userId, ERC721.address, 2)
      ).to.be.revertedWith("LegacyAssetManager: Asset not found");
    });
  });

  context("Change ERC721 Asset Beneficiary", async () => {
    it("Should change the Asset beneficiary for ERC721 Asset", async () => {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        ERC721,
        beneficiary,
        beneficiary1,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.addAssets(
        userId,
        [ERC721.address],
        [1],
        [0],
        [[beneficiary.address]],
        [[100]]
      );
      await expect(
        ownerAssetManager.setERC721Beneficiary(
          userId,
          ERC721.address,
          1,
          beneficiary1.address
        )
      )
        .to.emit(ownerAssetManager, "BeneficiaryChanged")
        .withArgs(
          userId,
          owner.address,
          ERC721.address,
          1,
          beneficiary1.address
        );
    });
    it("Should fail to change the Asset beneficiary for ERC721 Asset when asset has been transferred", async () => {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        beneficiaryAssetManager,
        ERC721,
        beneficiary,
        beneficiary1,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      const hashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["string", "address", "uint256"],
          [userId, owner.address, nonce]
        )
      );
      const signature = await authorizer.signMessage(hashedMessage);
      await ownerAssetManager.addAssets(
        userId,
        [ERC721.address],
        [1],
        [0],
        [[beneficiary.address]],
        [[100]]
      );
      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC721.address, 1, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);
      await beneficiaryAssetManager.claimAsset(
        userId,
        owner.address,
        ERC721.address,
        1,
        nonce + 1,
        [claimSignature]
      );
      await expect(
        ownerAssetManager.setERC721Beneficiary(
          userId,
          ERC721.address,
          1,
          beneficiary1.address
        )
      ).to.be.revertedWith("LegacyAssetManager: Asset has been claimed");
    });
  });
});
