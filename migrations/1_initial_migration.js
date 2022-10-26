const { expect } = require("chai");
const { ethers } = require("hardhat");

function sleep(ms) {
    return new Promise((resolve) => {
        setTimeout(resolve, ms);
    });
}

async function deploy() {
    const [admin, authorizer, owner, _] = await ethers.getSigners();

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

    console.log("ERC1155 Address: " + ERC1155.address);
    console.log("ERC721 Address: " + ERC721.address);
    console.log("ERC20 Address: " + ERC20.address);
    console.log("LegacyVaultFactory Address: " + LegacyVaultFactory.address);
    console.log("LegacyAssetManager Address: " + LegacyAssetManager.address);

    await sleep(5000);

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

    await sleep(5000);

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

    await sleep(5000);

    await ownerERC20.approve(
        ownerVaultAddress,
        ethers.utils.parseEther("100000")
    );
    await ownerERC1155.setApprovalForAll(ownerVaultAddress, true);

    await sleep(5000);

    await ERC20.transfer(owner.address, ethers.utils.parseEther("10000"));

    await ownerERC721.setApprovalForAll(ownerVault.address, true);
    for (let i = 1; i <= 10; i++) {
        await ERC721.mint(owner.address, i);
    }
}

async function main() {
    await deploy();
}

main();
