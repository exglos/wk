pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {WitnessKey} from "../src/WitnessKey.sol";

contract MockCbBTC is ERC20 {
    constructor() ERC20("Coinbase Wrapped BTC", "cbBTC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 8;
    }
}

contract WkHandler is Test {
    MockCbBTC cbbtc;
    WitnessKey wk;

    uint16 holdersN = 10;
    address[] holders; // including vaults
    uint256 constant MAGNITUDE = 2 ** 64;
    mapping(address => uint256) scaledRecirculationsOf;

    constructor() {
        cbbtc = new MockCbBTC();
        wk = new WitnessKey(address(cbbtc));

        for (uint16 i = 0; i < holdersN; i++) {
            address holder = i == 0 ? address(this) : makeAddr(vm.toString(i));
            holders.push(holder);
            cbbtc.mint(holder, 1e12);
            vm.prank(holder);
            cbbtc.approve(address(wk), type(uint256).max);
        }

        wk.acquire(100, 0);
    }

    function acquire(uint256 senderN, uint256 cbbtcAmount) public {
        address sender = holders[senderN % holdersN];
        cbbtcAmount = cbbtcAmount % 999901 + 100;
        uint256 totalSupply = wk.totalSupply();
        uint256 addScaledRecirculations = cbbtcAmount * 7 / 100 * MAGNITUDE;
        for (uint16 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            scaledRecirculationsOf[holder] += addScaledRecirculations * wk.balanceOf(holder) / totalSupply;
        }

        vm.prank(sender);
        wk.acquire(cbbtcAmount, 0);
    }

    function dispose(uint256 senderN, uint256 wkAmount) public {
        address sender = holders[senderN % holdersN];
        vm.assume(wk.balanceOf(sender) >= 100);
        wkAmount = wkAmount % (wk.balanceOf(sender) - 99) + 100;
        uint256 totalSupply = wk.totalSupply();
        vm.assume(wkAmount < totalSupply);
        uint256 addScaledRecirculations = wkAmount * 7 / 100 * MAGNITUDE;

        vm.prank(sender);
        wk.dispose(wkAmount, 0);

        for (uint16 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            scaledRecirculationsOf[holder] += addScaledRecirculations * wk.balanceOf(holder) / totalSupply;
        }
    }

    function transfer(uint256 senderN, uint256 recipientN, uint256 wkAmount) public {
        address sender = holders[senderN % holdersN];
        address recipient = holders[recipientN % holdersN];
        vm.assume(wk.balanceOf(sender) > 0);
        wkAmount = wkAmount % wk.balanceOf(sender) + 1;

        vm.prank(sender);
        wk.transfer(recipient, wkAmount);
    }

    function claim(uint256 senderN) public {
        address sender = holders[senderN % holdersN];
        vm.assume(wk.recirculationOf(sender) > 0);
        scaledRecirculationsOf[sender] = 0;

        vm.prank(sender);
        wk.claim();
    }

    function recirculate(uint256 senderN) public {
        address sender = holders[senderN % holdersN];
        vm.assume(wk.recirculationOf(sender) >= 100);
        scaledRecirculationsOf[sender] = 0;

        vm.prank(sender);
        wk.recirculate();
    }

    function inscribe(
        address vault,
        bytes32 assetId,
        uint256 cbbtcAmount,
        uint256 ordinalNumber,
        string calldata inscriptionId
    ) public {
        vm.assume(vault != address(0));
        vm.assume(!wk.isVault(vault));
        vm.assume(assetId != bytes32(0));
        cbbtcAmount = cbbtcAmount % 999901 + 100;
        if (ordinalNumber > 0) {
            vm.assume(wk.ordinalVaultAddress(ordinalNumber) == address(0));
        }
        uint256 totalSupply = wk.totalSupply();
        uint256 addScaledRecirculations = cbbtcAmount * 7 / 100 * MAGNITUDE;
        for (uint16 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            scaledRecirculationsOf[holder] += addScaledRecirculations * wk.balanceOf(holder) / totalSupply;
        }
        holders.push(vault);

        wk.inscribe(vault, assetId, cbbtcAmount, ordinalNumber, inscriptionId);
    }

    function checkRecirculations() public view {
        uint256 sumWk = 0;
        uint256 sumRecirculations = 0;
        for (uint16 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            sumWk += wk.balanceOf(holder);

            uint256 recirculations = wk.recirculationOf(holder);
            assertApproxEqAbs(recirculations, scaledRecirculationsOf[holder] / MAGNITUDE, 3000);
            sumRecirculations += recirculations;
        }

        assertEq(wk.totalSupply(), sumWk);
        assertApproxEqAbs(cbbtc.balanceOf(address(wk)), sumWk + sumRecirculations, 10000);
    }
}

/// forge-config: default.invariant.runs = 1
/// forge-config: default.invariant.depth = 100
/// forge-config: default.invariant.fail_on_revert = true
contract WkTest is Test {
    WkHandler handler;

    function setUp() public {
        handler = new WkHandler();
        targetContract(address(handler));
    }

    function invariant_recirculations() public view {
        handler.checkRecirculations();
    }
}
