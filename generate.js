const ethers = require("ethers");
const crypto = require("crypto");
const keccak256 = require("keccak256");
const { MerkleTree } = require("merkletreejs");

addresses = [];
for (i = 0; i < 5000; i++) {
  const id = crypto.randomBytes(32).toString("hex");
  const privateKey = "0x" + id;
  const wallet = new ethers.Wallet(privateKey);
  // console.log("Address: " + wallet.address);
  addresses.push(wallet.address);
}

const merkleTree = new MerkleTree(addresses, keccak256, {
  hashLeaves: true,
  sortPairs: true,
});
const root = merkleTree.getHexRoot();
const proof = merkleTree.getHexProof(keccak256(addresses[2]));

console.log(proof);
