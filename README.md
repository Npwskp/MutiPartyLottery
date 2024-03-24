# Multi-Party Lottery in Solidity
## Parameter

```solidity
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
```

`T1 T2 T3` define time of each state start counting from first player added

`N` define max player of this game

`player_num` represent an index and number of player now

`reward_pool` represent reward that everyone put in a pool which is 0.001 ether per player

`start` repersent a start time stamp which turning to block time stamp when first player enter

`player_commit` is a mapping address player and hash of their choice,salt that they enter

`player_index` is a mapping to assign index for all player address for easier query

`player_choice` is mapping address and choice of player which we only change it in reveal stage

## Lottery system setting

Owner of the contract can set time of stage 1,2 and 3 by changeing input in constructor

``` solidity
    constructor(uint _t1, uint _t2, uint _t3, uint _max_player) {
        T1 = _t1;
        T2 = _t2;
        T3 = _t3;
        N = _max_player;
        owner = msg.sender;
    }
```
and game will be sperate to 4 stage which you can check by this function

```solidity
    function checkState() public view returns(uint8) {
        uint8 stage = 0;

        if(start == 0) { return stage;}

        if(block.timestamp > start){
            if(block.timestamp < start + T1){ stage = 1; }
            else if(block.timestamp < start + T1 +T2){ stage = 2; }
            else if(block.timestamp < start + T1 + T2 + T3){ stage = 3; }
            else { stage = 4; }
        }
        return stage;
    }
```

when all operation is done we call function reset game to restart all over again
```solidity
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
```

## Game stage
### Stage 1 :: Add player stage (Time: start => start + T1)

in this state time would not count until first player sucessfully add thier choice

a step to commit their choice in this contract is

1. choose your number choice 0-999 and salt(a random number *always remember this num*) then put in to hash function
``` solidity
    function hashCommitValue(uint value, uint salt) public view returns (bytes32) {
        return getSaltedHash(bytes32(value), bytes32(salt));
    }
```
2. once you get bytes32 hash value you put in a addPlayer function
``` solidity
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
```

### stage 2 :: Reveal stage (Time: start + T1 => start + T1 + T2)
1. player reveal their commit in period of time by using fuction and put their value and salt
```solidity
    function playerReveal(uint val, uint salt) public {
        // stage 2 Player Reveal their choice

        require(checkState() == 2, "This is not Reveal(2) stage");

        bytes32 hashCheckVal = hashCommitValue(val, salt);
        require(player_commit[msg.sender] == hashCheckVal, "this is not your value or salt");

        // if player choice is less than 0 or more than 999 their ether will gone
        player_choice[msg.sender] = val;
    }
```
note : if you not reveal you will not be a valid player and not have any chance to win the game

### stage 3 :: Find winner stage (Time: start + T1 + T2 => start + T1 + T2 + T3)
1. owner of this contract fire a transaction to begin a checkWinner function
2. we find winner by checking all of valid player and xor them then we calculate winner by hash and modulo by number of valid player  
3. Ater that we iterate through apping of user insex and find our 'valid' winner
4. when we get our winner 98% of reward pool will be their reward and 2% will be fee for owner who run this contract
5. after that we restart all of game setting and stage
```solidity
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
```
### stage 4 :: Reveal stage (Time: > start + T1 + T2 + T3)
1. this stage will trigger if owner not fire a transaction in stage 3 period which make players can withdraw their ether
2. once everyone redeem we restart all the game setting and stage

```solidity
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
```
