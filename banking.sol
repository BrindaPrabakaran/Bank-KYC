// SPDX-License-Identifier: MIT
pragma solidity^0.8.17;

contract KYC{
// components that the customer struct needs
    struct Customer{
        string userName;
        string data; //documents of the customer
        bool kycStatus;//If the number of upvotes/downvotes meet the required conditions, set kycStatus to true; otherwise, set it to false.
        uint256 Downvote;
        uint256 Upvotes;
        address bank;
    }
// components that the bank struct needs
    struct Bank{
        string name;
        address ethAddress; //unique eth address of the bank
        uint256 complaintsReported;
        uint256 _count;
        bool isAllowedToVote;
        string regNumber;
        address bankAddress;
    }

    struct Request{
        string customerName;
        string customerData;
        address bankAddress;
    }

    enum BankActions {
        AddKYC,
        RemoveKYC,
        ApproveKYC,
        AddCustomer,
        RemoveCustomer,
        ModifyCustomer,
        DeleteCustomer,
        UpVoteCustomer,
        DownVoteCustomer,
        ViewCustomer,

        ReportSuspectedBank
    }

    address[] bankAddresses; //array for bank addresses
    address admin; //certain activites are limited to admin only

    event ContractInitialized();
    event CustomerRequestAdded();
    event CustomerRequestRemoved();
    event CustomerRequestApproved();

    event NewCustomerCreated();
    event CustomerInfoModified();

    event NewBankCreated();
    event BankRemoved();
    event BankBlockedFromKYC();

    constructor(){
        emit ContractInitialized();
        admin = msg.sender;
    }

    

    mapping(string=>Customer) customers;//Mapping a customer struct to  Customers
    mapping(address=> Bank) banks;// mapping Bank struct to banks
    mapping(string=> Request) kycRequests; // mapping request struct to jycrequests
    mapping(string=>mapping(address=>uint256))upvotes;// to track upvotes
    mapping(string=>mapping(address=>uint256))downvotes; //to track downvotes
    mapping(string=>Bank)regNumbers;// mapping the regNumber of Bank struct
    mapping(address => mapping(uint256 => uint256)) bankActionsAudit; // mapping enum to bankActionsAudit
    
    //This function will add a customer to the customer list
    function addCustomer(string memory _userName,string memory _customerdata, string memory customName) public payable{
        require(customers[_userName].bank==address(0),"Customer is already present, please call modifyCustomer to edit the customer data");
        require(customers[customName].bank == address(0), "Requested Customer already exists");
        customers[_userName].userName=_userName;
        customers[_userName].data=_customerdata;
        customers[_userName].bank=msg.sender;

        auditBankAction(msg.sender,BankActions.AddCustomer);
        emit NewCustomerCreated();
    }

    //This function allows a bank to view the details of a customer
    function viewCustomer(string memory _userName) public view returns(string memory, string memory, address){
        require(customers[_userName].bank != address(0), "Customer is not present in the database");
        return (customers[_userName].userName, customers[_userName].data, customers[_userName].bank);
    }

    //This function allows a bank to modify a customer data 
    function modifyCustomer(string memory _userName, string memory _newCustomerData) public payable{
        require(customers[_userName].bank != address(0), "Customer is not present in the database");
        customers[_userName].data=_newCustomerData;

        emit CustomerInfoModified();
    }

    //This function is used to add the KYC request to the requests list
    function addRequest(string memory customName,string memory customData)public payable returns(int){
        require(kycRequests[customName].bankAddress != address(0),"A KYC request is already pending with this customer");
        kycRequests[customName]=Request(customName,customData,msg.sender);
        banks[msg.sender]._count++;

        customers[customName].data = customData;
        customers[customName].Upvotes = 0;
        customers[customName].Downvote = 0;

        emit CustomerRequestAdded();
        auditBankAction(msg.sender,BankActions.AddKYC);
        return 1;
        
    }

    //This function will remove the request from the requests list
    function removeRequest(string memory customName) public payable returns(int){
        require(kycRequests[customName].bankAddress==msg.sender,"Requested Bank is not authorized to remove this customer as KYC is not initiated");
        delete kycRequests[customName];
        auditBankAction(msg.sender,BankActions.RemoveKYC);

        emit CustomerRequestRemoved();
        return 1;
    }

    //This function allows a bank to cast an upvote for a customer, which accepts the customer details
    function upvoteCustomer(string memory customName)public payable returns(int){
        require(banks[msg.sender].isAllowedToVote,"Requested bank does not have voting privilege");
        require(customers[customName].bank!=address(0),"Requested customer found");
        customers[customName].Upvotes++;
        customers[customName].kycStatus = (customers[customName].Upvotes > customers[customName].Downvote && customers[customName].Upvotes >  bankAddresses.length/3);
        upvotes[customName][msg.sender] = block.timestamp;
        auditBankAction(msg.sender,BankActions.UpVoteCustomer);

        return 1;
    }

    //This function allows a bank to cast a downvote for a customer, which denies the data of the customer
    function downvoteCustomer(string memory customName) public payable returns(int){
        require(banks[msg.sender].isAllowedToVote,"Requested bank does not have voting rights");
        require(customers[customName].bank!= address(0),"Requested customer not found");
        customers[customName].Downvote++;
        customers[customName].kycStatus= (customers[customName].Upvotes > customers[customName].Downvote && customers[customName].Upvotes > bankAddresses.length/3);          
        downvotes[customName][msg.sender] = block.timestamp;
        auditBankAction(msg.sender,BankActions.DownVoteCustomer);
        return 1;
    }

    //This function will be used to fetch bank complaints from the smart contract.  
    function getBankComplaints(address wrongBankAddress) public payable returns(uint256){
        require(banks[wrongBankAddress].ethAddress!=address(0),"Requested bank account not found");
        return banks[wrongBankAddress].complaintsReported;
    }

    //This function is used to fetch the bank details.
    function viewBankDetails(address BankAddress) public view returns(address){
        require(banks[BankAddress].ethAddress!=address(0),"Requested bank address is not visisble");
        return banks[BankAddress].bankAddress;
    }

    //This function is used to report a complaint against any bank in the network.
    function reportBank(address suspectingBank)public payable returns(int) {
        require(banks[suspectingBank].ethAddress!=address(0),"Bank not found");
        banks[suspectingBank].complaintsReported;
        auditBankAction(msg.sender,BankActions.ReportSuspectedBank);

        return 1;
    }

    //This function is used by the admin to add a bank to the KYC Contract.This function can only be modified by admin
    function addBank(string memory bankName, string memory regNumber,address ethAddress, address bankAddress) public  payable{
        require(msg.sender==admin,"Only admins can add bank");
        require(regNumbers[bankName].ethAddress!=address(0),"Already exists with same regNum");

        banks[ethAddress] = Bank(bankName,ethAddress,0,0,true,regNumber,bankAddress);
        bankAddresses.push(ethAddress);

        emit NewBankCreated();
    }

    //This function can only be used by the admin to change the status of isAllowedToVote of the banks
    function BankisAllowedToVote(address ethAddress)public payable returns(int){
        require(msg.sender==admin,"Only admins can modify");
        require(banks[ethAddress].ethAddress!=address(0),"Bank not found");
        banks[ethAddress]. isAllowedToVote = false;

        emit BankBlockedFromKYC();

        return 1;
    }

    //This function is used by the admin to remove a bank from the KYC Contract
    function removeBank(address ethAddress)public payable returns(int){
        require(msg.sender==admin,"Only admins can remove Bank");
        require(banks[ethAddress].ethAddress!=address(0),"Not found");
        delete banks[ethAddress];

        emit BankRemoved();

        return 1;

    }

    function auditBankAction(address changesDoneBy, BankActions bankAction) private {
        bankActionsAudit[changesDoneBy][uint256(bankAction)] = (block.timestamp);
    }
}