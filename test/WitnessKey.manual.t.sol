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

contract WkManualTest is Test {
    MockCbBTC cbbtc;
    WitnessKey wk;

    address o = address(this);
    address a = makeAddr("a");
    address b = makeAddr("b");

    function setUp() public {
        cbbtc = new MockCbBTC();
        wk = new WitnessKey(address(cbbtc));

        cbbtc.mint(o, 1000000);
        cbbtc.mint(a, 1000000);
        cbbtc.mint(b, 1000000);

        cbbtc.approve(address(wk), type(uint256).max);
        vm.prank(a);
        cbbtc.approve(address(wk), type(uint256).max);
        vm.prank(b);
        cbbtc.approve(address(wk), type(uint256).max);
    }

    function test() public {
        assertCbbtcBalance(1000000, 1000000, 1000000, 0);
        assertWkBalance(0, 0, 0, 0);
        assertRecirculations(0, 0, 0);

        vm.prank(a);
        wk.acquire(1000, 0);
        assertCbbtcBalance(1000000, 999000, 1000000, 1000);
        assertWkBalance(0, 1000, 0, 1000);
        assertRecirculations(0, 0, 0);

        vm.prank(a);
        wk.transfer(b, 100);
        assertCbbtcBalance(1000000, 999000, 1000000, 1000);
        assertWkBalance(0, 900, 100, 1000);
        assertRecirculations(0, 0, 0);

        vm.prank(b);
        wk.acquire(1000, 0);
        assertCbbtcBalance(1000000, 999000, 999000, 2000);
        assertWkBalance(0, 900, 1030, 1930);
        assertRecirculations(0, 62, 7);

        vm.prank(b);
        wk.transfer(b, 200);
        assertCbbtcBalance(1000000, 999000, 999000, 2000);
        assertWkBalance(0, 900, 1030, 1930);
        assertRecirculations(0, 62, 7);

        vm.prank(b);
        wk.transfer(a, 250);
        assertCbbtcBalance(1000000, 999000, 999000, 2000);
        assertWkBalance(0, 1150, 780, 1930);
        assertRecirculations(0, 63, 6);

        vm.prank(a);
        wk.dispose(150, 0);
        assertCbbtcBalance(1000000, 999140, 999000, 1860);
        assertWkBalance(0, 1000, 780, 1780);
        assertRecirculations(0, 68, 10);

        wk.acquire(30000, 0);
        assertCbbtcBalance(970000, 999140, 999000, 31860);
        assertWkBalance(27900, 1000, 780, 29680);
        assertRecirculations(0, 1248, 931);

        vm.prank(a);
        wk.recirculate();
        assertCbbtcBalance(970000, 999140, 999000, 31860);
        assertWkBalance(27900, 2248, 780, 30928);
        assertRecirculations(0, 1, 931);

        vm.prank(b);
        wk.dispose(180, 0);
        assertCbbtcBalance(970000, 999140, 999168, 31692);
        assertWkBalance(27900, 2248, 600, 30748);
        assertRecirculations(11, 2, 930);

        wk.acquire(18000, 0);
        assertCbbtcBalance(952000, 999140, 999168, 49692);
        assertWkBalance(44640, 2248, 600, 47488);
        assertRecirculations(1155, 94, 955);

        vm.prank(a);
        wk.acquire(180000, 0);
        assertCbbtcBalance(952000, 819140, 999168, 229692);
        assertWkBalance(44640, 169648, 600, 214888);
        assertRecirculations(12999, 690, 1114);

        wk.claim();
        assertCbbtcBalance(964999, 819140, 999168, 216693);
        assertWkBalance(44640, 169648, 600, 214888);
        assertRecirculations(0, 690, 1114);

        vm.prank(a);
        wk.recirculate();
        assertCbbtcBalance(964999, 819140, 999168, 216693);
        assertWkBalance(44640, 170338, 600, 215578);
        assertRecirculations(0, 1, 1114);

        wk.dispose(44640, 0);
        assertCbbtcBalance(1006515, 819140, 999168, 175177);
        assertWkBalance(0, 170338, 600, 170938);
        assertRecirculations(0, 3114, 1125);

        vm.prank(a);
        wk.dispose(170338, 0);
        assertCbbtcBalance(1006515, 977555, 999168, 16762);
        assertWkBalance(0, 0, 600, 600);
        assertRecirculations(0, 3114, 13048);

        vm.prank(b);
        wk.dispose(599, 0);
        assertCbbtcBalance(1006515, 977555, 999726, 16204);
        assertWkBalance(0, 0, 1, 1);
        assertRecirculations(0, 3114, 13088);

        vm.prank(b);
        wk.claim();
        assertCbbtcBalance(1006515, 977555, 1012814, 3116);
        assertWkBalance(0, 0, 1, 1);
        assertRecirculations(0, 3114, 0);

        vm.prank(a);
        wk.claim();
        assertCbbtcBalance(1006515, 980669, 1012814, 2);
        assertWkBalance(0, 0, 1, 1);
        assertRecirculations(0, 0, 0);
    }

    function assertCbbtcBalance(uint256 cbbtcO, uint256 cbbtcA, uint256 cbbtcB, uint256 cbbtcWk) private view {
        assertEq(cbbtc.balanceOf(o), cbbtcO);
        assertEq(cbbtc.balanceOf(a), cbbtcA);
        assertEq(cbbtc.balanceOf(b), cbbtcB);
        assertEq(cbbtc.balanceOf(address(wk)), cbbtcWk);
    }

    function assertWkBalance(uint256 wkO, uint256 wkA, uint256 wkB, uint256 wkTotal) private view {
        assertEq(wk.balanceOf(o), wkO);
        assertEq(wk.balanceOf(a), wkA);
        assertEq(wk.balanceOf(b), wkB);
        assertEq(wk.totalSupply(), wkTotal);
    }

    function assertRecirculations(uint256 divO, uint256 divA, uint256 divB) private view {
        assertEq(wk.recirculationOf(o), divO);
        assertEq(wk.recirculationOf(a), divA);
        assertEq(wk.recirculationOf(b), divB);
    }
}
