const { expect } = require("chai");
const { ethers } = require("hardhat");
// const { ClaimableVoucher } = require("../lib");

async function deploy() {
    const [
        admin,
        owner,
        beneficiary,
        beneficiary1,
        beneficiary2,
        beneficiary3,
        beneficiary4,
        beneficiary5,
        _,
    ] = await ethers.getSigners();

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
        LegacyVaultFactory.address
    );

    await LegacyAssetManager.deployed();
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
    await LegacyVaultFactory.createVault(owner.address);
    const ownerVaultAddress =
        await LegacyVaultFactory.deployedContractFromMember(owner.address);
    const ownerVault = LegacyVaultArtifact.attach(ownerVaultAddress);
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

    await ERC20.transfer(owner.address, ethers.utils.parseEther("10000"));
    for (let i = 1; i <= 10; i++) {
        await ERC721.mint(owner.address, i);
        await ownerERC721.approve(ownerVault.address, i);
    }

    return {
        LegacyAssetManager,
        LegacyVaultFactory,
        ownerAssetManager,
        ownerVault,
        beneficiaryAssetManager,
        ERC721,
        ERC20,
        admin,
        owner,
        ownerERC721,
        ownerERC20,
        beneficiary,
        beneficiary1,
        beneficiary2,
        beneficiary3,
        beneficiary4,
        beneficiary5,
    };
}

describe("LegacyAssetManager: addERC721Single", async function () {
    context("add erc721 asset", async function () {
        it("Should add single ERC721 asset", async function () {
            const { owner, ownerAssetManager, ERC721, beneficiary } =
                await deploy();

            // check if event is emitted
            await expect(
                ownerAssetManager.addERC721Single(
                    ERC721.address,
                    1,
                    beneficiary.address
                )
            )
                .to.emit(ownerAssetManager, "ERC21AssetAdded") // transfer from minter to redeemer
                .withArgs(
                    owner.address,
                    ERC721.address,
                    1,
                    beneficiary.address
                );
        });
    });
    context("add erc721 asset two times", async function () {
        it("Should fail to add single ERC721 asset more than once", async function () {
            const { owner, ownerAssetManager, ERC721, beneficiary } =
                await deploy();
            await ownerAssetManager.addERC721Single(
                ERC721.address,
                1,
                beneficiary.address
            );
            // check if event is emitted
            await expect(
                ownerAssetManager.addERC721Single(
                    ERC721.address,
                    1,
                    beneficiary.address
                )
            ).to.revertedWith("LegacyAssetManager: Asset already added");
        });
    });
    context("add erc721 asset from non owner", async function () {
        it("Should fail to add single ERC721 asset more than once", async function () {
            const { owner, ownerAssetManager, ERC721, beneficiary } =
                await deploy();

            await ERC721.mint(beneficiary.address, 11);
            // check if event is emitted
            await expect(
                ownerAssetManager.addERC721Single(
                    ERC721.address,
                    11,
                    beneficiary.address
                )
            ).to.revertedWith(
                "LegacyAssetManager: Caller is not the token owner"
            );
        });
    });
    context("add erc721 asset not approved", async function () {
        it("Should fail to add single ERC721 that is not approved", async function () {
            const { owner, ownerAssetManager, ERC721, beneficiary } =
                await deploy();

            await ERC721.mint(owner.address, 11);
            // check if event is emitted
            await expect(
                ownerAssetManager.addERC721Single(
                    ERC721.address,
                    11,
                    beneficiary.address
                )
            ).to.revertedWith("LegacyAssetManager: Asset not approved");
        });
    });
});

describe("LegacyAssetManager: claimERC721Single", async () => {
    context("Claim single Asset", async function () {
        it("Should claim single ERC721 Asset", async function () {
            const {
                owner,
                ERC721,
                beneficiary,
                ownerAssetManager,
                beneficiaryAssetManager,
            } = await deploy();

            await ownerAssetManager.addERC721Single(
                ERC721.address,
                1,
                beneficiary.address
            );

            // check if event is emitted
            await expect(
                beneficiaryAssetManager.claimERC721Asset(
                    owner.address,
                    ERC721.address,
                    1
                )
            )
                .to.emit(beneficiaryAssetManager, "ERC721AssetClaimed") // transfer from minter to redeemer
                .withArgs(
                    owner.address,
                    beneficiary.address,
                    ERC721.address,
                    1
                );
            expect(await ERC721.ownerOf(1)).to.be.equals(beneficiary.address);
        });
    });
    context("Claim single Asset twice", async function () {
        it("Should fail to claim single ERC721 Asset twice", async function () {
            const {
                owner,
                ERC721,
                beneficiary,
                ownerAssetManager,
                beneficiaryAssetManager,
            } = await deploy();

            await ownerAssetManager.addERC721Single(
                ERC721.address,
                1,
                beneficiary.address
            );

            await beneficiaryAssetManager.claimERC721Asset(
                owner.address,
                ERC721.address,
                1
            );
            await expect(
                beneficiaryAssetManager.claimERC721Asset(
                    owner.address,
                    ERC721.address,
                    1
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Beneficiary has already claimed the asset"
            );
        });
    });
    context("When caller is not the beneficiary", async function () {
        it("Should fail to claim single ERC721 by non beneficiary", async function () {
            const {
                owner,
                ERC721,
                beneficiary,
                ownerAssetManager,
                beneficiaryAssetManager,
                beneficiary1,
            } = await deploy();

            await ownerAssetManager.addERC721Single(
                ERC721.address,
                1,
                beneficiary1.address
            );
            await expect(
                beneficiaryAssetManager.claimERC721Asset(
                    owner.address,
                    ERC721.address,
                    1
                )
            ).to.be.revertedWith("LegacyAssetManager: Unauthorized claim call");
        });
    });
    context("When the asset has been transferred", async function () {
        it("Should fail to claim single ERC721 when the owner has been changed", async function () {
            const {
                owner,
                ownerERC721,
                ERC721,
                ownerAssetManager,
                beneficiary,
                beneficiaryAssetManager,
                beneficiary1,
            } = await deploy();

            await ownerAssetManager.addERC721Single(
                ERC721.address,
                1,
                beneficiary.address
            );
            await ownerERC721.transferFrom(
                owner.address,
                beneficiary1.address,
                1
            );
            await expect(
                beneficiaryAssetManager.claimERC721Asset(
                    owner.address,
                    ERC721.address,
                    1
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: The asset does not belong to the owner now"
            );
        });
    });
});

describe("LegacyAssetManager: addERC20Single", async () => {
    context("Add single ERC20 asset", async () => {
        it("Should add single ERC20 asset", async () => {
            const {
                owner,
                beneficiary,
                ownerAssetManager,
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiary1,
                beneficiary2,
            } = await deploy();
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
            await expect(
                ownerAssetManager.addERC20Single(
                    ERC20.address,
                    amount,
                    beneficiaries,
                    percentages
                )
            )
                .to.emit(ownerAssetManager, "ERC20AssetAdded")
                .withArgs(
                    owner.address,
                    ERC20.address,
                    amount,
                    beneficiaries,
                    percentages
                );
        });
    });
    context("When asset amount exceeds balance", async () => {
        it("Should fail to add single ERC20 asset when asset amount exceeds balance", async () => {
            const {
                owner,
                beneficiary,
                ownerAssetManager,
                ERC20,
                beneficiary1,
                beneficiary2,
            } = await deploy();
            const amount = ethers.utils.parseEther(
                (await ERC20.balanceOf(owner.address)) + 100
            );
            const beneficiaries = [
                beneficiary.address,
                beneficiary1.address,
                beneficiary2.address,
            ];
            const percentages = [33, 33, 34];
            await expect(
                ownerAssetManager.addERC20Single(
                    ERC20.address,
                    amount,
                    beneficiaries,
                    percentages
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Asset amount exceeds balance"
            );
        });
    });
    context("When allowance is insufficient", async () => {
        it("Should fail to add single ERC20 asset when the allowance is insufficient", async () => {
            const {
                owner,
                beneficiary,
                ownerAssetManager,
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiary1,
                beneficiary2,
            } = await deploy();
            const amount = ethers.utils.parseEther("101");
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
            await expect(
                ownerAssetManager.addERC20Single(
                    ERC20.address,
                    amount,
                    beneficiaries,
                    percentages
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Asset allowance is insufficient"
            );
        });
    });
    context("When beneficiary percentages exceed 100", async () => {
        it("Should fail to add single ERC20 asset when percentages exceed 100", async () => {
            const {
                owner,
                beneficiary,
                ownerAssetManager,
                ERC20,
                ownerVault,
                ownerERC20,
                beneficiary1,
                beneficiary2,
            } = await deploy();
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
            await expect(
                ownerAssetManager.addERC20Single(
                    ERC20.address,
                    amount,
                    beneficiaries,
                    percentages
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Beneficiary percentages exceed 100"
            );
        });
    });
});

describe("LegacyAssetManager: claimERC20", async () => {
    context("add single ERC20 asset", async () => {
        it("Should claim single ERC20 asset", async () => {
            const {
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

            await ownerAssetManager.addERC20Single(
                ERC20.address,
                amount,
                beneficiaries,
                percentages
            );
            await expect(
                beneficiaryAssetManager.claimERC20Asset(
                    owner.address,
                    ERC20.address
                )
            )
                .to.emit(beneficiaryAssetManager, "ERC20AssetClaimed")
                .withArgs(
                    owner.address,
                    beneficiary.address,
                    ERC20.address,
                    ethers.utils.parseEther("33")
                );
        });
    });
    context("Claiming twice", async () => {
        it("Should fail to claim single ERC20 asset twice", async () => {
            const {
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

            await ownerAssetManager.addERC20Single(
                ERC20.address,
                amount,
                beneficiaries,
                percentages
            );
            await beneficiaryAssetManager.claimERC20Asset(
                owner.address,
                ERC20.address
            );
            await expect(
                beneficiaryAssetManager.claimERC20Asset(
                    owner.address,
                    ERC20.address
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Beneficiary has already claimed the asset"
            );
        });
    });
    context("When caller is not a beneficiary", async () => {
        it("Should fail to claim single ERC20 asset by non beneficiary", async () => {
            const {
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
            await ownerAssetManager.addERC20Single(
                ERC20.address,
                amount,
                beneficiaries,
                percentages
            );
            await expect(
                beneficiaryAssetManager.claimERC20Asset(
                    owner.address,
                    ERC20.address
                )
            ).to.be.revertedWith("LegacyAssetManager: Beneficiary not found");
        });
    });
    context("When owner has zero balance", async () => {
        it("Should fail to claim single ERC20 asset by non beneficiary", async () => {
            const {
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
            await ownerAssetManager.addERC20Single(
                ERC20.address,
                amount,
                beneficiaries,
                percentages
            );
            await ownerERC20.transfer(
                beneficiary3.address,
                await ownerERC20.balanceOf(owner.address)
            );
            await expect(
                beneficiaryAssetManager.claimERC20Asset(
                    owner.address,
                    ERC20.address
                )
            ).to.be.revertedWith(
                "LegacyAssetManager: Owner has zero balance for this asset"
            );
        });
    });
});

// TODO: Add signature generation and verification
// TODO: Add all beneficiaries claim
