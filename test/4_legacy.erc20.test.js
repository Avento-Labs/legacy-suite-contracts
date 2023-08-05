const { expect } = require("chai");
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
    backupWallet,
    wallet1,
    wallet2,
    wallet3,
    _,
  ] = await ethers.getSigners();

  const ERC20 = await (
    await ethers.getContractFactory("ERC20Mock", admin)
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
  const ownerERC20 = await (await ethers.getContractFactory("ERC20Mock", admin))
    .connect(owner)
    .attach(ERC20.address);
  const beneficiaryERC20 = await (
    await ethers.getContractFactory("ERC20Mock", admin)
  )
    .connect(beneficiary)
    .attach(ERC20.address);

  await ERC20.transfer(owner.address, ethers.utils.parseEther("100"));

  return {
    admin,
    authorizer,
    owner,
    LegacyAssetManager,
    LegacyVaultFactory,
    ownerAssetManager,
    ownerVaultAddress,
    ownerVaultAddress,
    beneficiaryAssetManager,
    ERC20,
    ownerERC20,
    beneficiaryERC20,
    beneficiary,
    beneficiary1,
    beneficiary2,
    beneficiary3,
    beneficiary4,
    beneficiary5,
  };
}

describe("LegacyAssetManager - ERC20 Assets", async function () {
  context("Add ERC20 Assets", async () => {
    it("Should add single ERC20 asset", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        ownerERC20,
        beneficiary1,
        beneficiary2,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther("100");
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      const beneficiaries = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 33, 34];
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
          [ERC20.address],
          [0],
          [0],
          [beneficiaries],
          [percentages]
        )
      )
        .to.emit(ownerAssetManager, "AssetAdded")
        .withArgs(
          userId,
          owner.address,
          ERC20.address,
          0,
          amount,
          beneficiaries,
          percentages
        );
    });
    it("Should fail to add single ERC20 asset when asset amount exceeds balance", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        beneficiary1,
        beneficiary2,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther(
        (await ERC20.balanceOf(owner.address)) + 100
      );
      const beneficiaries = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 33, 34];
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
          [ERC20.address],
          [0],
          [0],
          [beneficiaries],
          [percentages]
        )
      ).to.be.revertedWith(
        "LegacyAssetManager: Insufficient allowance for the asset"
      );
    });
    // it("Should fail to add single ERC20 asset when the allowance is insufficient", async () => {
    //     const {
    //         admin,
    //         authorizer,
    //         owner,
    //         beneficiary,
    //         ownerAssetManager,
    //         ownerVaultAddress,
    //         ERC20,
    //         ownerVaultAddress,
    //         ownerERC20,
    //         beneficiary1,
    //         beneficiary2,
    //     } = await deploy();
    //     const userId = ethers.utils.hashMessage(owner.address);
    //     const amount = ethers.utils.parseEther("101");
    //     await ownerERC20.approve(
    //         ownerVaultAddress,
    //         ethers.utils.parseEther("100")
    //     );
    //     const beneficiaries = [
    //         beneficiary.address,
    //         beneficiary1.address,
    //         beneficiary2.address,
    //     ];
    //     const percentages = [33, 33, 34];
    //     const message = ethers.BigNumber.from(
    //         ethers.utils.randomBytes(4)
    //     ).toString();
    //     const hashedMessage = ethers.utils.arrayify(
    //         ethers.utils.hashMessage(message)
    //     );
    //     const signature = await authorizer.signMessage(hashedMessage);
    //     await expect(
    //         ownerAssetManager.addERC20Assets(
    //             userId,
    //             [ERC20.address],
    //
    //             [beneficiaries],
    //             [percentages],
    //             hashedMessage,
    //             signature
    //         )
    //     ).to.be.revertedWith(
    //         "LegacyAssetManager: Asset allowance is insufficient"
    //     );
    // });
    it("Should fail to add single ERC20 asset when percentages exceed 100", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        ownerERC20,
        beneficiary1,
        beneficiary2,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther("100");
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      const beneficiaries = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 34, 34];
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
          [ERC20.address],
          [0],
          [0],
          [beneficiaries],
          [percentages]
        )
      ).to.be.revertedWith(
        "LegacyAssetManager: Beneficiary percentages exceed 100"
      );
    });
  });

  context("Claim ERC20 Assets", async () => {
    it("Should claim single ERC20 asset", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        ownerERC20,
        beneficiaryAssetManager,
        beneficiary1,
        beneficiary2,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther("100");
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      const beneficiaries = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 33, 34];
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
        [ERC20.address],
        [0],
        [0],
        [beneficiaries],
        [percentages]
      );
      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC20.address, 0, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);
      await expect(
        beneficiaryAssetManager.claimAsset(
          userId,
          owner.address,
          ERC20.address,
          0,
          nonce + 1,
          [claimSignature]
        )
      )
        .to.emit(beneficiaryAssetManager, "AssetClaimed")
        .withArgs(
          userId,
          owner.address,
          beneficiary.address,
          ERC20.address,
          0,
          ethers.utils.parseEther("33"),
          [admin.address]
        );
    });
    it("Should reclaim single ERC20 asset", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        ownerERC20,
        beneficiaryERC20,
        beneficiaryAssetManager,
        beneficiary1,
        beneficiary2,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther("100");
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      const beneficiaries = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 33, 34];
      const nonce = ethers.BigNumber.from(
        ethers.utils.randomBytes(4)
      ).toString();
      await ownerAssetManager.addAssets(
        userId,
        [ERC20.address],
        [0],
        [0],
        [beneficiaries],
        [percentages]
      );
      await ownerERC20.transfer(
        beneficiary.address,
        ethers.utils.parseEther("70")
      );

      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC20.address, 0, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);

      await expect(
        beneficiaryAssetManager.claimAsset(
          userId,
          owner.address,
          ERC20.address,
          0,
          nonce + 1,
          [claimSignature]
        )
      )
        .to.emit(beneficiaryAssetManager, "AssetClaimed")
        .withArgs(
          userId,
          owner.address,
          beneficiary.address,
          ERC20.address,
          0,
          ethers.utils.parseEther("9.9"),
          [admin.address]
        );

      await beneficiaryERC20.transfer(
        owner.address,
        ethers.utils.parseEther("70")
      );

      const claimHashedMessage1 = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC20.address, 0, nonce + 2]
        )
      );
      const claimSignature1 = await admin.signMessage(claimHashedMessage1);

      await expect(
        beneficiaryAssetManager.claimAsset(
          userId,
          owner.address,
          ERC20.address,
          0,
          nonce + 2,
          [claimSignature1]
        )
      )
        .to.emit(beneficiaryAssetManager, "AssetClaimed")
        .withArgs(
          userId,
          owner.address,
          beneficiary.address,
          ERC20.address,
          0,
          ethers.utils.parseEther("23.1"),
          [admin.address]
        );
    });
    it("Should fail to claim single ERC20 asset twice", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        ownerERC20,
        beneficiaryAssetManager,
        beneficiary1,
        beneficiary2,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther("100");
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      const beneficiaries = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 33, 34];
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
        [ERC20.address],
        [0],
        [0],
        [beneficiaries],
        [percentages]
      );
      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC20.address, 0, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);
      await beneficiaryAssetManager.claimAsset(
        userId,
        owner.address,
        ERC20.address,
        0,
        nonce + 1,
        [claimSignature]
      );
      const claimHashedMessage1 = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC20.address, 0, nonce + 2]
        )
      );
      const claimSignature1 = await admin.signMessage(claimHashedMessage1);
      await expect(
        beneficiaryAssetManager.claimAsset(
          userId,
          owner.address,
          ERC20.address,
          0,
          nonce + 2,
          [claimSignature1]
        )
      ).to.be.revertedWith(
        "LegacyAssetManager: Beneficiary has already claimed the asset"
      );
    });
    it("Should fail to claim single ERC20 asset by non beneficiary", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        ownerERC20,
        beneficiaryAssetManager,
        beneficiary1,
        beneficiary2,
        beneficiary3,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther("100");
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      const beneficiaries = [
        beneficiary1.address,
        beneficiary2.address,
        beneficiary3.address,
      ];
      const percentages = [33, 33, 34];
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
        [ERC20.address],
        [0],
        [0],
        [beneficiaries],
        [percentages]
      );
      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC20.address, 0, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);
      await expect(
        beneficiaryAssetManager.claimAsset(
          userId,
          owner.address,
          ERC20.address,
          0,
          nonce + 1,
          [claimSignature]
        )
      ).to.be.revertedWith("LegacyAssetManager: Beneficiary not found");
    });
    it("Should fail to claim single ERC20 asset when owner has zero balance or zero allowance for this asset", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        ownerERC20,
        beneficiaryAssetManager,
        beneficiary1,
        beneficiary2,
        beneficiary3,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther("100");
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      const beneficiaries = [
        beneficiary.address,
        beneficiary2.address,
        beneficiary3.address,
      ];
      const percentages = [33, 33, 34];
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
        [ERC20.address],
        [0],
        [0],
        [beneficiaries],
        [percentages]
      );
      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC20.address, 0, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);
      await ownerERC20.transfer(
        beneficiary3.address,
        await ownerERC20.balanceOf(owner.address)
      );
      await expect(
        beneficiaryAssetManager.claimAsset(
          userId,
          owner.address,
          ERC20.address,
          0,
          nonce + 1,
          [claimSignature]
        )
      ).to.be.revertedWith(
        "LegacyAssetManager: Owner has zero balance or zero allowance for this asset"
      );
    });
  });

  context("Change ERC20 Asset beneficiary percentages", async () => {
    it("Should change the percentages for ERC20 Asset beneficiary", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        ownerERC20,
        beneficiaryAssetManager,
        beneficiary1,
        beneficiary2,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther("100");
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      const beneficiaries = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 33, 34];
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
        [ERC20.address],
        [0],
        [0],
        [beneficiaries],
        [percentages]
      );
      await expect(
        ownerAssetManager.setBeneficiaryPercentage(
          userId,
          ERC20.address,
          0,
          beneficiary.address,
          30
        )
      )
        .to.emit(ownerAssetManager, "BeneficiaryPercentageChanged")
        .withArgs(
          userId,
          owner.address,
          ERC20.address,
          0,
          beneficiary.address,
          30
        );
    });
    it("Should fail to change the percentages for ERC20 Asset beneficiary when percentage exceeds 100", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        ownerERC20,
        beneficiaryAssetManager,
        beneficiary1,
        beneficiary2,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther("100");
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      const beneficiaries = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 33, 34];
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
        [ERC20.address],
        [0],
        [0],
        [beneficiaries],
        [percentages]
      );
      await expect(
        ownerAssetManager.setBeneficiaryPercentage(
          userId,
          ERC20.address,
          0,
          beneficiary.address,
          34
        )
      ).to.be.revertedWith(
        "LegacyAssetManager: Beneficiary percentage exceeds total of 100"
      );
    });
    it("Should fail to change the percentages for beneficiary when asset has been claimed", async () => {
      const {
        admin,
        authorizer,
        owner,
        beneficiary,
        ownerAssetManager,
        ownerVaultAddress,
        ERC20,
        ownerERC20,
        beneficiaryAssetManager,
        beneficiary1,
        beneficiary2,
      } = await deploy();
      const userId = ethers.utils.hashMessage(owner.address);
      const amount = ethers.utils.parseEther("100");
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      const beneficiaries = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 33, 34];
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
        [ERC20.address],
        [0],
        [0],
        [beneficiaries],
        [percentages]
      );

      const claimHashedMessage = ethers.utils.arrayify(
        ethers.utils.solidityKeccak256(
          ["address", "address", "address", "uint256", "uint256"],
          [owner.address, beneficiary.address, ERC20.address, 0, nonce + 1]
        )
      );
      const claimSignature = await admin.signMessage(claimHashedMessage);
      await beneficiaryAssetManager.claimAsset(
        userId,
        owner.address,
        ERC20.address,
        0,
        nonce + 1,
        [claimSignature]
      );

      await expect(
        ownerAssetManager.setBeneficiaryPercentage(
          userId,
          ERC20.address,
          0,
          beneficiary.address,
          30
        )
      ).to.be.revertedWith(
        "LegacyAssetManager: Beneficiary has already claimed the asset"
      );
    });
  });
});
