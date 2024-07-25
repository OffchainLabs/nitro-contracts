// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RoundTimingInfo} from "./RoundTimingInfo.sol";
import {ELCRound} from "./ELCRound.sol";
import {
    IAccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/IAccessControlEnumerableUpgradeable.sol";
import {
    IERC165Upgradeable
} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

/// @notice A bid to control the express lane for a specific round
struct Bid {
    /// @notice The address to be set as the express lane controller if this bid wins the auction round
    address expressLaneController;
    /// @notice The maximum amount the bidder is willing to pay if they win the round
    ///         The auction is a second price auction, so the winner may end up paying less than this amount
    ///         however this is the maximum amount up to which they may have to pay
    uint256 amount;
    /// @notice Authentication of this bid by the bidder.
    ///         The bidder signs over a hash of the following
    ///         keccak256("\x19Ethereum Signed Message:\n144" ++ keccak256("TIMEBOOST_BID") ++ chainId ++ auctionContractAddress ++ auctionRound ++ bidAmount ++ expressLaneController)
    bytes signature;
}

interface IExpressLaneAuction is IAccessControlEnumerableUpgradeable, IERC165Upgradeable {
    /// @notice An account has deposited funds to be used for bidding in the auction
    /// @param account The account that deposited funds
    /// @param amount The amount deposited by that account
    event Deposit(address indexed account, uint256 amount);

    /// @notice An account has initiated a withdrawal of funds from the auction
    /// @param account The account withdrawing the funds
    /// @param withdrawalAmount The amount beind withdrawn
    /// @param roundWithdrawable The round the funds will become withdrawable in
    event WithdrawalInitiated(
        address indexed account,
        uint256 withdrawalAmount,
        uint256 roundWithdrawable
    );

    /// @notice An account has finalized a withdrawal
    /// @param account The account that finalized the withdrawal
    /// @param withdrawalAmount The amount that was withdrawn
    event WithdrawalFinalized(address indexed account, uint256 withdrawalAmount);

    /// @notice An auction was resolved and a new express lane controller was set
    /// @param isMultiBidAuction Whether there was more than one bid in the auction
    /// @param round The round for which the rights were being auctioned
    /// @param firstPriceBidder The bidder who won the auction
    /// @param firstPriceExpressLaneController The address that will have express lane control in the specified round
    /// @param firstPriceAmount The price in the winning bid
    /// @param price The price paid by the winning bidder
    /// @param roundStartTimestamp The time at which the round will start
    /// @param roundEndTimestamp The time at which the round will end
    event AuctionResolved(
        bool indexed isMultiBidAuction,
        uint64 round,
        address indexed firstPriceBidder,
        address indexed firstPriceExpressLaneController,
        uint256 firstPriceAmount,
        uint256 price,
        uint64 roundStartTimestamp,
        uint64 roundEndTimestamp
    );

    /// @notice A new express lane controller was set
    /// @param round The round which the express lane controller will control
    /// @param previousExpressLaneController The previous express lane controller
    /// @param newExpressLaneController The new express lane controller
    /// @param startTimestamp The timestamp at which the new express lane controller takes over
    /// @param endTimestamp The timestamp at which the new express lane controller will cease to have control
    event SetExpressLaneController(
        uint64 round,
        address previousExpressLaneController,
        address newExpressLaneController,
        uint64 startTimestamp,
        uint64 endTimestamp
    );

    /// @notice The minimum reserve price was set
    /// @param oldPrice The previous minimum reserve price
    /// @param newPrice The new minimum reserve price
    event SetMinReservePrice(uint256 oldPrice, uint256 newPrice);

    /// @notice A new reserve price was set
    /// @param oldReservePrice Previous reserve price
    /// @param newReservePrice New reserve price
    event SetReservePrice(uint256 oldReservePrice, uint256 newReservePrice);

    /// @notice A new beneficiary was set
    /// @param oldBeneficiary The previous beneficiary
    /// @param newBeneficiary The new beneficiary
    event SetBeneficiary(address oldBeneficiary, address newBeneficiary);

    /// @notice The role given to the address that can resolve auctions
    function AUCTIONEER_ROLE() external returns (bytes32);

    /// @notice The role given to the address that can set the minimum reserve
    function MIN_RESERVE_SETTER_ROLE() external returns (bytes32);

    /// @notice The role given to the address that can set the reserve
    function RESERVE_SETTER_ROLE() external returns (bytes32);

    /// @notice The role given to the address that can set the beneficiary
    function BENEFICIARY_SETTER_ROLE() external returns (bytes32);

    /// @notice Domain constant to be concatenated with data before signing
    function BID_DOMAIN() external returns (bytes32);

    /// @notice The beneficiary who receives the funds that are paid by the auction winners
    function beneficiary() external returns (address);

    /// @notice The ERC20 token that can be used for bidding
    function biddingToken() external returns (IERC20);

    /// @notice The reserve price for the auctions. The reserve price setter can update this value
    ///         to ensure that controlling rights are auctioned off at a reasonable value
    function reservePrice() external returns (uint256);

    /// @notice The minimum amount the reserve can be set to. This ensures that reserve prices cannot be
    ///         set too low
    function minReservePrice() external returns (uint256);

    /// @notice Initialize the auction
    /// @param _auctioneer The address who can resolve auctions
    /// @param _beneficiary The address to which auction winners will pay the bid
    /// @param _biddingToken The token used for payment
    /// @param _roundTimingInfo Round timing components: offset, auction closing, round duration, reserve submission
    /// @param _minReservePrice The minimum reserve price, also used to set the initial reserve price
    /// @param _roleAdmin The admin that can manage roles in the contract
    /// @param _minReservePriceSetter The address given the rights to change the min reserve price
    /// @param _reservePriceSetter The address given the rights to change the reserve price
    /// @param _beneficiarySetter The address given the rights to change the beneficiary address
    function initialize(
        address _auctioneer,
        address _beneficiary,
        address _biddingToken,
        RoundTimingInfo memory _roundTimingInfo,
        uint256 _minReservePrice,
        address _roleAdmin,
        address _minReservePriceSetter,
        address _reservePriceSetter,
        address _beneficiarySetter
    ) external;

    /// @notice Round timing components: offset, auction closing, round duration and reserve submission
    function roundTimingInfo()
        external
        view
        returns (
            uint64 offsetTimestamp,
            uint64 roundDurationSeconds,
            uint64 auctionClosingSeconds,
            uint64 reserveSubmissionSeconds
        );

    /// @notice The current auction round that we're in
    ///         Bidding for control of the next round occurs in the current round
    function currentRound() external view returns (uint64);

    /// @notice Is the current auction round closed for bidding
    ///         After the round has closed the auctioneer can resolve it with the highest bids
    function isAuctionRoundClosed() external view returns (bool);

    /// @notice The auction reserve cannot be updated during the blackout period
    ///         This starts ReserveSubmissionSeconds before the round closes and ends when the round is resolved, or the round ends
    function isReserveBlackout() external view returns (bool);

    /// @notice Gets the start and end timestamps for a given round
    /// @param round The round to find the timestamps for
    /// @return start The start of the round in seconds, inclusive
    /// @return end The end of the round in seconds, inclusive
    function roundTimestamps(uint64 round) external view returns (uint64 start, uint64 end);

    /// @notice Update the beneficiary to a new address
    /// @param newBeneficiary The new beneficiary
    function setBeneficiary(address newBeneficiary) external;

    /// @notice Set the minimum reserve. The reserve cannot be set below this value
    ///         Having a minimum reserve ensures that the reserve setter set the reserve too low
    ///         If the new minimum reserve is greater than the current reserve then the reserve will also be set,
    ///         this will regardless of whether we are in a reserve blackout period or not.
    ///         The min reserve setter is therefore trusted to either give bidders plenty of notice that they may change the min
    ///         reserve, or do so outside of the blackout window. It is expected that the min reserve setter will be controlled by
    ///         Arbitrum DAO who can only make changes via timelocks, thereby providing the notice to bidders.
    ///         If the new minimum reserve is set to a very high value eg max(uint) then the auction will never be able to resolve
    ///         the min reserve setter is therefore trusted not to do this as it would DOS the auction. Note that even if this occurs
    ///         bidders will not lose their funds and will still be able to withdraw them.
    /// @param newMinReservePrice The new minimum reserve
    function setMinReservePrice(uint256 newMinReservePrice) external;

    /// @notice Set the auction reserve price. Must be greater than or equal the minimum reserve.
    ///         A reserve price setter is given the ability to change the reserve price to ensure that express lane control rights
    ///         are not sold off too cheaply. They are trusted to set realistic values for this.
    ///         However they can only change this value when not in the blackout period, which occurs before at the auction close
    ///         This ensures that bidders will have plenty of time to observe the reserve before the auction closes, and that
    ///         the reserve cannot be changed at the last second. One exception to this is if the minimum reserve changes, see the setMinReservePrice
    ///         documentation for more details.
    ///         If the new reserve is set to a very high value eg max(uint) then the auction will never be able to resolve
    ///         the reserve setter is therefore trusted not to do this as it would DOS the auction. Note that even if this occurs
    ///         bidders will not lose their funds and will still be able to withdraw them.
    /// @param newReservePrice The price to set the reserve to
    function setReservePrice(uint256 newReservePrice) external;

    /// @notice Get the current balance of specified account.
    ///         If a withdrawal is initiated this balance will reduce in current round + 2
    /// @param account The specified account
    function balanceOf(address account) external view returns (uint256);

    /// @notice The amount of balance that can currently be withdrawn via the finalize method
    ///         This balance only increases current round + 2 after a withdrawal is initiated
    /// @param account The account the check the withdrawable balance for
    function withdrawableBalance(address account) external view returns (uint256);

    /// @notice Deposit an amount of ERC20 token to the auction to make bids with
    ///         Deposits must be submitted prior to bidding.
    /// @dev    Deposits are submitted first so that the auctioneer can be sure that the accepted bids can actually be paid
    /// @param amount   The amount to deposit.
    function deposit(uint256 amount) external;

    /// @notice Initiate a withdrawal of the full account balance of the message sender
    ///         Once funds have been deposited they can only be retrieved by initiating + finalizing a withdrawal
    ///         There is a delay between initializing and finalizing a withdrawal so that the auctioneer can be sure
    ///         that value cannot be removed before an auction is resolved. The timeline is as follows:
    ///         1. Initiate a withdrawal at some time in round r
    ///         2. During round r the balance is still available and can be used in an auction
    ///         3. During round r+1 the auctioneer should consider any accounts that have been initiated for withdrawal as having zero balance
    ///            However if a bid is submitted the balance will be available for use
    ///         4. During round r+2 the bidder can finalize a withdrawal and remove their funds
    ///         A bidder may have only one withdrawal being processed at any one time, and that withdrawal will be for the full balance
    function initiateWithdrawal() external;

    /// @notice Finalizes a withdrawal and transfers the funds to the msg.sender
    ///         Withdrawals can only be finalized 2 rounds after being initiated
    function finalizeWithdrawal() external;

    /// @notice Calculates the data to be hashed for signing
    /// @param _round The round the bid is for the control of
    /// @param _amount The amount being bid
    /// @param _expressLaneController The address that will be the express lane controller if the bid wins
    function getBidBytes(
        uint64 _round,
        uint256 _amount,
        address _expressLaneController
    ) external view returns (bytes memory);

    /// @notice Resolve the auction with just a single bid. The auctioneer is trusted to call this only when there are
    ///         less than two bids higher than the reserve price for an auction round.
    ///         In this case the highest bidder will pay the reserve price for the round
    /// @param firstPriceBid The highest price bid. Must have a price higher than the reserve. Price paid is the reserve
    function resolveSingleBidAuction(Bid calldata firstPriceBid) external;

    /// @notice Resolves the auction round with the two highest bids for that round
    ///         The highest price bidder pays the price of the second highest bid
    ///         Both bids must be higher than the reserve
    /// @param firstPriceBid The highest price bid
    /// @param secondPriceBid The second highest price bid
    function resolveMultiBidAuction(Bid calldata firstPriceBid, Bid calldata secondPriceBid)
        external;

    /// @notice Express lane controllers are allowed to transfer their express lane rights for the current or future
    ///         round to another address. They may use this for reselling their rights after purchasing them
    /// @param round The round to transfer rights for
    /// @param newExpressLaneController The new express lane controller to transfer the rights to
    function transferExpressLaneController(uint64 round, address newExpressLaneController) external;

    // CHRIS: TODO: docs and tests
    function resolvedRounds() external returns (ELCRound memory, ELCRound memory);
}
