// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2 <0.9.0;

import "Commit-Reveal.sol";

contract Lottery is CommitReveal{
    address public owner;
    uint public T1;
    uint public T2;
    uint public T3;
    uint public N;

    uint public player_num = 0;

    uint public reward_pool = 0;
    uint public start = 0;

    mapping (address => bytes32) private player_commit;
    mapping (uint => address) private player_index;
    mapping (address => uint) private player_choice;

    constructor(uint _t1, uint _t2, uint _t3, uint _max_player) {
        T1 = _t1;
        T2 = _t2;
        T3 = _t3;
        N = _max_player;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _; // Continue execution if the caller is the owner
    }

    function hashCommitValue(uint value, uint salt) public view returns (bytes32) {
        return getSaltedHash(bytes32(value), bytes32(salt));
    }

    function checkState() public view returns(uint8) {
        uint8 stage = 0;

        if(start == 0) { return stage;}

        if(block.timestamp > start){
            if(block.timestamp < start + T1){
                stage = 1;
            }
            else if(block.timestamp < start + T1 +T2){
                stage = 2;
            }
            else if(block.timestamp < start + T1 + T2 + T3){
                stage = 3;
            }
            else {
                stage = 4;
            }
        }
        return stage;
    }

    function checkValidPlayer(address player) public view returns(bool){
        if(player_choice[player] >= 0 && player_choice[player] <= 999){
            return true;
        }
        return false;
    }

    function resetGame() private{
        // clear mapping
        for (uint i = 0; i < player_num; i++) {
            player_commit[player_index[i]] = bytes32(0);
            player_choice[player_index[i]] = 9999;
            player_index[i] = address(0);
        }

        // clear other
        player_num = 0;
        start = 0;
        reward_pool = 0;
    }

    function addPlayer(bytes32 value) public payable {
        // stage 1 Add player and player commit their choice

        require(checkState() == 0 || checkState() == 1, "This is not AddPlayer(1) stage");

        // validate an input
        require(msg.value == 0.001 ether, "0.001 Ether per lottery");
        require(player_commit[msg.sender] == bytes32(0), "You already commit");
        require(player_num < N, "Max player reached");

        // check first player start
        if (start == 0) { start = block.timestamp; }

        //set player info
        player_commit[msg.sender] = value;
        player_index[player_num] = msg.sender;
        player_choice[msg.sender] = 9999;
        reward_pool += msg.value;
        player_num += 1;
    }

    function playerReveal(uint val, uint salt) public {
        // stage 2 Player Reveal their choice

        require(checkState() == 2, "This is not Reveal(2) stage");

        bytes32 hashCheckVal = hashCommitValue(val, salt);
        require(player_commit[msg.sender] == hashCheckVal, "this is not your value or salt");

        // if player choice is less than 0 or more than 999 their ether will gone
        player_choice[msg.sender] = val;
    }

    function checkWinner() public payable onlyOwner{
        // stage 3 check winner and pay but we need owner to fire transaction

        require(checkState() == 3, "This is not FindWinner(3) stage");

        // check valid player and XOR choice before hash and mod
        uint Valid_player_num = 0;
        uint XOR_choice = 0;

        for(uint i=0; i < player_num; i++ ){
            if (checkValidPlayer(player_index[i])){
                Valid_player_num +=1;
                XOR_choice ^= player_choice[player_index[i]];
            }
        }

        // find winner index
        uint Valid_winner_index = uint(keccak256(abi.encodePacked(XOR_choice))) % Valid_player_num;
        uint Valid_player_index = 0;
        address WinnerAddress;

        // if no valid player we assign winner to owner
        if(Valid_player_num == 0){
            WinnerAddress = owner;
        }
        // if not we find winner by index
        else{
            for(uint i=0; i < player_num; i++ ){
                if (checkValidPlayer(player_index[i])){
                    if(Valid_player_index == Valid_winner_index){
                        WinnerAddress = player_index[i];
                    }
                    else{
                        Valid_winner_index += 1;
                    }
                }
            }
        }

        // payment Part
        address payable ownerAddress = payable(owner);
        address payable winnerAddress = payable(WinnerAddress);

        ownerAddress.transfer((reward_pool * 2) / 100);
        winnerAddress.transfer((reward_pool * 98) / 100);

        // the reset game will not lead us to stage 4 if stage 3 execute succesfully (it reset to stage 0)
        resetGame();
    } 

    function playerWithdraw() public {
        // player both walid and invalid player withdraw if owner not succesfully execute stage 3

        require(checkState() == 4, "This game already end you cannot withdraw any");
        require(player_commit[msg.sender] != bytes32(0), "You are not part of this game or alredy withdraw");

        // payback to player that in game and not withdraw yet
        address payable Addr = payable (msg.sender);
        player_commit[msg.sender] = bytes32(0);

        reward_pool -= 0.001 ether;        
        Addr.transfer(0.001 ether);
        
        // until it reach 0 in pool
        if(reward_pool == 0){
            resetGame();
        }
    }
}