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
        "LegacyAssetManager",
        admin
    );
    const LegacyVaultFactoryArtifact = await ethers.getContractFactory(
        "LegacyVaultFactory",
        admin
    );
    const LegacyVaultArtifact = await ethers.getContractFactory(
        "LegacyVault",
        admin
    );

    const LegacyVaultFactory = await LegacyVaultFactoryArtifact.deploy();
    await LegacyVaultFactory.deployed();
    const LegacyAssetManager = await LegacyAssetManagerFactory.deploy(
        LegacyVaultFactory.address,
        1
    );

    await LegacyAssetManager.deployed();
    await LegacyAssetManager.grantRole(
        LegacyAssetManager.ASSET_AUTHORIZER(),
        authorizer.address
    );
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
        backupWallet
    ).attach(LegacyAssetManager.address);
    const beneficiaryAssetManager = LegacyAssetManagerFactory.connect(
        beneficiary
    ).attach(LegacyAssetManager.address);
    await LegacyVaultFactory.createVault(owner.address);
    const ownerVaultAddress =
        await LegacyVaultFactory.deployedContractFromMember(owner.address);
    const ownerVault = LegacyVaultArtifact.attach(ownerVaultAddress);
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
    const ownerERC20 = await (
        await ethers.getContractFactory("ERC20Mock", admin)
    )
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
        await ownerERC721.approve(ownerVault.address, i);
    }

    return {
        admin,
        authorizer,
        owner,
        LegacyAssetManager,
        LegacyVaultFactory,
        ownerAssetManager,
        backupWalletAssetManager,
        ownerVault,
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
        backupWallet,
    };
}

describe("LegacyAssetManager", async function () {
    context("Add ERC1155 Assets", async function () {
        it("Should add single ERC1155 asset", async function () {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                ERC721,
                ERC1155,
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
                ownerAssetManager.addERC1155Assets(
                    userId,
                    [ERC1155.address],
                    [1],
                    [1],
                    [[beneficiary.address]],
                    [[100]],
                    nonce,
                    signature
                )
            )
                .to.emit(ownerAssetManager, "ERC1155AssetAdded")
                .withArgs(
                    userId,
                    owner.address,
                    ERC1155.address,
                    1,
                    1,
                    [beneficiary.address],
                    [100],
                    100
                );
        });
        it("Should fail to add single ERC1155 asset twice", async function () {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                ERC721,
                ERC1155,
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
            await ownerAssetManager.addERC1155Assets(
                userId,
                [ERC1155.address],
                [1],
                [1],
                [[beneficiary.address]],
                [[100]],
                nonce,
                signature
            );
            await expect(
                ownerAssetManager.addERC1155Assets(
                    userId,
                    [ERC1155.address],
                    [1],
                    [1],
                    [[beneficiary.address]],
                    [[100]],
                    nonce,
                    signature
                )
            ).to.be.revertedWith("LegacyAssetManager: Asset already added");
        });
        it("Should fail to add single ERC1155 asset when balance is insufficient", async function () {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                ERC721,
                ERC1155,
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
                ownerAssetManager.addERC1155Assets(
                    userId,
                    [ERC1155.address],
                    [1],
                    [2],
                    [[beneficiary.address]],
                    [[100]],
                    nonce,
                    signature
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Insufficient token balance"
            );
        });
        it("Should fail to add single ERC1155 asset when asset not approved", async function () {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                ownerVault,
                ownerERC1155,
                ERC721,
                ERC1155,
                beneficiary,
            } = await deploy();
            await ownerERC1155.setApprovalForAll(ownerVault.address, false);
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
                ownerAssetManager.addERC1155Assets(
                    userId,
                    [ERC1155.address],
                    [1],
                    [1],
                    [[beneficiary.address]],
                    [[100]],
                    nonce,
                    signature
                )
            ).to.be.revertedWith("LegacyAssetManager: Asset not approved");
        });
    });

    context("Claim ERC1155 Asset", async function () {
        it("Should claim single ERC1155 Asset", async function () {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                ERC1155,
                beneficiary,
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
            await ownerAssetManager.addERC1155Assets(
                userId,
                [ERC1155.address],
                [1],
                [1],
                [[beneficiary.address]],
                [[100]],
                nonce,
                addSignature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC1155.address,
                        1,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);

            await expect(
                beneficiaryAssetManager.claimERC1155Asset(
                    userId,
                    owner.address,
                    ERC1155.address,
                    1,
                    nonce + 1,
                    [claimSignature]
                )
            )
                .to.emit(beneficiaryAssetManager, "ERC1155AssetClaimed") // transfer from minter to redeemer
                .withArgs(
                    userId,
                    owner.address,
                    beneficiary.address,
                    ERC1155.address,
                    1,
                    1,
                    [admin.address]
                );
        });
        it("Should fail to claim single ERC1155 Asset with invalid signature", async function () {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                ERC1155,
                beneficiary,
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
            await ownerAssetManager.addERC1155Assets(
                userId,
                [ERC1155.address],
                [1],
                [1],
                [[beneficiary.address]],
                [[100]],
                nonce,
                addSignature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC1155.address,
                        1,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await owner.signMessage(claimHashedMessage);
            await expect(
                beneficiaryAssetManager.claimERC1155Asset(
                    userId,
                    owner.address,
                    ERC1155.address,
                    1,
                    nonce + 1,
                    [claimSignature]
                )
            ).to.be.revertedWith("LegacyAssetManager: Unauthorized signature");
        });
        it("Should fail to claim single ERC1155 Asset with invalid asset", async function () {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                ERC1155,
                beneficiary,
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
            await ownerAssetManager.addERC1155Assets(
                userId,
                [ERC1155.address],
                [1],
                [1],
                [[beneficiary.address]],
                [[100]],
                nonce,
                addSignature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC1155.address,
                        2,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);
            await expect(
                beneficiaryAssetManager.claimERC1155Asset(
                    userId,
                    owner.address,
                    ERC1155.address,
                    2,
                    nonce + 1,
                    [claimSignature]
                )
            ).to.be.revertedWith("LegacyAssetManager: Asset not found");
        });
        it("Should fail to claim single ERC1155 Asset when beneficiary has already claimed the asset", async function () {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                ERC1155,
                beneficiary,
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
            await ownerAssetManager.addERC1155Assets(
                userId,
                [ERC1155.address],
                [2],
                [1],
                [[beneficiary.address]],
                [[100]],
                nonce,
                addSignature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC1155.address,
                        2,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);
            await beneficiaryAssetManager.claimERC1155Asset(
                userId,
                owner.address,
                ERC1155.address,
                2,
                nonce + 1,
                [claimSignature]
            );
            const claimHashedMessage1 = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC1155.address,
                        2,
                        nonce + 2,
                    ]
                )
            );
            const claimSignature1 = await admin.signMessage(
                claimHashedMessage1
            );
            await expect(
                beneficiaryAssetManager.claimERC1155Asset(
                    userId,
                    owner.address,
                    ERC1155.address,
                    2,
                    nonce + 2,
                    [claimSignature1]
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Beneficiary has already claimed the asset"
            );
        });
        it("Should fail to claim single ERC1155 Asset when owner has zero balance for the asset", async function () {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                ownerERC1155,
                ERC1155,
                beneficiary,
                beneficiary1,
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
            await ownerAssetManager.addERC1155Assets(
                userId,
                [ERC1155.address],
                [1],
                [1],
                [[beneficiary.address]],
                [[100]],
                nonce,
                addSignature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC1155.address,
                        1,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);
            await ownerERC1155.safeTransferFrom(
                owner.address,
                beneficiary1.address,
                1,
                1,
                "0x01"
            );
            await expect(
                beneficiaryAssetManager.claimERC1155Asset(
                    userId,
                    owner.address,
                    ERC1155.address,
                    1,
                    nonce + 1,
                    [claimSignature]
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Owner has zero balance or approval is not set for this asset"
            );
        });
        it("Should fail to claim single ERC1155 Asset with duplicate signature", async function () {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                ownerERC1155,
                ERC1155,
                beneficiary,
                beneficiary1,
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
            await ownerAssetManager.addERC1155Assets(
                userId,
                [ERC1155.address],
                [1],
                [1],
                [[beneficiary.address]],
                [[100]],
                nonce,
                addSignature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC1155.address,
                        1,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature1 = await admin.signMessage(claimHashedMessage);
            const claimSignature2 = await admin.signMessage(claimHashedMessage);
            await ownerERC1155.safeTransferFrom(
                owner.address,
                beneficiary1.address,
                1,
                1,
                "0x01"
            );
            await expect(
                beneficiaryAssetManager.claimERC1155Asset(
                    userId,
                    owner.address,
                    ERC1155.address,
                    1,
                    nonce + 1,
                    [claimSignature1, claimSignature2]
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Duplicate signature not allowed"
            );
        });
    });

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
                ownerAssetManager.addERC721Assets(
                    userId,
                    [ERC721.address],
                    [1],
                    [beneficiary.address],
                    nonce,
                    signature
                )
            )
                .to.emit(ownerAssetManager, "ERC721AssetAdded")
                .withArgs(
                    userId,
                    owner.address,
                    ERC721.address,
                    1,
                    beneficiary.address
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
            await ownerAssetManager.addERC721Assets(
                userId,
                [ERC721.address],
                [1],
                [beneficiary.address],
                nonce,
                signature
            );

            await expect(
                ownerAssetManager.addERC721Assets(
                    userId,
                    [ERC721.address],
                    [1],
                    [beneficiary.address],
                    nonce,
                    signature
                )
            ).to.revertedWith("LegacyAssetManager: Asset already added");
        });
        it("Should fail to add single ERC721 asset more than once", async function () {
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
                ownerAssetManager.addERC721Assets(
                    userId,
                    [ERC721.address],
                    [11],
                    [beneficiary.address],
                    nonce,
                    signature
                )
            ).to.revertedWith(
                "LegacyAssetManager: Caller is not the token owner"
            );
        });
        it("Should fail to add single ERC721 that is not approved", async function () {
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
            await ERC721.mint(owner.address, 11);

            await expect(
                ownerAssetManager.addERC721Assets(
                    userId,
                    [ERC721.address],
                    [11],
                    [beneficiary.address],
                    nonce,
                    signature
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
            await ownerAssetManager.addERC721Assets(
                userId,
                [ERC721.address],
                [1],
                [beneficiary.address],
                nonce,
                addSignature
            );

            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC721.address,
                        1,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);

            await expect(
                beneficiaryAssetManager.claimERC721Asset(
                    userId,
                    owner.address,
                    ERC721.address,
                    1,
                    nonce + 1,
                    [claimSignature]
                )
            )
                .to.emit(beneficiaryAssetManager, "ERC721AssetClaimed") // transfer from minter to redeemer
                .withArgs(
                    userId,
                    owner.address,
                    beneficiary.address,
                    ERC721.address,
                    1,
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
            await ownerAssetManager.addERC721Assets(
                userId,
                [ERC721.address],
                [1],
                [beneficiary.address],
                nonce,
                addSignature
            );

            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC721.address,
                        1,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);

            await beneficiaryAssetManager.claimERC721Asset(
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
                    [
                        owner.address,
                        beneficiary.address,
                        ERC721.address,
                        1,
                        nonce + 2,
                    ]
                )
            );
            const claimSignature1 = await admin.signMessage(
                claimHashedMessage1
            );

            await expect(
                beneficiaryAssetManager.claimERC721Asset(
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
            await ownerAssetManager.addERC721Assets(
                userId,
                [ERC721.address],
                [1],
                [beneficiary1.address],
                nonce,
                addSignature
            );

            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC721.address,
                        1,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);

            await expect(
                beneficiaryAssetManager.claimERC721Asset(
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
            await ownerAssetManager.addERC721Assets(
                userId,
                [ERC721.address],
                [1],
                [beneficiary.address],
                nonce,
                addSignature
            );

            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC721.address,
                        1,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);
            await ownerERC721.transferFrom(
                owner.address,
                beneficiary1.address,
                1
            );

            await expect(
                beneficiaryAssetManager.claimERC721Asset(
                    userId,
                    owner.address,
                    ERC721.address,
                    1,
                    nonce + 1,
                    [claimSignature]
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: The asset does not belong to the owner now"
            );
        });
    });

    context("Add ERC20 Assets", async () => {
        it("Should add single ERC20 asset", async () => {
            const {
                admin,
                authorizer,
                owner,
                beneficiary,
                ownerAssetManager,
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiary1,
                beneficiary2,
            } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            const amount = ethers.utils.parseEther("100");
            await ownerERC20.approve(
                ownerVault.address,
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
                ownerAssetManager.addERC20Assets(
                    userId,
                    [ERC20.address],
                    [amount],
                    [beneficiaries],
                    [percentages],
                    nonce,
                    signature
                )
            )
                .to.emit(ownerAssetManager, "ERC20AssetAdded")
                .withArgs(
                    userId,
                    owner.address,
                    ERC20.address,
                    amount,
                    beneficiaries,
                    percentages,
                    100
                );
        });
        it("Should fail to add single ERC20 asset when asset amount exceeds balance", async () => {
            const {
                admin,
                authorizer,
                owner,
                beneficiary,
                ownerAssetManager,
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
                ownerAssetManager.addERC20Assets(
                    userId,
                    [ERC20.address],
                    [amount],
                    [beneficiaries],
                    [percentages],
                    nonce,
                    signature
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
        //         ERC20,
        //         ownerVault,
        //         ownerERC20,
        //         beneficiary1,
        //         beneficiary2,
        //     } = await deploy();
        //     const userId = ethers.utils.hashMessage(owner.address);
        //     const amount = ethers.utils.parseEther("101");
        //     await ownerERC20.approve(
        //         ownerVault.address,
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
        //             [amount],
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
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiary1,
                beneficiary2,
            } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            const amount = ethers.utils.parseEther("100");
            await ownerERC20.approve(
                ownerVault.address,
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
                ownerAssetManager.addERC20Assets(
                    userId,
                    [ERC20.address],
                    [amount],
                    [beneficiaries],
                    [percentages],
                    nonce,
                    signature
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
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiaryAssetManager,
                beneficiary1,
                beneficiary2,
            } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            const amount = ethers.utils.parseEther("100");
            await ownerERC20.approve(
                ownerVault.address,
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
            await ownerAssetManager.addERC20Assets(
                userId,
                [ERC20.address],
                [amount],
                [beneficiaries],
                [percentages],
                nonce,
                addSignature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC20.address,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);
            await expect(
                beneficiaryAssetManager.claimERC20Asset(
                    userId,
                    owner.address,
                    ERC20.address,
                    nonce + 1,
                    [claimSignature]
                )
            )
                .to.emit(beneficiaryAssetManager, "ERC20AssetClaimed")
                .withArgs(
                    userId,
                    owner.address,
                    beneficiary.address,
                    ERC20.address,
                    ethers.utils.parseEther("33"),
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
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiaryAssetManager,
                beneficiary1,
                beneficiary2,
            } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            const amount = ethers.utils.parseEther("100");
            await ownerERC20.approve(
                ownerVault.address,
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
            await ownerAssetManager.addERC20Assets(
                userId,
                [ERC20.address],
                [amount],
                [beneficiaries],
                [percentages],
                nonce,
                addSignature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC20.address,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);
            await beneficiaryAssetManager.claimERC20Asset(
                userId,
                owner.address,
                ERC20.address,
                nonce + 1,
                [claimSignature]
            );
            const claimHashedMessage1 = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC20.address,
                        nonce + 2,
                    ]
                )
            );
            const claimSignature1 = await admin.signMessage(
                claimHashedMessage1
            );
            await expect(
                beneficiaryAssetManager.claimERC20Asset(
                    userId,
                    owner.address,
                    ERC20.address,
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
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiaryAssetManager,
                beneficiary1,
                beneficiary2,
                beneficiary3,
            } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            const amount = ethers.utils.parseEther("100");
            await ownerERC20.approve(
                ownerVault.address,
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
            await ownerAssetManager.addERC20Assets(
                userId,
                [ERC20.address],
                [amount],
                [beneficiaries],
                [percentages],
                nonce,
                addSignature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC20.address,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);
            await expect(
                beneficiaryAssetManager.claimERC20Asset(
                    userId,
                    owner.address,
                    ERC20.address,
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
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiaryAssetManager,
                beneficiary1,
                beneficiary2,
                beneficiary3,
            } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            const amount = ethers.utils.parseEther("100");
            await ownerERC20.approve(
                ownerVault.address,
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
            await ownerAssetManager.addERC20Assets(
                userId,
                [ERC20.address],
                [amount],
                [beneficiaries],
                [percentages],
                nonce,
                addSignature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC20.address,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);
            await ownerERC20.transfer(
                beneficiary3.address,
                await ownerERC20.balanceOf(owner.address)
            );
            await expect(
                beneficiaryAssetManager.claimERC20Asset(
                    userId,
                    owner.address,
                    ERC20.address,
                    nonce + 1,
                    [claimSignature]
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Owner has zero balance or zero allowance for this asset"
            );
        });
    });

    context("Add Backup Wallet", async () => {
        it("Should add a backup wallet for a valid user", async () => {
            const { owner, ownerAssetManager, backupWallet } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            await expect(
                ownerAssetManager.setBackupWallet(userId, backupWallet.address)
            )
                .to.emit(ownerAssetManager, "BackupWalletAdded")
                .withArgs(userId, owner.address, backupWallet.address);
        });
        it("Should fail to add a backup wallet with zero address", async () => {
            const { owner, ownerAssetManager } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            await expect(
                ownerAssetManager.setBackupWallet(
                    userId,
                    ethers.constants.AddressZero
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Invalid address for backup wallet"
            );
        });
        it("Should fail to add a backup wallet with already added address", async () => {
            const { owner, ownerAssetManager, backupWallet } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            await ownerAssetManager.setBackupWallet(
                userId,
                backupWallet.address
            );
            await expect(
                ownerAssetManager.setBackupWallet(userId, backupWallet.address)
            ).to.be.revertedWith(
                "LegacyAssetManager: Backup wallet provided already set"
            );
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
                ERC721,
                ERC20,
                ownerERC20,
                ownerVault,
                beneficiary,
                beneficiary1,
                beneficiary2,
                beneficiary3,
                beneficiary4,
                backupWallet,
            } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            await ownerAssetManager.setBackupWallet(
                userId,
                backupWallet.address
            );
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
                ],
                nonce,
                signature
            );
            const amount = ethers.utils.parseEther("100");
            const beneficiaires = [
                beneficiary.address,
                beneficiary1.address,
                beneficiary2.address,
            ];
            const percentages = [33, 33, 34];
            await ownerERC20.approve(
                ownerVault.address,
                ethers.utils.parseEther("100")
            );
            await ownerAssetManager.addERC20Assets(
                userId,
                [ERC20.address],
                [amount],
                [beneficiaires],
                [percentages],
                nonce,
                signature
            );
            await expect(
                backupWalletAssetManager.switchBackupWallet(
                    userId,
                    owner.address
                )
            ).to.emit(backupWalletAssetManager, "BackupWalletSwitched");
        });
        it("Should fail to swith backup wallet when called by non backup wallet", async () => {
            const {
                admin,
                authorizer,
                owner,
                ownerAssetManager,
                backupWalletAssetManager,
                ERC721,
                ERC20,
                ownerERC20,
                ownerVault,
                beneficiary,
                beneficiary1,
                beneficiary2,
                beneficiary3,
                beneficiary4,
                backupWallet,
            } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            await ownerAssetManager.setBackupWallet(
                userId,
                backupWallet.address
            );
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
                ],
                nonce,
                signature
            );
            const amount = ethers.utils.parseEther("100");
            const beneficiaires = [
                beneficiary.address,
                beneficiary1.address,
                beneficiary2.address,
            ];
            const percentages = [33, 33, 34];
            await ownerERC20.approve(
                ownerVault.address,
                ethers.utils.parseEther("100")
            );
            await ownerAssetManager.addERC20Assets(
                userId,
                [ERC20.address],
                [amount],
                [beneficiaires],
                [percentages],
                nonce,
                signature
            );
            await expect(
                ownerAssetManager.switchBackupWallet(userId, owner.address)
            ).to.be.revertedWith(
                "LegacyAssetManager: Unauthorized backup wallet transfer call"
            );
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
            await ownerAssetManager.addERC721Assets(
                userId,
                [ERC721.address],
                [1],
                [beneficiary.address],
                nonce,
                signature
            );
            await expect(
                ownerAssetManager.setBeneficiary(
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
            await ownerAssetManager.addERC721Assets(
                userId,
                [ERC721.address],
                [1],
                [beneficiary.address],
                nonce,
                signature
            );
            const claimHashedMessage = ethers.utils.arrayify(
                ethers.utils.solidityKeccak256(
                    ["address", "address", "address", "uint256", "uint256"],
                    [
                        owner.address,
                        beneficiary.address,
                        ERC721.address,
                        1,
                        nonce + 1,
                    ]
                )
            );
            const claimSignature = await admin.signMessage(claimHashedMessage);
            await beneficiaryAssetManager.claimERC721Asset(
                userId,
                owner.address,
                ERC721.address,
                1,
                nonce + 1,
                [claimSignature]
            );
            await expect(
                ownerAssetManager.setBeneficiary(
                    userId,
                    ERC721.address,
                    1,
                    beneficiary1.address
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Asset has been transferred"
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
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiaryAssetManager,
                beneficiary1,
                beneficiary2,
            } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            const amount = ethers.utils.parseEther("100");
            await ownerERC20.approve(
                ownerVault.address,
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
            await ownerAssetManager.addERC20Assets(
                userId,
                [ERC20.address],
                [amount],
                [beneficiaries],
                [percentages],
                nonce,
                addSignature
            );
            await expect(
                ownerAssetManager.setBeneficiaryPercentage(
                    userId,
                    ERC20.address,
                    beneficiary.address,
                    30
                )
            )
                .to.emit(ownerAssetManager, "BeneficiaryPercentageChanged")
                .withArgs(
                    userId,
                    owner.address,
                    ERC20.address,
                    beneficiary.address,
                    30
                );
            expect(
                (
                    await ownerAssetManager.getERC20Asset(
                        owner.address,
                        ERC20.address
                    )
                ).beneficiaries[0].allowedPercentage
            ).to.be.equals(30);
        });
        it("Should change the percentages for ERC20 Asset beneficiary", async () => {
            const {
                admin,
                authorizer,
                owner,
                beneficiary,
                ownerAssetManager,
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiaryAssetManager,
                beneficiary1,
                beneficiary2,
            } = await deploy();
            const userId = ethers.utils.hashMessage(owner.address);
            const amount = ethers.utils.parseEther("100");
            await ownerERC20.approve(
                ownerVault.address,
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
            await ownerAssetManager.addERC20Assets(
                userId,
                [ERC20.address],
                [amount],
                [beneficiaries],
                [percentages],
                nonce,
                addSignature
            );
            await expect(
                ownerAssetManager.setBeneficiaryPercentage(
                    userId,
                    ERC20.address,
                    beneficiary.address,
                    34
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Beneficiary percentage exceeds 100"
            );
        });
    });
});
