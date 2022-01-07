const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DonkeVerse", function () {
  let DonkeVerseContract = null;
  let owner = null;
  let addr1 = null;
  let addr2 = null;

  beforeEach(async function () {
    const dv = await ethers.getContractFactory("DonkeVerse");
    [owner, addr1, addr2] = await ethers.getSigners();

    DonkeVerseContract = await dv.deploy();
    await DonkeVerseContract.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await DonkeVerseContract.owner()).to.equal(owner.address);
    });
  });

  describe("publicMint", async function () {
    let signingWallet = null;
    function signAddress(wallet, customer) {
      return wallet.signMessage(
        ethers.utils.arrayify(
          ethers.utils.defaultAbiCoder.encode(
            ["bytes32"],
            [ethers.utils.defaultAbiCoder.encode(["address"], [customer])]
          )
        )
      );
    }

    beforeEach(async function () {
      // signingWallet = addr1.privateKey
      signingWallet = addr1;

      await DonkeVerseContract.setPublicMintAddress(addr1.address);
    });

    it("should reject non-whitelisted user with nonsense signature when public minting is not open", async function () {
      await expect(
        DonkeVerseContract.publicMint("0x123abc")
      ).to.be.revertedWith("ECDSA: invalid signature length");
    });

    it("should reject using the signature of another address", async function () {
      await expect(
        DonkeVerseContract.connect(addr2).publicMint(
          "0xf15658ed1ec8799e6e3644a3d21240c5aebc48a347fdbf8b3a62c9e1a8b4189c0b7ffcbd3eb664de69bc12e916a96f8e67159b549348690b0b52d4e501f380e81b"
        )
      ).to.be.revertedWith("not allowed");
    });

    it("should allow whitelisted users to mint if they pay enough ether", async function () {
      const signature1 = await signAddress(signingWallet, addr1.address);

      expect(
        await DonkeVerseContract.connect(addr1).publicMint(signature1, {
          value: ethers.utils.parseEther("0.06"),
        })
      );
      expect(await DonkeVerseContract.ownerOf(1)).to.be.equal(addr1.address);

      expect(
        await DonkeVerseContract.connect(addr1).publicMint(signature1, {
          value: ethers.utils.parseEther("0.06"),
        })
      );
      expect(await DonkeVerseContract.ownerOf(2)).to.be.equal(addr1.address);
    });

    it("should reject transactions below 0.07 ether", async function () {
      const signature1 = signAddress(signingWallet, addr1.address);
      await expect(
        DonkeVerseContract.connect(addr1).publicMint(signature1, {
          value: ethers.utils.parseEther("0.069"),
        })
      ).to.be.revertedWith("wrong price");
    });

    xit("should allow priviledged users extra mints", async function () {
      await DonkeVerseContract.setExtraMintsForAddress(addr1.address, 6);
      const signature1 = signAddress(signingWallet, addr1.address);
      expect(
        await DonkeVerseContract.connect(addr1).publicMint(signature1, {
          value: ethers.utils.parseEther("0.07"),
        })
      );
      for (let i = 0; i < 6; i++) {
        expect(await DonkeVerseContract.ownerOf(i)).to.be.equal(addr1.address);
      }
    });

    xit("should not exceed total supply", async function () {
      this.timeout(60 * 1000);
      await DonkeVerseContract.setExtraMintsForAddress(
        addr1.address,
        10000 - 1
      );
      const signature1 = signAddress(signingWallet, addr1.address);
      const signature2 = signAddress(signingWallet, addr2.address);
      let totalMints = 0;

      // mint 9999 times
      for (let i = 0; i < 9; i++) {
        totalMints += 1000;
        await DonkeVerseContract.connect(addr1).publicMint(signature1, 1000, {
          value: ethers.utils.parseEther("0.07"),
        });
      }
      totalMints += 999;
      await DonkeVerseContract.connect(addr1).publicMint(signature1, 999, {
        value: ethers.utils.parseEther("0.07"),
      });

      // mint enough times to hit 10001
      totalMints += 2;
      await expect(
        DonkeVerseContract.connect(addr2).publicMint(signature2, 2, {
          value: ethers.utils.parseEther("0.07"),
        })
      ).to.be.revertedWith("max supply");
      expect(totalMints).to.be.equal(10001);
    });
  });

  describe("privateMint", async function () {
    let signingWallet = null;
    function signAddress(wallet, customer) {
      return wallet.signMessage(
        ethers.utils.arrayify(
          ethers.utils.defaultAbiCoder.encode(
            ["bytes32"],
            [ethers.utils.defaultAbiCoder.encode(["address"], [customer])]
          )
        )
      );
    }

    beforeEach(async function () {
      signingWallet = addr2;
      await DonkeVerseContract.setPrivateMintAddress(signingWallet.address);
    });

    it("should only accept owner", async function () {
      const signature1 = signAddress(signingWallet, addr1.address);
      await expect(
        DonkeVerseContract.connect(addr1).privateMint(signature1, 2)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should reject alternative signatures", async function () {
      const privateKeyOtherWallet =
        "0xAAA3456789012345678901234567890123456789012345678901234567890123";
      const otherWallet = new ethers.Wallet(privateKeyOtherWallet);
      const fakeSignature = signAddress(otherWallet, addr1.address);
      await expect(
        DonkeVerseContract.connect(owner).privateMint(fakeSignature, 2)
      ).to.be.revertedWith("not allowed");
    });
  });

  describe("tokenURI", async function () {
    it("should reject invalid token values", async function () {
      await expect(DonkeVerseContract.tokenURI(99999)).to.be.revertedWith(
        "invalid id"
      );
    });
    it("should return placeholder before reveal", async function () {
      expect(await DonkeVerseContract.tokenURI(0)).to.be.equal(
        "https://www.example.com/metadata/placeholder.json"
      );
    });
    it("should return shuffled result after reveal", async function () {
      await DonkeVerseContract.reveal(32);
      expect(await DonkeVerseContract.tokenURI(0)).to.be.equal(
        "https://www.example.com/metadata/0.json"
      );
    });
  });

  describe("administrative functions", async function () {
    describe("reveal", async function () {
      it("should require an input of 32 as a speedbump", async function () {
        await expect(DonkeVerseContract.reveal(33)).to.be.revertedWith(
          "be careful"
        );
      });
    });

    describe("setPublicMintAddress", async function () {
      it("only owner can set the public key for whitelisting", async function () {
        await expect(
          DonkeVerseContract.connect(addr1.address).setPublicMintAddress(
            addr1.address
          )
        ).to.be.reverted;
      });

      it("should set the public key for whitelisting", async function () {
        const privateKey =
          "0x0123456789012345678901234567890123456789012345678901234567890123";
        const wallet = new ethers.Wallet(privateKey);

        expect(await DonkeVerseContract.getPublicMintingAddress()).to.equal(
          ethers.utils.getAddress("0x0000000000000000000000000000000000000001")
        );

        await DonkeVerseContract.setPublicMintAddress(wallet.address);
        expect(await DonkeVerseContract.getPublicMintingAddress()).to.equal(
          wallet.address
        );
      });
    });

    describe("setForeverLock", async function () {
      it("should only be callable by owner", async function () {
        await expect(
          DonkeVerseContract.connect(addr1.address).setForeverLock(50)
        ).to.be.reverted;
      });
      it("should reject unless the number 50 is entered", async function () {
        await expect(DonkeVerseContract.setForeverLock(0)).to.be.revertedWith(
          "be careful"
        );
      });
      it("should reject if max supply is not reached", async function () {
        await expect(DonkeVerseContract.setForeverLock(50)).to.be.revertedWith(
          "cannot lock"
        );
        expect(await DonkeVerseContract.foreverLocked()).to.be.equal(0);
      });
    });

    describe("setPrivateMintAddress", async function () {
      it("only owner can set the public key for gifting", async function () {
        await expect(
          DonkeVerseContract.connect(addr1.address).setPrivateMintAddress(
            addr1.address
          )
        ).to.be.reverted;
      });

      it("should set the private key for gifting", async function () {
        const privateKey =
          "0xBB23456789012345678901234567890123456789012345678901234567890123";
        const wallet = new ethers.Wallet(privateKey);

        expect(await DonkeVerseContract.getPrivateMintingAddress()).to.equal(
          ethers.utils.getAddress("0x0000000000000000000000000000000000000001")
        );
        await DonkeVerseContract.setPrivateMintAddress(wallet.address);
        expect(await DonkeVerseContract.getPrivateMintingAddress()).to.equal(
          wallet.address
        );
      });

      it("should not allow gifting and public to be the same", async function () {
        const privateKey =
          "0xBB23456789012345678901234567890123456789012345678901234567890123";
        const wallet = new ethers.Wallet(privateKey);

        await DonkeVerseContract.setPublicMintAddress(wallet.address);
        await expect(
          DonkeVerseContract.setPrivateMintAddress(wallet.address)
        ).to.be.revertedWith("not allowed");
      });
    });

    describe("setRoyaltyBasisPoints", async function () {
      it("should set the royalty basis points", async function () {
        await DonkeVerseContract.setRoyaltyBasisPoints(800);
        expect(await DonkeVerseContract.royaltyBasisPoints()).to.be.equal(
          new ethers.BigNumber.from(800)
        );
      });

      it("should reject high royalty", async function () {
        await expect(
          DonkeVerseContract.setRoyaltyBasisPoints(5001)
        ).to.be.revertedWith("invalid royalty");
        expect(await DonkeVerseContract.royaltyBasisPoints()).to.be.equal(
          new ethers.BigNumber.from(500)
        );
      });

      it("only owner", async function () {
        await expect(
          DonkeVerseContract.connect(addr2).setRoyaltyBasisPoints(10)
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });
    });

    describe("receiveResults", async function () {
      it("should receive values", async function () {
        this.timeout(30 * 1000);
        const toUpload = Array.from(Array(7778).keys()).reverse();
        for (let i = 0; i < 6000; i += 2000) {
          await DonkeVerseContract.receiveValues(
            toUpload.slice(i, i + 2000),
            i
          );
        }

        await DonkeVerseContract.receiveValues(
          toUpload.slice(6000, 7778),
          6000
        );

        expect(await DonkeVerseContract.getNftToImageMapping()).to.eql(
          toUpload
        );
      });

      xit("should block if ForeverLock is set", async function () {
        await DonkeVerseContract.setForeverLock(50);
        await expect(
          DonkeVerseContract.receiveValues([5], 0)
        ).to.be.revertedWith("ForeverLocked");
      });

      it("onlyOwner");
    });
  });

  describe("referenceShuffle", async function () {
    function referenceShuffle(seed, _totalSupply) {
      const mapping = [];
      for (let i = 0; i < _totalSupply; i++) {
        mapping.push(i);
      }
      let randomState256 = new ethers.BigNumber.from(seed);
      for (let i = _totalSupply - 1; i > 1; i--) {
        randomState256 = new ethers.BigNumber.from(
          ethers.utils.solidityKeccak256(["uint"], [randomState256])
        );
        const j = randomState256.mod(new ethers.BigNumber.from(i));
        [mapping[i], mapping[j]] = [mapping[j], mapping[i]];
      }
      return mapping;
    }

    it("should match javascript ipmementation", async function () {
      console.log("Please be patient, this will take a minute");
      this.timeout(60 * 1000);
      // const randomSeed = new ethers.BigNumber.from(
      //  "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
      // );
      const referenceShuffleResult = referenceShuffle(100, 7778);
      const contractShuffleResult = await DonkeVerseContract.referenceShuffle(
        100
      );
      expect(referenceShuffleResult).to.be.eql(contractShuffleResult);
    });
  });

  describe("withdraw", async function () {
    it("should block non-owner", async function () {
      await expect(
        DonkeVerseContract.connect(addr2).withdraw()
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should allow owner to withdraw", async function () {
      const prov = ethers.provider;

      const previousBalance = await prov.getBalance(owner.address);
      await addr1.sendTransaction({
        to: DonkeVerseContract.address,
        value: ethers.utils.parseEther("10.0"), // Sends exactly 1.0 ether
      });
      await DonkeVerseContract.withdraw();

      const newBalance = await prov.getBalance(owner.address);

      expect(newBalance - previousBalance).to.be.approximately(
        10 * 10 ** 18,
        0.001 * 10 ** 18
      );
    });
  });

  describe("royalties", async function () {
    it("should return 10% of sale price for mintable", async function () {
      const result = await DonkeVerseContract.royaltyInfo(2, 100);
      expect(result.receiver).to.be.equal(owner.address);
      expect(result.royaltyAmount).to.be.equal(5);
    });

    it("should return 900 basis points for rarible", async function () {
      expect(await DonkeVerseContract.getFeeBps(21)).to.be.eql([
        new ethers.BigNumber.from(500),
      ]);
    });

    it("should return owner for rarible", async function () {
      expect(await DonkeVerseContract.getFeeRecipients(23)).to.be.eql([
        owner.address,
      ]);
    });
  });

  describe("supportsInterface", async function () {
    it("should support raribleV1", async function () {
      expect(await DonkeVerseContract.supportsInterface("0xb7799584")).to.equal(
        true
      );
    });

    it("should support ERC2981", async function () {
      expect(await DonkeVerseContract.supportsInterface("0x2a55205a")).to.equal(
        true
      );
    });

    it("should support ERC721", async function () {
      expect(await DonkeVerseContract.supportsInterface("0x80ac58cd")).to.equal(
        true
      );
    });
  });
});
