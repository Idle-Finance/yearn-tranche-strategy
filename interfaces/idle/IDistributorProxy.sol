// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

interface IDistributorProxy {
    function distribute(address gauge) external;

    function distributor() external view returns (address);
}
