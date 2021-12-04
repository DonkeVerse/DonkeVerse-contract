//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.9;

import "node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "node_modules/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "node_modules/@openzeppelin/contracts/utils/Strings.sol";
import "node_modules/@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "./@rarible/royalties/contracts/LibRoyaltiesV1.sol";

contract DonkeVerse is ERC721, Ownable, VRFConsumerBase {
    using ECDSA for bytes32;
    using Strings for uint256;

    uint256 public price = 0.07 ether;
    uint256 public verifiedRandomResult;
    bytes32 public randomnessRequestId;

    uint32 public constant MAX_TOKEN_SUPPLY = 10000;
    uint32 public tokenSupply = 0;
    uint32 public allowPublicMinting = 0;
    uint32 public defaultMaxMintsPerUser = 5;
    uint32 public isRevealed = 0;
    uint32 public foreverLocked = 0;
    uint32 public numberOfTimesRandomNumberGeneratorCalled = 0;
    uint32 public royaltyBasisPoints = 900;

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    uint16[MAX_TOKEN_SUPPLY] public nftToImageMapping; // the result of the shuffle will be stored here.

    address public publicMintingAddress;
    address public privateMintingAddress;

    mapping(address => uint256) public overrideMaxMintsPerUser; // allows specific addresses to go over the limit of 10, or allows us to block an address we signed without changing the publicMintingAddress
    mapping(address => uint256) public amountMintedSoFar; // lets us track how many NFTs a particular address has minted, so we can limit them

    // CHANGE IN PROD - Chainlink Integration
    address internal constant VRF_COORDINATOR =
        0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B;
    address internal constant CHAINLINK_CONTRACT =
        0x01BE23585060835E02B77ef475b0Cc51aA1e0709;
    bytes32 internal constant KEYHASH =
        0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311;
    uint256 internal constant CHAINLINK_FEE = 0.1 * 10**18; // 0.1 LINK CHANGE IN PROD

    // CHANGE IN PROD - Metadata
    string public constant COLLECTION_NAME = "Collection Name 922";
    string public constant BASE_URI = "https://www.example.com/metadata/"; // this also doubles as a provenance hash when used with IPFS
    string public constant PLACEHOLDER = "placeholder"; // NO JSON EXTENSION

    // these events allow people to track if we called the number generator more than once.
    // We leave that as an option because there is a non-zero chance that chainlink will fail
    event RequestedRandomNumber(address _address, bytes32 _requestId);
    event FulfillRandomness(bytes32 _requestId, uint256 _randomness);

    constructor()
        ERC721(COLLECTION_NAME, "DV")
        VRFConsumerBase(VRF_COORDINATOR, CHAINLINK_CONTRACT)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    // administrative functions
    function togglePublicMinting() external onlyOwner {
        allowPublicMinting = 1 - allowPublicMinting;
    }

    // reveal can't be undone, so metadata is safe even if the private keys are stolen
    function reveal(uint256 _protection) external onlyOwner {
        require(_protection == 32, "be careful");
        isRevealed = 1;
    }

    // setForeverLock can't be undone, so metadata is safe even if the private keys are stolen
    function setForeverLock(uint256 _protection) external onlyOwner {
        require(_protection == 50, "be careful");
        require(tokenSupply == MAX_TOKEN_SUPPLY, "cannot lock");
        foreverLocked = 1;
    }

    // this function has a foreverLock because we don't want the values to change after the shuffle
    function receiveValues(uint16[] calldata _shuffle, uint16 _offset)
        external
        onlyOwner
    {
        require(foreverLocked == 0, "ForeverLocked"); // if set to 1, metadata cannot be updated
        for (uint256 i = 0; i < _shuffle.length; i++) {
            nftToImageMapping[_offset + i] = _shuffle[i];
        }
    }

    // the rest of the functions do not need to be locked
    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function setExceptionMaxMintsForAddress(address _address, uint32 _amount)
        external
        onlyOwner
    {
        require(_amount < MAX_TOKEN_SUPPLY, "too high");
        overrideMaxMintsPerUser[_address] = _amount;
    }

    function setDefaultMaxMintsPerUser(uint32 _amount) external onlyOwner {
        require(_amount < MAX_TOKEN_SUPPLY, "to high");
        defaultMaxMintsPerUser = _amount;
    }

    function setPrivateMintAddress(address _address) external onlyOwner {
        require(_address != publicMintingAddress, "not allowed");
        privateMintingAddress = _address;
    }

    function setPublicMintAddress(address _address) external onlyOwner {
        publicMintingAddress = _address;
    }

    function setRoyaltyBasisPoints(uint32 _royaltyBasisPoints)
        external
        onlyOwner
    {
        require(_royaltyBasisPoints <= 5000, "invalid royalty");
        royaltyBasisPoints = _royaltyBasisPoints;
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawLink() external onlyOwner {
        bool success = LINK.transfer(msg.sender, LINK.balanceOf(address(this)));
        require(success, "withdraw failed");
    }

    // minting functions
    function privateMint(bytes calldata _signature, uint256 _amount) external {
        require(isAllowedToPrivateMint(msg.sender, _signature), "not eligible");
        internalMint(msg.sender, _amount);
    }

    function publicMint(bytes calldata _signature, uint256 _amount)
        external
        payable
    {
        require(
            allowPublicMinting == 1 ||
                isAllowedToPublicMint(msg.sender, _signature),
            "not allowed"
        );
        require(msg.value >= price, "price too low");
        // solhint-disable-next-line avoid-tx-origin
        require(tx.origin == msg.sender, "no smart contracts");

        internalMint(msg.sender, _amount);
    }

    function internalMint(address _address, uint256 _amount) private {
        require(tokenSupply + _amount <= MAX_TOKEN_SUPPLY, "max supply");
        require(
            _amount + amountMintedSoFar[msg.sender] <= defaultMaxMintsPerUser ||
                _amount + amountMintedSoFar[msg.sender] <=
                overrideMaxMintsPerUser[msg.sender],
            "quantity too big"
        );

        for (uint256 i = 0; i < _amount; i++) {
            tokenSupply += 1;
            amountMintedSoFar[msg.sender] += 1;
            _mint(_address, tokenSupply - 1);
        }
    }

    // functions for users to get information

    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_tokenId < MAX_TOKEN_SUPPLY, "invalid id");
        string memory asset = isRevealed == 0
            ? PLACEHOLDER
            : uint256(nftToImageMapping[uint16(_tokenId)]).toString();
        return string(abi.encodePacked(BASE_URI, asset, ".json"));
    }

    // used to audit the shuffle was conducted according to the rules
    function getNftToImageMapping()
        external
        view
        returns (uint16[MAX_TOKEN_SUPPLY] memory)
    {
        return nftToImageMapping;
    }

    function verifySignature(
        address _address,
        address _account,
        bytes memory _signature
    ) internal pure returns (bool) {
        return
            _address ==
            keccak256(abi.encodePacked(_account))
                .toEthSignedMessageHash()
                .recover(_signature);
    }

    function isAllowedToPrivateMint(address _account, bytes memory _signature)
        public
        view
        returns (bool)
    {
        return verifySignature(privateMintingAddress, _account, _signature);
    }

    // bypassing this function call only saves 100 gas after optimization, so not worth it
    function isAllowedToPublicMint(address _account, bytes memory _signature)
        public
        view
        returns (bool)
    {
        return verifySignature(publicMintingAddress, _account, _signature);
    }

    // random number functions
    function getRandomNumber() external onlyOwner returns (bytes32 requestId) {
        require(foreverLocked == 0, "ForeverLocked");
        require(tokenSupply == MAX_TOKEN_SUPPLY, "too early");
        require(
            LINK.balanceOf(address(this)) > CHAINLINK_FEE,
            "Not enough LINK"
        );
        numberOfTimesRandomNumberGeneratorCalled += 1;
        bytes32 rid = requestRandomness(KEYHASH, CHAINLINK_FEE);
        emit RequestedRandomNumber(msg.sender, rid);
        return rid;
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        require(foreverLocked == 0, "ForeverLocked");
        randomnessRequestId = requestId;
        verifiedRandomResult = randomness;
        emit FulfillRandomness(requestId, randomness);
    }

    // royalty functions
    // Rarible updates the per id royalty during mint, but we have the same royalty
    // across the entire collection. So to save gas during mint, we just hardcode the
    // entire collection to be the same and ignore the uint256 input.
    function getFeeRecipients(uint256)
        external
        view
        returns (address payable[] memory)
    {
        address payable[] memory result = new address payable[](1);
        result[0] = payable(owner());
        return result;
    }

    // see above
    function getFeeBps(uint256) external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](1);
        result[0] = royaltyBasisPoints;
        return result;
    }

    // mintable and ERC2981. Again, we don't care about the token id
    function royaltyInfo(uint256, uint256 _salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        return (owner(), (_salePrice * royaltyBasisPoints) / 10000);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721)
        returns (bool)
    {
        if (interfaceId == LibRoyaltiesV1._INTERFACE_ID_FEES) {
            return true;
        }
        if (interfaceId == _INTERFACE_ID_ERC2981) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /*
     * reference javascript implementation using ethers.js

    function referenceShuffle(seed, _totalSupply) {
      let mapping = [];
      for (let i = 0; i < _totalSupply; i++) {
        mapping.push(i);
      }
      let randomState256 = new ethers.BigNumber.from(seed);
      for (let i = _totalSupply - 1; i > 0; i--) {
        randomState256 = new ethers.BigNumber.from(ethers.utils.solidityKeccak256(["uint"], [randomState256]));
        let j = randomState256.mod(new ethers.BigNumber.from(i));
        [mapping[i], mapping[j]] = [mapping[j], mapping[i]];
      }
      return mapping;
    }
    */

    // Due to gas costs, we cannot shuffle on chain, because we will take up a lot of gas block limit!
    // So instead, we get the random number seed on chain, execute the shuffle offchain, and upload the
    // results. People need to know the shuffle algorithm and its interaction with the random seed was
    // fixed in advance, so we publish it here.
    /*
    function referenceShuffle(uint256 _seed)
        external
        pure
        returns (uint16[MAX_TOKEN_SUPPLY] memory)
    {
        uint16[MAX_TOKEN_SUPPLY] memory initialState;
        for (uint16 i = 0; i < initialState.length; i++) {
            initialState[i] = i;
        }

        uint256 randomState256 = _seed;
        uint256 j;
        for (uint256 i = MAX_TOKEN_SUPPLY - 1; i > 0; i--) {
            randomState256 = uint256(
                keccak256(abi.encodePacked(randomState256))
            );
            j = randomState256 % i;
            (initialState[i], initialState[j]) = (
                initialState[j],
                initialState[i]
            );
        }

        return initialState;
    }
    */
}
