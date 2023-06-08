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
    backupWallet1,
    backupWallet2,
    wallet1,
    wallet2,
    wallet3,
    _,
  ] = await ethers.getSigners();

  const ERC1155 = await (
    await ethers.getContractFactory("ERC1155Mock", admin)
  ).deploy();
  const ERC721 = await (
    await ethers.getContractFactory("ERC721Mock", admin)
  ).deploy();
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
  const backupWalletAssetManager = LegacyAssetManagerFactory.connect(
    backupWallet1
  ).attach(LegacyAssetManager.address);
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
  const ownerERC1155 = await (
    await ethers.getContractFactory("ERC1155Mock", admin)
  )
    .connect(owner)
    .attach(ERC1155.address);
  const ownerERC721 = await (
    await ethers.getContractFactory("ERC721Mock", admin)
  )
    .connect(owner)
    .attach(ERC721.address);
  const ownerERC20 = await (await ethers.getContractFactory("ERC20Mock", admin))
    .connect(owner)
    .attach(ERC20.address);

  await ownerERC1155.mintBatch(
    owner.address,
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    "0x01"
  );
  await ownerERC1155.setApprovalForAll(ownerVaultAddress, true);
  await ERC20.transfer(owner.address, ethers.utils.parseEther("10000"));
  for (let i = 1; i <= 10; i++) {
    await ERC721.mint(owner.address, i);
    await ownerERC721.approve(ownerVaultAddress, i);
  }

  return {
    admin,
    authorizer,
    owner,
    LegacyAssetManager,
    LegacyVaultFactory,
    ownerAssetManager,
    backupWalletAssetManager,
    ownerVaultAddress,
    beneficiaryAssetManager,
    ERC1155,
    ERC721,
    ERC20,
    ownerERC1155,
    ownerERC721,
    ownerERC20,
    beneficiary,
    beneficiary1,
    beneficiary2,
    beneficiary3,
    beneficiary4,
    beneficiary5,
    backupWallet1,
    backupWallet2    
  };
}

describe("LegacyAssetManager - Backup Wallet", async function () {
  context("Add First Backup Wallet", async () => {
    it("Should add first backup wallet for a valid user", async () => {
      const {
        authorizer,
        owner,
        ownerAssetManager,
        ERC1155,
        beneficiary,
        backupWallet1,
      } = await deploy();
      await ownerAssetManager.addBackupWallet("string",0,backupWallet1.address);
      expect(await ownerAssetManager.backupWallets(owner.address,0)).to.be.equals(
        backupWallet1.address
      );
    });
    it("Should fail to add a backup wallet when the user is not listed", async () => {
      const { owner, beneficiaryAssetManager, backupWallet1 } = await deploy();
      await expect(
        beneficiaryAssetManager.addBackupWallet("string",0,backupWallet1.address)
      ).to.be.revertedWith("LegacyAssetManager: User not listed");
    });
  });
    context("Add second Backup Wallet", async () => {
      it("Should add second backup wallet for a valid user", async () => {
        const {
          authorizer,
          owner,
          ownerAssetManager,
          ERC1155,
          beneficiary,
          backupWallet1,
          backupWallet2
        } = await deploy();
        await ownerAssetManager.addBackupWallet("string",1,backupWallet2.address);
        console.log(await ownerAssetManager.backupWallets(owner.address,1));
        expect(await ownerAssetManager.backupWallets(owner.address,1)).to.be.equals(
          backupWallet2.address
        );
      });
      it("Should fail to add a backup wallet when the user is not listed", async () => {
        const { owner, beneficiaryAssetManager, backupWallet1 } = await deploy();
        await expect(
          beneficiaryAssetManager.addBackupWallet("string",1,backupWallet1.address)
        ).to.be.revertedWith("LegacyAssetManager: User not listed");
      });
      
  });

  context("Switch Backup Wallet", async () => {
    it("Should switch to backup wallet", async () => {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        backupWalletAssetManager,
        ERC1155,
        ERC721,
        ERC20,
        ownerERC20,
        ownerVaultAddress,
        beneficiary,
        beneficiary1,
        beneficiary2,
        beneficiary3,
        beneficiary4,
        backupWallet1
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
      await ownerAssetManager.addERC1155Assets(
        userId,
        [ERC1155.address],
        [1],
        [1],
        [[beneficiary.address]],
        [[100]]
      );
      await ownerAssetManager.addERC721Assets(
        userId,
        [
          ERC721.address,
          ERC721.address,
          ERC721.address,
          ERC721.address,
          ERC721.address,
        ],
        [1, 2, 3, 4, 5],
        [
          beneficiary.address,
          beneficiary1.address,
          beneficiary2.address,
          beneficiary3.address,
          beneficiary4.address,
        ]
      );
      const beneficiaires = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 33, 34];
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      await ownerAssetManager.addERC20Assets(
        userId,
        [ERC20.address],
        [beneficiaires],
        [percentages]
      );

      await ownerAssetManager.addBackupWallet("string",0,backupWallet1.address);
      await expect(
        backupWalletAssetManager.switchBackupWallet(userId, owner.address)
      ).to.emit(backupWalletAssetManager, "BackupWalletSwitched");
    backupWalletAssetManager.switchBackupWallet(userId, owner.address);
  });
    it("Should fail to swith backup wallet when called by non backup wallet", async () => {
      const {
        admin,
        authorizer,
        owner,
        ownerAssetManager,
        backupWalletAssetManager,
        ERC1155,
        ERC721,
        ERC20,
        ownerERC20,
        ownerVaultAddress,
        beneficiary,
        beneficiary1,
        beneficiary2,
        beneficiary3,
        beneficiary4,
        backupWallet1
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
      await ownerAssetManager.addERC1155Assets(
        userId,
        [ERC1155.address],
        [1],
        [1],
        [[beneficiary.address]],
        [[100]]
      );
      await ownerAssetManager.addERC721Assets(
        userId,
        [
          ERC721.address,
          ERC721.address,
          ERC721.address,
          ERC721.address,
          ERC721.address,
        ],
        [1, 2, 3, 4, 5],
        [
          beneficiary.address,
          beneficiary1.address,
          beneficiary2.address,
          beneficiary3.address,
          beneficiary4.address,
        ]
      );
      const beneficiaires = [
        beneficiary.address,
        beneficiary1.address,
        beneficiary2.address,
      ];
      const percentages = [33, 33, 34];
      await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100")
      );
      await ownerAssetManager.addERC20Assets(
        userId,
        [ERC20.address],
        [beneficiaires],
        [percentages]
      );

      await ownerAssetManager.addBackupWallet("string",0,backupWallet1.address);
      await expect(
        ownerAssetManager.switchBackupWallet(userId, owner.address)
      ).to.be.revertedWith(
        "LegacyAssetManager: Unauthorized backup wallet transfer call"
      );
    });
  });
});
