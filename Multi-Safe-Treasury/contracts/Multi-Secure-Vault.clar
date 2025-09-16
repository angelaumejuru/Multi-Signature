;; Collaborative Treasury Management Contract
;; 
;; A secure multi-signature treasury system enabling collaborative financial management
;; through consensus-based governance with comprehensive security features and controls.

;; ERROR CODE DEFINITIONS

(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-INVALID-PARAMETER (err u101))
(define-constant ERR-PROPOSAL-NOT-EXISTS (err u102))
(define-constant ERR-PROPOSAL-ALREADY-COMPLETED (err u103))
(define-constant ERR-PROPOSAL-ALREADY-CANCELLED (err u104))
(define-constant ERR-PROPOSAL-EXPIRED (err u105))
(define-constant ERR-INSUFFICIENT-TREASURY-BALANCE (err u106))
(define-constant ERR-APPROVAL-THRESHOLD-EXCEEDED (err u107))
(define-constant ERR-GUARDIAN-ALREADY-EXISTS (err u108))
(define-constant ERR-GUARDIAN-NOT-EXISTS (err u109))
(define-constant ERR-GUARDIAN-VOTE-DUPLICATE (err u110))
(define-constant ERR-GUARDIAN-VOTE-NOT-FOUND (err u111))
(define-constant ERR-INVALID-MEMO-FORMAT (err u112))
(define-constant ERR-TIMELOCK-STILL-ACTIVE (err u113))
(define-constant ERR-EMERGENCY-MODE-ENABLED (err u114))
(define-constant ERR-SPENDING-LIMIT-EXCEEDED (err u115))

;; SYSTEM STATE VARIABLES

(define-data-var proposal-counter uint u0)
(define-data-var total-active-guardians uint u0)
(define-data-var minimum-approval-count uint u0)
(define-data-var emergency-mode-status bool false)
(define-data-var emergency-controller-address principal 'SP000000000000000000002Q6VF78)
(define-data-var timelock-period-blocks uint u144)
(define-data-var maximum-daily-spending uint u1000000000)
(define-data-var current-daily-spent uint u0)
(define-data-var last-reset-day uint u0)

;; DATA STORAGE STRUCTURES

(define-map treasury-proposals
  { proposal-identifier: uint }
  {
    proposal-creator: principal,
    recipient-address: principal,
    amount-in-microstx: uint,
    description-memo: (optional (buff 256)),
    operation-type: (string-ascii 20),
    execution-status: bool,
    cancellation-status: bool,
    approval-votes-received: uint,
    expiration-block-height: uint,
    timelock-release-block: uint,
    created-at-block: uint
  }
)

(define-map authorized-guardians
  { guardian-address: principal }
  { 
    active-status: bool,
    role-designation: (string-ascii 15),
    individual-spending-limit: uint,
    registration-block: uint
  }
)

(define-map guardian-votes
  { proposal-identifier: uint, voter-address: principal }
  { 
    approval-given: bool,
    voting-block-height: uint
  }
)

(define-map voting-delegations
  { delegator-address: principal }
  {
    delegate-address: principal,
    delegation-expiry-block: uint
  }
)

;; INPUT VALIDATION HELPERS

(define-private (validate-principal-address (wallet-address principal))
  (not (is-eq wallet-address 'SP000000000000000000002Q6VF78)))

(define-private (validate-description-format (description-text (optional (buff 256))))
  (match description-text
    valid-desc (and (>= (len valid-desc) u1) (<= (len valid-desc) u256))
    true))

(define-private (validate-proposal-exists (proposal-id uint))
  (< proposal-id (var-get proposal-counter)))

(define-private (validate-block-duration (block-count uint))
  (and (> block-count u0) (<= block-count u52560))) ;; Max ~1 year in blocks

;; ON-CHAIN FUNCTIONALITIES

;; TREASURY INITIALIZATION
(define-public (setup-treasury-system (initial-guardians (list 20 principal)) 
                                      (required-approvals uint)
                                      (emergency-admin principal))
  (begin
    (asserts! (is-eq (var-get total-active-guardians) u0) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (<= required-approvals (len initial-guardians)) ERR-APPROVAL-THRESHOLD-EXCEEDED)
    (asserts! (> required-approvals u0) ERR-INVALID-PARAMETER)
    ;; Validate emergency guardian address
    (asserts! (validate-principal-address emergency-admin) ERR-INVALID-PARAMETER)
    ;; Validate all founding guardian addresses
    (asserts! (is-eq (len (filter validate-principal-address initial-guardians)) (len initial-guardians)) ERR-INVALID-PARAMETER)
    
    (var-set minimum-approval-count required-approvals)
    (var-set emergency-controller-address emergency-admin)
    (map add-founding-guardian initial-guardians)
    (ok true)))

(define-private (add-founding-guardian (guardian-wallet principal))
  (begin
    (map-set authorized-guardians 
      { guardian-address: guardian-wallet } 
      { active-status: true, role-designation: "standard", 
        individual-spending-limit: u1000000000, registration-block: block-height })
    (var-set total-active-guardians (+ (var-get total-active-guardians) u1))
    true))

;; PROPOSAL CREATION
(define-public (submit-transfer-proposal (target-recipient principal) 
                                        (transfer-amount uint) 
                                        (proposal-memo (optional (buff 256))) 
                                        (validity-period-blocks uint))
  (let ((new-proposal-id (var-get proposal-counter))
        (submitter-info (unwrap! (map-get? authorized-guardians { guardian-address: tx-sender }) ERR-UNAUTHORIZED-ACCESS)))
    
    ;; Input validation
    (asserts! (validate-principal-address target-recipient) ERR-INVALID-PARAMETER)
    (asserts! (validate-description-format proposal-memo) ERR-INVALID-PARAMETER)
    (asserts! (validate-block-duration validity-period-blocks) ERR-INVALID-PARAMETER)
    
    (asserts! (get active-status submitter-info) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (var-get emergency-mode-status)) ERR-EMERGENCY-MODE-ENABLED)
    (asserts! (> transfer-amount u0) ERR-INVALID-PARAMETER)
    (asserts! (<= transfer-amount (stx-get-balance (as-contract tx-sender))) ERR-INSUFFICIENT-TREASURY-BALANCE)
    (asserts! (<= transfer-amount (get individual-spending-limit submitter-info)) ERR-SPENDING-LIMIT-EXCEEDED)
    
    (process-daily-spending-update transfer-amount)
    (asserts! (<= (var-get current-daily-spent) (var-get maximum-daily-spending)) ERR-SPENDING-LIMIT-EXCEEDED)
    
    (map-set treasury-proposals
      { proposal-identifier: new-proposal-id }
      {
        proposal-creator: tx-sender,
        recipient-address: target-recipient,
        amount-in-microstx: transfer-amount,
        description-memo: proposal-memo,
        operation-type: "transfer",
        execution-status: false,
        cancellation-status: false,
        approval-votes-received: u1,
        expiration-block-height: (+ block-height validity-period-blocks),
        timelock-release-block: (+ block-height (var-get timelock-period-blocks)),
        created-at-block: block-height
      })
    
    (map-set guardian-votes
      { proposal-identifier: new-proposal-id, voter-address: tx-sender }
      { approval-given: true, voting-block-height: block-height })
    
    (var-set proposal-counter (+ new-proposal-id u1))
    (ok new-proposal-id)))

;; PROPOSAL VOTING
(define-public (cast-approval-vote (proposal-id uint))
  (begin
    ;; Validate proposal ID
    (asserts! (validate-proposal-exists proposal-id) ERR-PROPOSAL-NOT-EXISTS)
    
    (asserts! (check-guardian-authorization tx-sender) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-some (map-get? treasury-proposals { proposal-identifier: proposal-id })) ERR-PROPOSAL-NOT-EXISTS)
    
    (match (map-get? treasury-proposals { proposal-identifier: proposal-id })
      proposal-data
        (begin
          (asserts! (not (get execution-status proposal-data)) ERR-PROPOSAL-ALREADY-COMPLETED)
          (asserts! (not (get cancellation-status proposal-data)) ERR-PROPOSAL-ALREADY-CANCELLED)
          (asserts! (<= block-height (get expiration-block-height proposal-data)) ERR-PROPOSAL-EXPIRED)
          (asserts! (not (check-guardian-vote-status proposal-id tx-sender)) ERR-GUARDIAN-VOTE-DUPLICATE)
          
          (map-set guardian-votes
            { proposal-identifier: proposal-id, voter-address: tx-sender }
            { approval-given: true, voting-block-height: block-height })
          
          (map-set treasury-proposals
            { proposal-identifier: proposal-id }
            (merge proposal-data 
              { approval-votes-received: (+ (get approval-votes-received proposal-data) u1) }))
          
          (if (>= (+ (get approval-votes-received proposal-data) u1) (var-get minimum-approval-count))
            (begin
              (try! (process-approved-proposal proposal-id))
              (ok proposal-id))
            (ok proposal-id)))
      ERR-PROPOSAL-NOT-EXISTS)))

;; PROPOSAL EXECUTION
(define-public (process-approved-proposal (proposal-id uint))
  (begin
    ;; Validate proposal ID
    (asserts! (validate-proposal-exists proposal-id) ERR-PROPOSAL-NOT-EXISTS)
    
    (asserts! (is-some (map-get? treasury-proposals { proposal-identifier: proposal-id })) ERR-PROPOSAL-NOT-EXISTS)
    
    (match (map-get? treasury-proposals { proposal-identifier: proposal-id })
      proposal-data
        (begin
          (asserts! (not (get execution-status proposal-data)) ERR-PROPOSAL-ALREADY-COMPLETED)
          (asserts! (not (get cancellation-status proposal-data)) ERR-PROPOSAL-ALREADY-CANCELLED)
          (asserts! (<= block-height (get expiration-block-height proposal-data)) ERR-PROPOSAL-EXPIRED)
          (asserts! (>= block-height (get timelock-release-block proposal-data)) ERR-TIMELOCK-STILL-ACTIVE)
          (asserts! (>= (get approval-votes-received proposal-data) (var-get minimum-approval-count)) ERR-UNAUTHORIZED-ACCESS)
          
          (map-set treasury-proposals
            { proposal-identifier: proposal-id }
            (merge proposal-data { execution-status: true }))
          
          (if (is-eq (get operation-type proposal-data) "transfer")
            (as-contract 
              (stx-transfer? (get amount-in-microstx proposal-data) 
                            tx-sender 
                            (get recipient-address proposal-data)))
            (ok true)))
      ERR-PROPOSAL-NOT-EXISTS)))

;; GUARDIAN MANAGEMENT
(define-public (submit-guardian-addition (new-guardian-wallet principal))
  (let ((new-proposal-id (var-get proposal-counter)))
    ;; Validate guardian address
    (asserts! (validate-principal-address new-guardian-wallet) ERR-INVALID-PARAMETER)
    
    (asserts! (check-guardian-authorization tx-sender) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (check-guardian-authorization new-guardian-wallet)) ERR-GUARDIAN-ALREADY-EXISTS)
    
    (map-set treasury-proposals
      { proposal-identifier: new-proposal-id }
      {
        proposal-creator: tx-sender,
        recipient-address: new-guardian-wallet,
        amount-in-microstx: u0,
        description-memo: none,
        operation-type: "add-guardian",
        execution-status: false,
        cancellation-status: false,
        approval-votes-received: u1,
        expiration-block-height: (+ block-height u1008),
        timelock-release-block: (+ block-height (var-get timelock-period-blocks)),
        created-at-block: block-height
      })
    
    (var-set proposal-counter (+ new-proposal-id u1))
    (ok new-proposal-id)))

(define-public (finalize-guardian-addition (proposal-id uint))
  (begin
    ;; Validate proposal ID
    (asserts! (validate-proposal-exists proposal-id) ERR-PROPOSAL-NOT-EXISTS)
    
    (asserts! (is-some (map-get? treasury-proposals { proposal-identifier: proposal-id })) ERR-PROPOSAL-NOT-EXISTS)
    
    (match (map-get? treasury-proposals { proposal-identifier: proposal-id })
      proposal-data
        (begin
          (asserts! (is-eq (get operation-type proposal-data) "add-guardian") ERR-INVALID-PARAMETER)
          (asserts! (>= (get approval-votes-received proposal-data) (var-get minimum-approval-count)) ERR-UNAUTHORIZED-ACCESS)
          (asserts! (>= block-height (get timelock-release-block proposal-data)) ERR-TIMELOCK-STILL-ACTIVE)
          
          (map-set treasury-proposals
            { proposal-identifier: proposal-id }
            (merge proposal-data { execution-status: true }))
          
          (map-set authorized-guardians 
            { guardian-address: (get recipient-address proposal-data) } 
            { active-status: true, role-designation: "standard", 
              individual-spending-limit: u1000000000, registration-block: block-height })
          
          (var-set total-active-guardians (+ (var-get total-active-guardians) u1))
          (ok proposal-id))
      ERR-PROPOSAL-NOT-EXISTS)))

;; DELEGATION SYSTEM
(define-public (establish-vote-delegation (target-delegate principal) (duration-in-blocks uint))
  (let ((delegator-data (unwrap! (map-get? authorized-guardians { guardian-address: tx-sender }) ERR-UNAUTHORIZED-ACCESS))
        (delegate-data (unwrap! (map-get? authorized-guardians { guardian-address: target-delegate }) ERR-GUARDIAN-NOT-EXISTS)))
    
    ;; Input validation
    (asserts! (validate-principal-address target-delegate) ERR-INVALID-PARAMETER)
    (asserts! (validate-block-duration duration-in-blocks) ERR-INVALID-PARAMETER)
    
    (asserts! (get active-status delegator-data) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (get active-status delegate-data) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (is-eq tx-sender target-delegate)) ERR-INVALID-PARAMETER)
    
    (map-set voting-delegations
      { delegator-address: tx-sender }
      {
        delegate-address: target-delegate,
        delegation-expiry-block: (+ block-height duration-in-blocks)
      })
    
    (ok true)))

(define-public (cancel-vote-delegation)
  (begin
    (asserts! (is-some (map-get? voting-delegations { delegator-address: tx-sender })) ERR-INVALID-PARAMETER)
    (map-delete voting-delegations { delegator-address: tx-sender })
    (ok true)))

;; EMERGENCY CONTROLS
(define-public (enable-emergency-mode)
  (begin
    (asserts! (is-eq tx-sender (var-get emergency-controller-address)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (var-get emergency-mode-status)) ERR-EMERGENCY-MODE-ENABLED)
    (var-set emergency-mode-status true)
    (ok true)))

(define-public (disable-emergency-mode)
  (begin
    (asserts! (check-guardian-authorization tx-sender) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (var-get emergency-mode-status) ERR-INVALID-PARAMETER)
    (var-set emergency-mode-status false)
    (ok true)))

;; TREASURY DEPOSIT
(define-public (contribute-funds (contribution-amount uint))
  (stx-transfer? contribution-amount tx-sender (as-contract tx-sender)))

;; GOVERNANCE PARAMETER UPDATES
(define-public (submit-threshold-modification (updated-threshold uint))
  (let ((new-proposal-id (var-get proposal-counter)))
    (asserts! (check-guardian-authorization tx-sender) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (> updated-threshold u0) ERR-INVALID-PARAMETER)
    (asserts! (<= updated-threshold (var-get total-active-guardians)) ERR-APPROVAL-THRESHOLD-EXCEEDED)
    
    (map-set treasury-proposals
      { proposal-identifier: new-proposal-id }
      {
        proposal-creator: tx-sender,
        recipient-address: tx-sender,
        amount-in-microstx: updated-threshold,
        description-memo: none,
        operation-type: "threshold-change",
        execution-status: false,
        cancellation-status: false,
        approval-votes-received: u1,
        expiration-block-height: (+ block-height u1008),
        timelock-release-block: (+ block-height (var-get timelock-period-blocks)),
        created-at-block: block-height
      })
    
    (var-set proposal-counter (+ new-proposal-id u1))
    (ok new-proposal-id)))

(define-public (apply-threshold-modification (proposal-id uint))
  (begin
    ;; Validate proposal ID
    (asserts! (validate-proposal-exists proposal-id) ERR-PROPOSAL-NOT-EXISTS)
    
    (match (map-get? treasury-proposals { proposal-identifier: proposal-id })
      proposal-data
        (begin
          (asserts! (is-eq (get operation-type proposal-data) "threshold-change") ERR-INVALID-PARAMETER)
          (asserts! (>= (get approval-votes-received proposal-data) (var-get minimum-approval-count)) ERR-UNAUTHORIZED-ACCESS)
          (asserts! (>= block-height (get timelock-release-block proposal-data)) ERR-TIMELOCK-STILL-ACTIVE)
          
          (var-set minimum-approval-count (get amount-in-microstx proposal-data))
          (map-set treasury-proposals
            { proposal-identifier: proposal-id }
            (merge proposal-data { execution-status: true }))
          (ok proposal-id))
      ERR-PROPOSAL-NOT-EXISTS)))

;; PROPOSAL CANCELLATION
(define-public (withdraw-proposal (proposal-id uint))
  (begin
    ;; Validate proposal ID
    (asserts! (validate-proposal-exists proposal-id) ERR-PROPOSAL-NOT-EXISTS)
    
    (match (map-get? treasury-proposals { proposal-identifier: proposal-id })
      proposal-data
        (begin
          (asserts! (not (get execution-status proposal-data)) ERR-PROPOSAL-ALREADY-COMPLETED)
          (asserts! (not (get cancellation-status proposal-data)) ERR-PROPOSAL-ALREADY-CANCELLED)
          (asserts! (or (is-eq (get proposal-creator proposal-data) tx-sender)
                       (>= (get approval-votes-received proposal-data) (var-get minimum-approval-count))) ERR-UNAUTHORIZED-ACCESS)
          
          (map-set treasury-proposals
            { proposal-identifier: proposal-id }
            (merge proposal-data { cancellation-status: true }))
          (ok proposal-id))
      ERR-PROPOSAL-NOT-EXISTS)))

;; HELPER FUNCTIONS

(define-private (process-daily-spending-update (spending-amount uint))
  (let ((current-day-number (/ block-height u144)))
    (if (> current-day-number (var-get last-reset-day))
      (begin
        (var-set current-daily-spent spending-amount)
        (var-set last-reset-day current-day-number)
        true)
      (begin
        (var-set current-daily-spent (+ (var-get current-daily-spent) spending-amount))
        true))))

;; READ-ONLY QUERY FUNCTIONS

(define-read-only (get-current-approval-threshold) (var-get minimum-approval-count))
(define-read-only (get-total-guardian-count) (var-get total-active-guardians))
(define-read-only (get-treasury-stx-balance) (stx-get-balance (as-contract tx-sender)))
(define-read-only (get-emergency-mode-status) (var-get emergency-mode-status))
(define-read-only (get-daily-spending-info) 
  { spent: (var-get current-daily-spent), limit: (var-get maximum-daily-spending) })

(define-read-only (check-guardian-authorization (wallet-address principal))
  (default-to false 
    (get active-status 
      (map-get? authorized-guardians { guardian-address: wallet-address }))))

(define-read-only (retrieve-proposal-information (proposal-id uint))
  (map-get? treasury-proposals { proposal-identifier: proposal-id }))

(define-read-only (check-guardian-vote-status (proposal-id uint) (guardian-wallet principal))
  (default-to false 
    (get approval-given 
      (map-get? guardian-votes 
        { proposal-identifier: proposal-id, voter-address: guardian-wallet }))))

(define-read-only (retrieve-guardian-information (wallet-address principal))
  (map-get? authorized-guardians { guardian-address: wallet-address }))

(define-read-only (retrieve-delegation-information (delegating-guardian-address principal))
  (map-get? voting-delegations { delegator-address: delegating-guardian-address }))