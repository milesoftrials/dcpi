// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;


import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract CPIPrediction is ChainlinkClient, ConfirmedOwner{
 using Chainlink for Chainlink.Request;

    uint constant SECONDS_PER_DAY = 24 * 60 * 60;
    int constant OFFSET19700101 = 2440588;
    string public yoyInflation;
    address public truOracleId;
    string public truJobId;
    // address public DOLOracleId;
    // string public DOLJobId;
    uint256 public fee;
    int256  inflationWei;

    int256 public DOLCPI;
    // address  __owner;

    mapping (uint => mapping (uint => int256)) TruflationYearEOMCPI;
    mapping (uint => mapping (uint => int256)) TruflationYearEOMPChange;

    int256 public NextMonthCPI;
    int256 public TwoMonthsCPI;
    int256 public ThreeMonthsCPI;


  constructor(
    address truOracleId_,
    string memory truJobId_,
    uint256 fee_,
    int256 DOLCPI_
    // address DOLOracleId_,
    // string memory DOLJobId_
  ) payable ConfirmedOwner(msg.sender) {
    setPublicChainlinkToken();

    // use this for Goerli (chain: 5)
    // setChainlinkToken(0x326C977E6efc84E512bB9C30f76E30c160eD06FB);
    
    truOracleId = truOracleId_;
    truJobId = truJobId_;

    // DOLOracleId = DOLOracleId_;
    // DOLJobId = DOLJobId_;

    // __owner = msg.sender;
    DOLCPI= DOLCPI_;


    fee = fee_;
    //  Historical Load for TruflationYearEOMCPI and TruflationYearEOMPChange
    TruflationYearEOMCPI[2022][7] = 9910000000000000000;
    TruflationYearEOMCPI[2022][8] = 9170000000000000000;
    TruflationYearEOMCPI[2022][9] = 8750000000000000000;

    TruflationYearEOMPChange[2022][8] = -74672048435923309;
    TruflationYearEOMPChange[2022][9] = -45801526717557251;

  }









    function thisMonthsCPI() public payable{
        // if (msg.sender == __owner){
        int256 month;
        uint year;
        string memory eom;
        (month, year)= MonthYear();
        (month,year)= SubMonths(month, year,1);
        eom = EOMString(month,year);
        requestInflationWei(eom);
        // }
    }






// Calls Truflation marketplace to obtain last month's EOM Inflation CPI
    function requestInflationWei(string memory eom) public returns (bytes32 requestId) {
        Chainlink.Request memory req = buildChainlinkRequest(
        bytes32(bytes(truJobId)),
        address(this),
        this.fulfillInflationWei.selector
        );
        req.add("service", "truflation/at-date");
        req.add("keypath", "yearOverYearInflation");
        req.add("data", string.concat("{'date':'",eom,"','location':'us'}"));
        req.add("abi", "int256");
        req.add("multiplier", "1000000000000000000");
        return sendChainlinkRequestTo(truOracleId, req, fee);
    }

//  Returns form the truflation node call
    function fulfillInflationWei(
        bytes32 _requestId,
        bytes memory _inflation
    ) public recordChainlinkFulfillment(_requestId) {
        int256 lmonth;
        uint lmyear;
        inflationWei = toInt256(_inflation);
        
        (lmonth, lmyear)= SetTruflationYearEOMCPI(inflationWei);
        SetTruflationYearEOMPChange(lmonth, lmyear);
        ProjectCPI();

    

    }


    function toInt256(bytes memory _bytes) internal pure
    returns (int256 value) {
        assembly {
        value := mload(add(_bytes, 0x20))
        }
    }


    // Sets TruflationYearEOMCPI returns last month to be used by percent change function
    function SetTruflationYearEOMCPI(int256 cpi) private returns (int256 month, uint year){

        (month, year)= MonthYear();
        (month,year)= SubMonths(month, year,1);
        TruflationYearEOMCPI[year][uint(month)] = cpi;

    }


    function SetTruflationYearEOMPChange(int256 _lmonth, uint _lmyear) private  {
        // need two months ago
        int256 tmonth;
        uint tmyear;
        int256 pchange;
        (tmonth,tmyear)=SubMonths(_lmonth,_lmyear,1);
        // (new-old)*10^18/old) need 10^18 so we dont end up with a decimal on the quotient
        pchange = ((TruflationYearEOMCPI[uint(_lmonth)][_lmyear]-TruflationYearEOMCPI[uint(tmonth)][tmyear])*1000000000000000000)/TruflationYearEOMCPI[uint(tmonth)][tmyear];

        TruflationYearEOMPChange[uint(_lmonth)][_lmyear]=pchange;



    }

    // in order to save time we input the number directly to obtian fed numbers
    // this will be replaced by a chainlink job that obtains the dol data from
    function setDol(int256 dol_) public payable {
        DOLCPI= dol_;


    }


    // Call fed number 


    function ProjectCPI() private  {
        int256 month;
        uint year;
        int256 lmonth;
        uint lmyear;
        int256 tmonth;
        uint tmyear;
        int256 thmonth;
        uint thmyear;
        
        (month, year)= MonthYear();
        (lmonth, lmyear)= SubMonths(month, year,1);
        (tmonth, tmyear)= SubMonths(month, year,2);
        (thmonth, thmyear)= SubMonths(month, year,3);
        // we need the last 3 months % change 

        NextMonthCPI= DOLCPI * TruflationYearEOMPChange[thmyear][uint(thmonth)];
        TwoMonthsCPI= NextMonthCPI * TruflationYearEOMPChange[tmyear][uint(tmonth)];
        ThreeMonthsCPI= TwoMonthsCPI* TruflationYearEOMPChange[lmyear][uint(lmyear)];

    }




    function MonthYear() public view returns (int256 month, uint year) {
        uint day;
        (year, month, day) = _daysToDate(block.timestamp / SECONDS_PER_DAY);
    }

    function EOMString(int256 _month, uint _year) public pure returns (string memory eom) {
            uint month;
            string memory day;
            month = uint(_month);
            if (month == 2 && _year % 4 != 0){
                day = "28";
            }else if (month == 2){
                day ="29";
            }else if (month % 2 == 0){
                day = "30";
            } else{
                day = "31";
            }

            eom= string.concat(Strings.toString(_year),"-",Strings.toString(month),"-",day);

    }

// ------------------------------------------------------------------------
    // Calculate year/month/day from the number of days since 1970/01/01 using
    // the date conversion algorithm from
    //   http://aa.usno.navy.mil/faq/docs/JD_Formula.php
    // and adding the offset 2440588 so that 1970/01/01 is day 0
    //
    // int L = days + 68569 + offset
    // int N = 4 * L / 146097
    // L = L - (146097 * N + 3) / 4
    // year = 4000 * (L + 1) / 1461001
    // L = L - 1461 * year / 4 + 31
    // month = 80 * L / 2447
    // dd = L - 2447 * month / 80
    // L = month / 11
    // month = month + 2 - 12 * L
    // year = 100 * (N - 49) + year + L
    // ------------------------------------------------------------------------
// https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary/blob/1ea8ef42b3d8db17b910b46e4f8c124b59d77c03/contracts/BokkyPooBahsDateTimeLibrary.sol

    function _daysToDate(uint _days) internal pure returns (uint year, int256 month, uint day) {
        int __days = int(_days);

        int L = __days + 68569 + OFFSET19700101;
        int N = 4 * L / 146097;
        L = L - (146097 * N + 3) / 4;
        int _year = 4000 * (L + 1) / 1461001;
        L = L - 1461 * _year / 4 + 31;
        int _month = 80 * L / 2447;
        int _day = L - 2447 * _month / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint(_year);
        month = int256(_month);
        day = uint(_day);
    }


    // addapted from above link's addMonths function

    function SubMonths(int256 _month, uint _year, int256 _months) public pure returns (int256 month, uint year) {
        if (_month <= _months){
            year = _year - 1;
        }
        month = ((_month-_months) +11) %12 +1;



    }

    // addapted from above link's addMonths function
    function subMonthsCurr( int256 _months) public view returns (int256 month, uint year) {
        uint day;
        (year, month, day) = _daysToDate(block.timestamp / SECONDS_PER_DAY);
        if (month <= _months){
            year -=1;
        }
        month = ((month-_months) +11) %12 +1;



    }



    // function withdrawLink() public onlyOwner {
    // LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
    // require(link.transfer(msg.sender, link.balanceOf(address(this))),
    // "Unable to transfer");
//   }




}
