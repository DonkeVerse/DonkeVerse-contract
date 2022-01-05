//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract DonkeVerse2 is ERC721Enumerable, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 5000;
    uint256 public constant MAX_PER_USER = 2;
    mapping(address => uint256) alreadyMinted;

    string BASE_URI = "www.example.com/metadata/";

    constructor() ERC721("COLLECTION_NAME", "SYMBOL") {}

    function publicMint() external payable {
        require(msg.value == 0.07 ether, "wrong price");
        require(totalSupply() < MAX_SUPPLY);
        require(alreadyMinted[msg.sender] < MAX_PER_USER);

        alreadyMinted[msg.sender] += 1;
        _mint(msg.sender, totalSupply());
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        return string(abi.encodePacked(BASE_URI, _tokenId.toString(), ".json"));
    }
}

// 123175 GAS
// 122400 GAS after optimization

// remove ERC 721
// 113404 GAS
// 112827 GAS after optimization

// 96796 GAS by setting to uint32
// 96103 GAS after optimization

// 96304 GAS by setting supply to start at 1
// 95727 GAS optimized by setting total supply to start at 1
