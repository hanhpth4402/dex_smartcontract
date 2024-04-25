pragma solidity ^0.8;

library Math {
    function abs(uint x, uint y) internal pure returns (uint) {
        return x >= y ? x - y : y - x;
    }
}

contract StableSwap {
    uint private constant N = 2;
    uint private constant A = 85 * (N ** (N - 1));

    address[N] public tokens;
    uint[N] public balances;

    uint private constant DECIMALS = 18;
    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    constructor(address _token1, address _token2) {
        tokens = [_token1, _token2];
    }

    function _mint(address _to, uint _amount) private {
        balanceOf[_to] += _amount;
        totalSupply += _amount;
    }

    function _burn(address _from, uint _amount) private {
        balanceOf[_from] -= _amount;
        totalSupply -= _amount;
    }

    function _getD(uint[N] memory _balances) private pure returns (uint) {
        uint a = A * N; // An^n
        uint s; // x_0 + x_1 + ... + x_(n-1)
        uint p = 1; // x_0 * x_1 * .... * x_(n-1)
        for (uint i; i < N; ++i) {
            s += _balances[i];
            p *= _balances[i];
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

    function _getY(uint i, uint j, uint x, uint[N] memory _balances) private pure returns (uint) {
        uint a = A * N;
        uint d = _getD(_balances);
        uint s;
        uint c = d;
        uint _x;
        for (uint k; k < N; ++k) {
            if (k == i) {
                _x = x;
            } else if (k == j) {
                continue;
            } else {
                _x = _balances[k];
            }

            s += _x;
            c = (c * d) / (N * _x);
        }
        c = (c * d) / (N * a);
        uint b = s + d / a;

        uint y_prev;
        uint y = d;
        for (uint _i; _i < 255; ++_i) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - d);
            if (Math.abs(y, y_prev) <= 1) {
                return y;
            }
        }
        revert("y didn't converge");
    }

    function getCurrentD () public view returns (uint d) {
        d = _getD(balances);
    }

    function getAmountOut (uint i, uint j, uint dx) public view returns (uint amountOut) {
        uint[N] memory _balances = balances;
        uint x = _balances[i] + dx;
        uint y0 = _balances[j];
        uint y1 = _getY(i, j, x, _balances);
        amountOut = (y0 - y1 - 1);
    }

    function getVirtualPrice() external view returns (uint) {
        uint d = _getD(balances);
        uint _totalSupply = totalSupply;
        if (_totalSupply > 0) {
            return (d * 10 ** DECIMALS) / _totalSupply;
        }
        return 0;
    }

    function swap(uint i, uint j, uint dx, uint minDy) external returns (uint dy, uint y, uint d, uint) {
        require(i != j, "i = j");

        IERC20(tokens[i]).transferFrom(msg.sender, address(this), dx);

        // Calculate dy
        uint[N] memory _balances = balances;
        uint x = _balances[i] + dx;

        uint y0 = _balances[j];
        d = _getD(_balances);
        uint y1 = _getY(i, j, x, _balances);
        // y0 must be >= y1, since x has increased
        // -1 to round down
        dy = (y0 - y1 - 1);

        // Subtract fee from dy
        require(dy >= minDy, "dy < min");

        balances[i] += dx;
        balances[j] -= dy;

        IERC20(tokens[j]).transfer(msg.sender, dy);
        return (dy, y1, d, A);
    }

    function addLiquidity(
        uint[N] calldata amounts,
        uint minShares
    ) external returns (uint shares) {
        uint _totalSupply = totalSupply;
        uint d0;
        uint[N] memory old_xs = balances;
        if (_totalSupply > 0) {
            d0 = _getD(old_xs);
        }
        uint[N] memory new_xs;
        for (uint i; i < N; ++i) {
            uint amount = amounts[i];
            if (amount > 0) {
                IERC20(tokens[i]).transferFrom(msg.sender, address(this), amount);
                new_xs[i] = old_xs[i] + amount;
            } else {
                new_xs[i] = old_xs[i];
            }
        }
        uint d1 = _getD(new_xs);
        require(d1 > d0, "liquidity didn't increase");
        for (uint i; i < N; ++i) {
            balances[i] += amounts[i];
        }
        if (_totalSupply > 0) {
            shares = ((d1 - d0) * _totalSupply) / d0;
        } else {
            shares = d1;
        }
        require(shares >= minShares, "shares < min");
        _mint(msg.sender, shares);
    }

    function removeLiquidity(
        uint shares,
        uint[N] calldata minAmountsOut
    ) external returns (uint[N] memory amountsOut) {
        uint _totalSupply = totalSupply;
        for (uint i; i < N; ++i) {
            uint amountOut = (balances[i] * shares) / _totalSupply;
            require(amountOut >= minAmountsOut[i], "out < min");

            balances[i] -= amountOut;
            amountsOut[i] = amountOut;

            IERC20(tokens[i]).transfer(msg.sender, amountOut);
        }

        _burn(msg.sender, shares);
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
