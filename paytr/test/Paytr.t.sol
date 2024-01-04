// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Paytr} from "../src/Paytr.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IComet {
    function supply(address asset, uint amount) external;
    function withdraw(address asset, uint amount) external;
    function baseToken() external view returns (address);
    function allow(address manager, bool isAllowed) external;
}

struct PaymentERC20 {
    uint256 amount;
    uint256 feeAmount;
    uint256 dueDate;
    uint256 wrapperSharesReceived;
    address payer;
    address payee;
    address feeAddress;
    bool shouldPayoutViaRequestNetwork;
}

contract PaytrTest is Test {
    using SafeERC20 for IERC20;

    Paytr Paytr_Test;

    IERC20 comet = IERC20(0xF09F0369aB0a875254fB565E52226c88f10Bc839);
    IERC20 baseAsset = IERC20(IComet(0xF09F0369aB0a875254fB565E52226c88f10Bc839).baseToken());
    address baseAssetAddress = IComet(0xF09F0369aB0a875254fB565E52226c88f10Bc839).baseToken();
    IERC20 cometWrapper = IERC20(0x797D7126C35E0894Ba76043dA874095db4776035);

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address dummyFeeAddress = address(0x4);

    bytes[] payOutArray;
    mapping(bytes => PaymentERC20) public paymentMapping;

    event PaymentERC20Event(address tokenAddress, address payee, address feeAddress, uint256 amount, uint256 dueDate, uint256 feeAmount, bytes paymentReference);
    event PayOutERC20Event(address tokenAddress, address payee, address feeAddress, uint256 amount, bytes paymentReference, uint256 feeAmount);
    event InterestPayoutEvent(address tokenAddress, address payee, uint256 interestAmount, bytes paymentReference);

    function getContractCometWrapperBalance() public view returns(uint256) {
    uint256 contractCometWrapperBalance = cometWrapper.balanceOf(address(Paytr_Test));
    return contractCometWrapperBalance;
    }

    function getAlicesBaseAssetBalance() public view returns(uint256) {
        uint256 alicesBaseAssetBalance = baseAsset.balanceOf(alice);
        return alicesBaseAssetBalance;
    }
    
    function getBobsBaseAssetBalance() public view returns(uint256) {
        uint256 bobsBaseAssetBalance = baseAsset.balanceOf(bob);
        return bobsBaseAssetBalance;
    }
    function getCharliesBaseAssetBalance() public view returns(uint256) {
        uint256 charliesBaseAssetBalance = baseAsset.balanceOf(charlie);
        return charliesBaseAssetBalance;
    }

    function setUp() public {
        Paytr_Test = new Paytr(
            0xF09F0369aB0a875254fB565E52226c88f10Bc839,
            0x797D7126C35E0894Ba76043dA874095db4776035,
            9000,
            7 days,
            365 days,
            10e6,
            100_000e6,
            30
        );

        //deal baseAsset
        deal(address(baseAsset), alice, 10_000e6);
        uint256 balanceAlice = baseAsset.balanceOf(alice);
        assertEq(balanceAlice, 10_000e6);
        deal(address(baseAsset), bob, 10_000e6);
        uint256 balanceBob = baseAsset.balanceOf(bob);
        assertEq(balanceBob, 10_000e6);
        deal(address(baseAsset), charlie, 10_000e6);
        uint256 balanceCharlie = baseAsset.balanceOf(charlie);
        assertEq(balanceCharlie, 10_000e6);

        //approve baseAsset to contract
        vm.startPrank(alice);
        baseAsset.approve(address(Paytr_Test), 2**256 - 1);
        vm.stopPrank();
        vm.startPrank(bob);
        baseAsset.approve(address(Paytr_Test), 2**256 - 1);
        vm.stopPrank();
    }

    function test_payInvoiceERC20Single() public {

        uint256 amountToPay = 1000e6;
        vm.expectEmit(false, false, false, true); //theres is only topic[0] in the logs (no indexed parameters), which is automatically tested by Foundry.


        assert(baseAsset.allowance(alice, address(Paytr_Test)) > 1000e6);
        vm.prank(alice);
        Paytr_Test.payInvoiceERC20(
            bob,
            dummyFeeAddress,
            block.timestamp + 10 days,
            amountToPay,
            0,
            "0x494e56332d32343001",
            false
        );
        emit PaymentERC20Event(baseAssetAddress, bob, dummyFeeAddress, amountToPay, block.timestamp + 10 days, 0, "0x494e56332d32343001");

        //baseAsset balances
        assertEq(getAlicesBaseAssetBalance(), 10000e6 - amountToPay);
        assertEq(getBobsBaseAssetBalance(), 10000e6);
        assertEq(getCharliesBaseAssetBalance(), 10000e6);
        assertEq(baseAsset.balanceOf(dummyFeeAddress), 0);
        assertEq(baseAsset.balanceOf(address(Paytr_Test)), 0);

        //comet (cbaseAssetv3) balances
        assertEq(comet.balanceOf(alice), 0);
        assertEq(comet.balanceOf(bob), 0);
        assertEq(comet.balanceOf(charlie), 0);
        assertEq(comet.balanceOf(dummyFeeAddress), 0);
        assertEq(comet.balanceOf(address(Paytr_Test)), 0);       
        
        //cometWrapper (wcbaseAssetv3) balances
        assertApproxEqRel(getContractCometWrapperBalance(), amountToPay, 0.1e18);

        console2.log(paymentMapping["0x494e56332d32343001"].amount);

    }

    function test_payInvoiceERC20Double() public {

        uint256 amountToPay = 1000e6;

        assert(baseAsset.allowance(alice, address(Paytr_Test)) > 1000e6);
        assert(baseAsset.allowance(bob, address(Paytr_Test)) > 1000e6);
        vm.startPrank(alice);
        Paytr_Test.payInvoiceERC20(
            bob,
            dummyFeeAddress,
            block.timestamp + 10 days,
            amountToPay,
            0,
            "0x494e56332d32343001",
            false
        );
        vm.stopPrank();

        //baseAsset balances
        assertEq(getAlicesBaseAssetBalance(), 10000e6 - amountToPay);
        assertEq(getBobsBaseAssetBalance(), 10000e6);
        assertEq(getCharliesBaseAssetBalance(), 10000e6);
        assertEq(baseAsset.balanceOf(dummyFeeAddress), 0);
        assertEq(baseAsset.balanceOf(address(Paytr_Test)), 0);
        
        //comet (cbaseAssetv3) balances
        assertEq(comet.balanceOf(alice), 0);
        assertEq(comet.balanceOf(bob), 0);
        assertEq(comet.balanceOf(charlie), 0);
        assertEq(comet.balanceOf(dummyFeeAddress), 0);
        assertEq(comet.balanceOf(address(Paytr_Test)), 0);       
        
        //cometWrapper (wcbaseAssetv3) balances
        assertApproxEqRel(getContractCometWrapperBalance(), amountToPay, 0.1e18);

        uint256 contractCometWrapperBalanceBeforeSecondPayment = getContractCometWrapperBalance();

        vm.startPrank(bob);
        Paytr_Test.payInvoiceERC20(
            charlie,
            dummyFeeAddress,
            block.timestamp + 10 days,
            amountToPay,
            0,
            "0x494e56332d32343002",
            false       
        );
        vm.stopPrank();

        uint256 contractCometWrapperBalanceAfterSecondPayment = getContractCometWrapperBalance();

        //baseAsset balances
        assertEq(getBobsBaseAssetBalance(), 10000e6 - amountToPay);
        assertEq(getCharliesBaseAssetBalance(), 10000e6);
        assertEq(baseAsset.balanceOf(address(Paytr_Test)), 0);

        //comet (cbaseAssetv3) balances
        assertEq(comet.balanceOf(alice), 0);
        assertEq(comet.balanceOf(bob), 0);
        assertEq(comet.balanceOf(charlie), 0);
        assertEq(comet.balanceOf(address(Paytr_Test)), 0);          
        
        //cometWrapper (wcbaseAssetv3) balances
        assertApproxEqRel(contractCometWrapperBalanceAfterSecondPayment, contractCometWrapperBalanceBeforeSecondPayment + amountToPay, 0.1e18);

    }

    function test_payAndRedeemSingle() public {
        test_payInvoiceERC20Single();
        uint256 amountToPay = 1000e6;

        // vm.prank(alice);
        // Paytr_Test.payInvoiceERC20(
        //     bob,
        //     dummyFeeAddress,
        //     block.timestamp + 10 days,
        //     amountToPay,
        //     0,
        //     "0x494e56332d32343001",
        //     false
        // );

        //vm.expectEmit(false, false, false, true);    
        
        //increase time to gain interest
        vm.warp(block.timestamp + 120 days);

        //redeem
        payOutArray.push("0x494e56332d32343001");
        Paytr_Test.payOutERC20Invoice(payOutArray);
        //console2.log(paymentMapping["0x494e56332d32343001"].amount);
        
        // emit PayOutERC20Event(
        //     baseAssetAddress,
        //     //paymentMapping["0x494e56332d32343001"].payee,
        //     bob,
        //     //paymentMapping["0x494e56332d32343001"].feeAddress,
        //     dummyFeeAddress,
        //     //paymentMapping["0x494e56332d32343001"].amount,
        //     amountToPay,
        //     "0x494e56332d32343001",
        //     0
        // );
        
        //baseAsset balances
        assert(getAlicesBaseAssetBalance() > 10000e6 - amountToPay); //alice receives interest after the payOutERC20Invoice has been called
        assertEq(getBobsBaseAssetBalance(), 10000e6 + amountToPay);
        assertEq(getCharliesBaseAssetBalance(), 10000e6);
        assert(baseAsset.balanceOf(address(Paytr_Test)) > 0); //the contract receives 10% of the interest amount as fee (param 9000 in setUp)

    }

}
