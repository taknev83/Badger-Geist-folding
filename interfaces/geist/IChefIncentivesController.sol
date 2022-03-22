// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IChefIncentivesController {
    function claim(address _user, address[] calldata _tokens) external;

}
