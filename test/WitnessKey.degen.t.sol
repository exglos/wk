pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {WitnessKey} from "../src/WitnessKey.sol";

contract MockCbBTC is ERC20 {
    constructor() ERC20("Coinbase Wrapped BTC", "cbBTC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract WitnessKeyDegenTest is Test {
    MockCbBTC cbbtc;
    WitnessKey wk;

    address a = makeAddr("a");
    address b = makeAddr("b");
    address c = makeAddr("c");

    function setUp() public {
        cbbtc = new MockCbBTC();
        wk = new WitnessKey(address(cbbtc));

        cbbtc.mint(a, 1000000);
        cbbtc.mint(b, 1000000);

        vm.prank(a);
        cbbtc.approve(address(wk), type(uint256).max);
        vm.prank(b);
        cbbtc.approve(address(wk), type(uint256).max);
    }

    function test_transfer_one() public {
        vm.prank(a);
        wk.acquire(100000, 0);
        vm.prank(b);
        wk.acquire(100000, 0);
        assertEq(cbbtc.balanceOf(b), 900000);
        assertEq(wk.balanceOf(b), 93000);
        assertEq(wk.recirculationOf(b), 0);

        uint256 sumClaimable = wk.recirculationOf(b) + wk.recirculationOf(c);
        assertEq(sumClaimable, 0);

        for (uint256 i = 0; i < 1000; i++) {
            vm.prank(b);
            wk.transfer(c, 1);
        }

        assertEq(wk.balanceOf(b), 92000);
        assertEq(wk.balanceOf(c), 1000);

        assertGe(sumClaimable, wk.recirculationOf(b) + wk.recirculationOf(c));
    }
}
