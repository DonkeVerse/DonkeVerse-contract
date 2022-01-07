//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;


import "./ERC721Tradable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "./@rarible/royalties/contracts/LibRoyaltiesV1.sol";


// TODO
// implement pausable for trading (to prevent sniping)
// add back the hidden gas savings
// implement burnable
// set variable token distribution for mods and volunteers
// move ERC2981 to its own interface/contract
contract DonkeVerse is ERC721Tradable, VRFConsumerBase {
    using ECDSA for bytes32;
    using Strings for uint256;

    // for tracking if a person has claimed their ticket on the presale
    uint256 private constant MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 private group00 = MAX_INT;
    uint256 private group01 = MAX_INT;
    uint256 private group02 = MAX_INT;
    uint256 private group03 = MAX_INT;
    uint256 private group04 = MAX_INT;
    uint256 private group05 = MAX_INT;
    uint256 private group06 = MAX_INT;
    uint256 private group07 = MAX_INT;
    uint256 private group08 = MAX_INT;
    uint256 private group09 = MAX_INT;
    uint256 private group10 = MAX_INT;
    uint256 private group11 = MAX_INT;
    uint256 private group12 = MAX_INT;
    uint256 private group13 = MAX_INT;
    uint256 private group14 = MAX_INT;
    uint256 private group15 = MAX_INT;
    uint256 private group16 = MAX_INT;
    uint256 private constant NUMBER_OF_GROUPS = 17;

    uint256 private nextTokenIndex = 1;
    uint256 public verifiedRandomResult;
    bytes32 public randomnessRequestId;

    // ID goes [1,7777] so the total supply is 7777.
    uint32 private constant MAX_TOKEN_SUPPLY = 7778;
    uint32 private isRevealed = 0;
    uint32 public foreverLocked = 0;
    uint32 public numberOfTimesRandomNumberGeneratorCalled = 0;
    uint32 public royaltyBasisPoints = 500;

    // https://eips.ethereum.org/EIPS/eip-2981
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    // the result of the shuffle will be stored here.
    uint16[MAX_TOKEN_SUPPLY] public nftToImageMapping;

    // these cannot be initialized to zero or someone 
    // can bypass with an intentional signature failure
    address public publicMintingAddress = address(1);
    address private privateMintingAddress = address(1);

    // allows specific addresses to go over the limit
    mapping(address => uint256) public extraMintsForAddress;

    // CHANGE IN PROD - Chainlink Integration
    address private constant VRF_COORDINATOR =
        0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B; // RINKEBY CHANGE IN PROD
    address private constant CHAINLINK_CONTRACT =
        0x01BE23585060835E02B77ef475b0Cc51aA1e0709; // RINKEBY CHANGE IN PROD
    bytes32 private constant KEYHASH =
        0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311;
    uint256 private constant CHAINLINK_FEE = 0.1 * 10**18; // RINKEBY 0.1 LINK CHANGE IN PROD
    address private constant OPENSEA_PROXY_ADDRESS = 
        0xF57B2c51dED3A29e6891aba85459d600256Cf317; // RINKEBY CHANGE IN PROD

    // CHANGE IN PROD - Metadata
    string public constant COLLECTION_NAME = "Collection Name 922";
    string public constant BASE_URI = "https://www.example.com/metadata/";
    string public constant PLACEHOLDER = "placeholder"; // NO JSON EXTENSION

    // these events allow people to track if we called the number 
    // generator more than once. We leave that as an option because 
    // there is a non-zero chance that chainlink will fail
    event RequestedRandomNumber(address _address, bytes32 _requestId);
    event FulfillRandomness(bytes32 _requestId, uint256 _randomness);

    constructor()
        ERC721Tradable(COLLECTION_NAME, "DV", OPENSEA_PROXY_ADDRESS)
        VRFConsumerBase(VRF_COORDINATOR, CHAINLINK_CONTRACT)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    // administrative functions

    // reveal can't be undone, so metadata is safe even if 
    // the private keys are stolen
    function reveal(uint256 _protection) external onlyOwner {
        require(_protection == 32, "be careful");
        isRevealed = 1;
    }

    // setForeverLock can't be undone, so metadata is safe even if 
    // the private keys are stolen
    function setForeverLock(uint256 _protection) external onlyOwner {
        require(_protection == 50, "be careful");
        require(nextTokenIndex == MAX_TOKEN_SUPPLY, "cannot lock");
        foreverLocked = 1;
    }

    // this function has a foreverLock because we don't want the values 
    // to change after the shuffle
    function receiveValues(uint16[] calldata _shuffle, uint16 _offset)
        external
        onlyOwner
    {
        require(foreverLocked == 0, "ForeverLocked");
        for (uint256 i = 0; i < _shuffle.length; i++) {
            nftToImageMapping[_offset + i] = _shuffle[i];
        }
    }

    function setPrivateMintAddress(address _address) external onlyOwner {
        require(_address != address(0), "zero address");
        require(_address != publicMintingAddress, "not allowed");
        privateMintingAddress = _address;
    }

    function setPublicMintAddress(address _address) external onlyOwner {
        require(_address != address(0), "zero address");
        publicMintingAddress = _address;
    }

    // it saves gas to make this variable private, so now we have to add a getter
    function getPublicMintingAddress()
        external
        view
        onlyOwner
        returns (address)
    {
        return publicMintingAddress;
    }

    function getPrivateMintingAddress()
        external
        view
        onlyOwner
        returns (address)
    {
        return privateMintingAddress;
    }

    function setRoyaltyBasisPoints(uint32 _royaltyBasisPoints)
        external
        onlyOwner
    {
        require(_royaltyBasisPoints < 5001, "invalid royalty");
        royaltyBasisPoints = _royaltyBasisPoints;
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawLink() external onlyOwner {
        bool success = LINK.transfer(msg.sender, LINK.balanceOf(address(this)));
        require(success, "withdraw failed");
    }

    function privateMint(bytes calldata _signature, uint32 _amount)
        external
        onlyOwner
    {
        uint256 _nextTokenIndex = nextTokenIndex;
        require(_nextTokenIndex + _amount < MAX_TOKEN_SUPPLY, "max supply");
        require(
            privateMintingAddress ==
                bytes32(uint256(uint160(msg.sender)))
                    .toEthSignedMessageHash()
                    .recover(_signature),
            "not allowed"
        );

        for (uint256 i = 0; i < _amount; i++) {
            _mint(msg.sender, _nextTokenIndex);
            unchecked {
                _nextTokenIndex++;
            }
        }
        nextTokenIndex = _nextTokenIndex;
    }

    function claimTicketOrRevertIfClaimed(uint256 ticketNumber) private {
        require(ticketNumber < NUMBER_OF_GROUPS * 256, "haxx0r ~(c001)");
        uint256 storageOffset;
        uint256 offsetWithin256;
        uint256 localGroup;
        uint256 storedBit;
        unchecked {
            storageOffset = ticketNumber / 256;
            offsetWithin256 = ticketNumber % 256;
        }
        
        //solhint-disable-next-line no-inline-assembly
        assembly {
            storageOffset := add(group00.slot, storageOffset)
            localGroup := sload(storageOffset)
        }
 
        storedBit = (localGroup >> offsetWithin256) & uint256(1);
        require(storedBit == 1, "already taken");
        localGroup = localGroup & ~(uint256(1) << offsetWithin256);

        //solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(storageOffset, localGroup)
        }
    }

    function presale(bytes[] calldata _signatureAddressAndTicketNumbers, uint256[] calldata ticketNumbers) external payable {
        uint256 _nextTokenIndex = nextTokenIndex; // uint256 private nextTokenIndex = 1;
        require(_nextTokenIndex + ticketNumbers.length < MAX_TOKEN_SUPPLY, "max supply"); // because 7778 - 1 = 7777
        require(msg.value == (0.06 ether) * ticketNumbers.length, "wrong price");

        for (uint256 i = 0; i < ticketNumbers.length; i++) {
            require(
                publicMintingAddress ==
                    keccak256(
                        abi.encodePacked(
                            "\x19Ethereum Signed Message:\n32",
                            bytes32(abi.encode(msg.sender, ticketNumbers[i]))
                        )
                    ).recover(_signatureAddressAndTicketNumbers[i]),
                "not allowed"
            );
            claimTicketOrRevertIfClaimed(ticketNumbers[i]); // we have to check the ticket numbers one by one
            // require(msg.sender == tx.origin); not needed because each mint requires a ticket
            
            _mint(msg.sender, _nextTokenIndex);
            unchecked {
                _nextTokenIndex++;
            }           
        }
        nextTokenIndex = _nextTokenIndex; 
    }

    // https://medium.com/donkeverse/hardcore-gas-savings-in-nft-minting-part-1-16c66a88c56a
    // https://medium.com/donkeverse/hardcore-gas-savings-in-nft-minting-part-2-signatures-vs-merkle-trees-917c43c59b07
    // https://github.com/DonkeVerse/GasContest
    function publicMint(bytes calldata _signature) external payable {
        uint256 _nextTokenIndex = nextTokenIndex; // uint256 private nextTokenIndex = 1;
        require(_nextTokenIndex < MAX_TOKEN_SUPPLY, "max supply"); // because 7778 - 1 = 7777
        require(
            publicMintingAddress ==
                keccak256(
                    abi.encodePacked(
                        "\x19Ethereum Signed Message:\n32",
                        bytes32(uint256(uint160(msg.sender)))
                    )
                ).recover(_signature),
            "not allowed"
        );
        require(msg.value == 0.06 ether, "wrong price");

        // someone could try to mint and transfer away the NFT in 
        // the same transaction which defeats balanceOf if they 
        // use a smart contract. This prevents that. We don't try 
        // to prevent people from transfering and then minting again 
        // because they can use another wallet in parallel anyway
        // solhint-disable-next-line avoid-tx-origin
        require(msg.sender == tx.origin, "no bots");
        require(balanceOf(msg.sender) < 2, "too many");

        _mint(msg.sender, _nextTokenIndex);
        unchecked {
            _nextTokenIndex++;
        }
        nextTokenIndex = _nextTokenIndex;

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

    // random number functions
    function getRandomNumber() external onlyOwner returns (bytes32 requestId) {
        require(foreverLocked == 0, "ForeverLocked");
        require(nextTokenIndex == MAX_TOKEN_SUPPLY, "too early");
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

    function totalSupply() external view returns (uint256) {
        return nextTokenIndex - 1; // token supply is 1 when nothing has been minted
    }

    // royalty functions
    // Rarible updates the per id royalty during mint, 
    // but we have the same royalty across the entire collection. 
    // So to save gas during mint, we just hardcode the
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

    // Due to gas costs, we cannot shuffle on chain, 
    // because we will take up a lot of gas block limit!
    // So instead, we get the random number seed on chain,
    // execute the shuffle offchain, and upload the
    // results. People need to know the shuffle algorithm 
    // and its interaction with the random seed was fixed in 
    // advance, so we publish it here. Token zero is not part 
    // of the shuffle because it is not a token.

    function referenceShuffle(uint256 _seed)
        public
        pure
        returns (uint16[MAX_TOKEN_SUPPLY] memory)
    {
        uint16[MAX_TOKEN_SUPPLY] memory initialState;
        for (uint16 i = 0; i < initialState.length; i++) {
            initialState[i] = i;
        }

        uint256 randomState256 = _seed;
        uint256 j;

        // skip zero, because it is not used
        for (uint256 i = MAX_TOKEN_SUPPLY - 1; i > 1; i--) {
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

    // Don't call this function from a smart contract or you 
    // are basically guaranteed to run out of gas
    // Don't call this before the random number is called.
    // Call this function after we reveal
    function wereWeHonest() external view returns (bool) {
        uint16[MAX_TOKEN_SUPPLY] memory shuffleResult = referenceShuffle(
            verifiedRandomResult
        );
        for (uint256 i = 1; i < MAX_TOKEN_SUPPLY; i++) {
            if (shuffleResult[i] != nftToImageMapping[i]) {
                return false;
            }
        }
        return true;
    }
}
