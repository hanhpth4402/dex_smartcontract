// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

library Math {
    function abs(uint x, uint y) internal pure returns (uint) {
        return x >= y ? x - y : y - x;
    }
}

contract StableSwap {
    address [2] public tokenList;
    uint [2] public reserves;
    uint public shareSupply;
    uint private constant N = 2;
    uint private constant A = 85 * (N ** (N - 1));

    constructor(address _token1, address _token2, uint[N] memory initReserves) {
        tokenList = [_token1, _token2];
        reserves[0] = initReserves[0];
        reserves[1] = initReserves[1];
    }

    function _getD(uint[N] memory _reserves) private pure returns (uint) {
        uint a = A * N; // An^n
        uint s; // x_0 + x_1 + ... + x_(n-1)
        uint p = 1; // x_0 * x_1 * .... * x_(n-1)
        for (uint i; i < N; ++i) {
            s += _reserves[i];
            p *= _reserves[i];
        }
        uint d = s;
        uint d_prev;
        for (uint i; i < 255; ++i) {
            uint Dn = 1;
            uint Dn1 = d;
            uint An2n = a;
            uint nn = 1;
            for (uint j; j < N; ++j) {
                Dn *= d;
                Dn1 *= d;
                An2n *= N;
                nn *= N;
            }
            d_prev = d;
            d = (N*Dn1 + An2n*p*s) / ((N+1)*Dn + An2n*p-nn*p);

            if (Math.abs(d, d_prev) <= 1) {
                return d;
            }
        }
        revert("D didn't converge");
    }

    function _getY(uint i, uint j, uint x, uint[N] memory _reserves) private pure returns (uint) {
        uint a = A * N;
        uint d = _getD(_reserves);
        uint sk;
        uint c = d;
        uint _x;
        for (uint k; k < N; ++k) {
            if (k == i)  _x = x;
            if (k == j) continue;
            else _x = _reserves[k];

            sk += _x;
            c = (c * d) / (N * _x);
        }
        c = (c * d) / (N * a);
        uint b = sk + d / a;
        uint prev_y;
        uint y = d;
        for (uint _i; _i < 255; ++_i) {
            prev_y = y;
            y = (y * y + c) / (2 * y + b - d);
            if (Math.abs(y, prev_y) <= 1) {
                return y;
            }
        }
        revert("y didn't converge");
    }

    function getCurrentD () public view returns (uint d) {
        d = _getD(reserves);
    }

    function getAmountOut (uint i, uint j, uint dx) public view returns (uint amountOut) {
        uint[N] memory _reserves = reserves;
        uint x = _reserves[i] + dx;
        uint y0 = _reserves[j];
        uint y1 = _getY(i, j, x, _reserves);
        amountOut = (y0 - y1 - 1);
    }


    function swap(uint i, uint j, uint dx, uint minDy) external returns (uint dy, uint y, uint d, uint) {
        require(i != j, "i = j");

        IERC20(tokenList[i]).transferFrom(msg.sender, address(this), dx);
        uint[N] memory _reserves = reserves;
        uint x = _reserves[i] + dx;

        uint y0 = _reserves[j];
        d = _getD(_reserves);
        uint y1 = _getY(i, j, x, _reserves);
        dy = (y0 - y1 - 1);

        // Subtract fee from dy
        require(dy >= minDy, "dy < min");

        reserves[i] += dx;
        reserves[j] -= dy;

        IERC20(tokenList[j]).transfer(msg.sender, dy);
        return (dy, y1, d, A);
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);
}
