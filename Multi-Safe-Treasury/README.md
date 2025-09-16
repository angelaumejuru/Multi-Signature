# Collaborative Treasury Management Contract

A secure multi-signature treasury system enabling collaborative financial management through consensus-based governance with comprehensive security features and controls.

## Overview

This smart contract implements a sophisticated treasury management system built on the Stacks blockchain. It provides a secure, multi-guardian approach to managing shared funds with built-in governance mechanisms, timelock security, and emergency controls.

## Key Features

### Multi-Signature Governance
- **Guardian-based Authorization**: Only authorized guardians can create and vote on proposals
- **Configurable Approval Threshold**: Customizable minimum number of approvals required for proposal execution
- **Vote Delegation**: Guardians can delegate their voting power to other trusted guardians

### Security Controls
- **Timelock Mechanism**: All proposals have a mandatory waiting period before execution
- **Daily Spending Limits**: Built-in protection against excessive daily expenditures
- **Individual Guardian Limits**: Each guardian has their own spending limits
- **Emergency Mode**: Emergency controller can halt all operations when needed

### Proposal System
- **Transfer Proposals**: Request STX transfers to specified recipients
- **Guardian Management**: Add or remove guardians through governance
- **Parameter Updates**: Modify system parameters like approval thresholds
- **Expiration Handling**: Proposals automatically expire after specified time periods

## Contract Functions

### Initialization

#### `setup-treasury-system`
Initializes the treasury with founding guardians and basic parameters.

**Parameters:**
- `initial-guardians`: List of founding guardian addresses (max 20)
- `required-approvals`: Minimum number of approvals needed for proposal execution
- `emergency-admin`: Address with emergency control privileges

### Proposal Management

#### `submit-transfer-proposal`
Creates a new STX transfer proposal.

**Parameters:**
- `target-recipient`: Destination address for the transfer
- `transfer-amount`: Amount in microSTX to transfer
- `proposal-memo`: Optional description (max 256 characters)
- `validity-period-blocks`: How long the proposal remains valid

#### `cast-approval-vote`
Vote to approve an existing proposal.

**Parameters:**
- `proposal-id`: ID of the proposal to vote on

#### `process-approved-proposal`
Execute a proposal that has received sufficient approvals and passed the timelock period.

**Parameters:**
- `proposal-id`: ID of the proposal to execute

#### `withdraw-proposal`
Cancel a proposal (only by creator or after sufficient approvals).

**Parameters:**
- `proposal-id`: ID of the proposal to cancel

### Guardian Management

#### `submit-guardian-addition`
Propose adding a new guardian to the system.

**Parameters:**
- `new-guardian-wallet`: Address of the proposed new guardian

#### `finalize-guardian-addition`
Execute an approved guardian addition proposal.

**Parameters:**
- `proposal-id`: ID of the guardian addition proposal

### Vote Delegation

#### `establish-vote-delegation`
Delegate your voting power to another guardian.

**Parameters:**
- `target-delegate`: Guardian to delegate votes to
- `duration-in-blocks`: How long the delegation lasts

#### `cancel-vote-delegation`
Cancel your existing vote delegation.

### Emergency Controls

#### `enable-emergency-mode`
Activate emergency mode (only emergency controller).

#### `disable-emergency-mode`
Deactivate emergency mode (any guardian).

### Treasury Management

#### `contribute-funds`
Add STX to the treasury.

**Parameters:**
- `contribution-amount`: Amount in microSTX to contribute

### Governance

#### `submit-threshold-modification`
Propose changing the approval threshold.

**Parameters:**
- `updated-threshold`: New minimum approval count

#### `apply-threshold-modification`
Apply an approved threshold change.

**Parameters:**
- `proposal-id`: ID of the threshold modification proposal

## Read-Only Functions

### System Status
- `get-current-approval-threshold`: Returns current minimum approvals needed
- `get-total-guardian-count`: Returns number of active guardians
- `get-treasury-stx-balance`: Returns current treasury balance
- `get-emergency-mode-status`: Returns whether emergency mode is active
- `get-daily-spending-info`: Returns daily spending statistics

### Data Queries
- `check-guardian-authorization`: Verify if an address is an authorized guardian
- `retrieve-proposal-information`: Get detailed proposal data
- `check-guardian-vote-status`: Check if guardian voted on specific proposal
- `retrieve-guardian-information`: Get guardian details and permissions
- `retrieve-delegation-information`: Get delegation details for a guardian

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 100 | ERR-UNAUTHORIZED-ACCESS | Caller lacks required permissions |
| 101 | ERR-INVALID-PARAMETER | Invalid input parameter provided |
| 102 | ERR-PROPOSAL-NOT-EXISTS | Referenced proposal doesn't exist |
| 103 | ERR-PROPOSAL-ALREADY-COMPLETED | Proposal already executed |
| 104 | ERR-PROPOSAL-ALREADY-CANCELLED | Proposal already cancelled |
| 105 | ERR-PROPOSAL-EXPIRED | Proposal past expiration time |
| 106 | ERR-INSUFFICIENT-TREASURY-BALANCE | Not enough STX in treasury |
| 107 | ERR-APPROVAL-THRESHOLD-EXCEEDED | Threshold exceeds guardian count |
| 108 | ERR-GUARDIAN-ALREADY-EXISTS | Guardian already registered |
| 109 | ERR-GUARDIAN-NOT-EXISTS | Referenced guardian not found |
| 110 | ERR-GUARDIAN-VOTE-DUPLICATE | Guardian already voted |
| 111 | ERR-GUARDIAN-VOTE-NOT-FOUND | Vote record not found |
| 112 | ERR-INVALID-MEMO-FORMAT | Memo format validation failed |
| 113 | ERR-TIMELOCK-STILL-ACTIVE | Timelock period not yet expired |
| 114 | ERR-EMERGENCY-MODE-ENABLED | System in emergency mode |
| 115 | ERR-SPENDING-LIMIT-EXCEEDED | Exceeds spending limits |

## Security Features

### Input Validation
- All principal addresses are validated against null addresses
- Memo fields are checked for proper length and format
- Block duration parameters are bounded to reasonable limits
- Proposal IDs are validated against existing proposals

### Access Controls
- Guardian authorization required for proposal creation and voting
- Emergency controller has special privileges for emergency mode
- Proposal creators can cancel their own proposals
- Individual guardian spending limits enforced

### Time-based Security
- Mandatory timelock period before proposal execution
- Proposal expiration prevents indefinite pending states
- Daily spending limits reset automatically
- Delegation expiry prevents indefinite vote delegation

### Economic Security
- Treasury balance checks prevent overdrafts
- Daily and individual spending limits provide multiple layers of protection
- Emergency mode can halt all operations immediately

## Usage Examples

### Initialize Treasury
```clarity
(contract-call? .treasury setup-treasury-system 
  (list 'SP1... 'SP2... 'SP3...) 
  u2 
  'SP-EMERGENCY...)
```

### Create Transfer Proposal
```clarity
(contract-call? .treasury submit-transfer-proposal 
  'SP-RECIPIENT... 
  u1000000 
  (some "Monthly team payment") 
  u1008)
```

### Vote on Proposal
```clarity
(contract-call? .treasury cast-approval-vote u1)
```

### Execute Approved Proposal
```clarity
(contract-call? .treasury process-approved-proposal u1)
```

## Configuration Parameters

### Default Values
- **Timelock Period**: 144 blocks (~24 hours)
- **Maximum Daily Spending**: 1,000 STX
- **Individual Guardian Limit**: 1,000 STX
- **Maximum Proposal Validity**: 52,560 blocks (~1 year)

### Customizable Settings
- Approval threshold (set during initialization)
- Guardian spending limits (per guardian)
- Emergency controller address
- Daily spending limits (through governance)

## Best Practices

### For Guardians
- Review proposals carefully before voting
- Use meaningful memos for transfer proposals
- Set appropriate validity periods
- Monitor daily spending limits
- Use delegation responsibly

### For Treasury Management
- Regular monitoring of guardian activity
- Periodic review of approval thresholds
- Proper emergency contact procedures
- Regular backup of important transaction data

### Security Considerations
- Verify all addresses before creating proposals
- Use conservative spending limits initially
- Test emergency procedures regularly
- Keep emergency controller address secure

## Deployment Notes

1. Deploy the contract to Stacks blockchain
2. Call `setup-treasury-system` with initial parameters
3. Fund the treasury using `contribute-funds`
4. Begin normal operations with proposal creation and voting