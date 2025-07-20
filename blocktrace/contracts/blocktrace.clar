;; Supply Chain Verification System
;; Enables tracking of products through the supply chain with
;; immutable records and verification at each step of the process

;; Product definitions
(define-map inventory-items
  { item-id: uint }
  {
    item-name: (string-utf8 128),
    item-description: (string-utf8 1024),
    producer: principal,
    lot-code: (string-ascii 64),
    established-at: uint,
    item-status: (string-ascii 32),  ;; "created", "in-transit", "delivered", "sold", "recalled"
    item-category: (string-ascii 64),
    source-location: (string-utf8 128),
    current-holder: principal,
    target-destination: (optional (string-utf8 128)),
    anticipated-delivery: (optional uint),
    data-uri: (optional (string-utf8 256))
  }
)

;; Supply chain checkpoints
(define-map waypoints
  { item-id: uint, waypoint-id: uint }
  {
    waypoint-location: (string-utf8 128),
    waypoint-timestamp: uint,
    waypoint-custodian: principal,
    validated-by: principal,
    waypoint-category: (string-ascii 32),  ;; "manufacture", "shipping", "customs", "warehouse", "retail", "delivery"
    ambient-temperature: (optional int),         ;; For temperature-sensitive goods
    ambient-humidity: (optional uint),           ;; For humidity-sensitive goods
    waypoint-notes: (optional (string-utf8 512)),
    verification-hash: (buff 32)         ;; Hash of checkpoint attestation document
  }
)

;; Authorized verifiers for each company
(define-map organization-validators
  { organization: principal, validator: principal }
  {
    validator-name: (string-utf8 128),
    validator-role: (string-ascii 64),
    validated-at: uint,
    validated-by: principal,
    validator-active: bool
  }
)

;; Custody transfers
(define-map ownership-transfers
  { item-id: uint, transfer-id: uint }
  {
    sender: principal,
    receiver: principal,
    initiated-timestamp: uint,
    finalized-timestamp: (optional uint),
    transfer-status: (string-ascii 32),  ;; "pending", "completed", "rejected", "cancelled"
    transfer-conditions: (optional (string-utf8 512))
  }
)

;; Certifications and compliance
(define-map compliance-certificates
  { item-id: uint, certificate-type: (string-ascii 64) }
  {
    certificate-issuer: principal,
    certificate-issued-at: uint,
    certificate-valid-until: uint,
    certificate-verification-hash: (buff 32),
    certificate-document-uri: (optional (string-utf8 256)),
    certificate-status: (string-ascii 32)  ;; "valid", "expired", "revoked"
  }
)

;; Next available IDs
(define-data-var next-item-id uint u0)
(define-map next-waypoint-id { item-id: uint } { id: uint })
(define-map next-transfer-id { item-id: uint } { id: uint })

;; Helper function to convert string to buffer for hashing
(define-private (string-utf8-to-buff (val (string-utf8 512)))
  ;; In a real implementation, you would convert the string to bytes
  0x68656c6c6f20776f726c64 ;; Example buffer (represents "hello world" in hex)
)

;; Helper function to convert ascii string to buffer for hashing
(define-private (ascii-to-buff (val (string-ascii 64)))
  ;; In a real implementation, you would convert the string to bytes
  0x68656c6c6f20776f726c64 ;; Example buffer (represents "hello world" in hex)
)

;; Helper function to convert principal to string
(define-private (principal-to-string (val principal))
  u"principal" ;; Simplified implementation
)

;; Register a new product
(define-public (register-inventory-item
                (item-name (string-utf8 128))
                (item-description (string-utf8 1024))
                (lot-code (string-ascii 64))
                (item-category (string-ascii 64))
                (source-location (string-utf8 128))
                (data-uri (optional (string-utf8 256))))
  (let
    ((item-id (var-get next-item-id)))
    
    ;; Create the product record
    (map-set inventory-items
      { item-id: item-id }
      {
        item-name: item-name,
        item-description: item-description,
        producer: tx-sender,
        lot-code: lot-code,
        established-at: block-height,
        item-status: "created",
        item-category: item-category,
        source-location: source-location,
        current-holder: tx-sender,
        target-destination: none,
        anticipated-delivery: none,
        data-uri: data-uri
      }
    )
    
    ;; Initialize checkpoint counter
    (map-set next-waypoint-id
      { item-id: item-id }
      { id: u0 }
    )
    
    ;; Initialize transfer counter
    (map-set next-transfer-id
      { item-id: item-id }
      { id: u0 }
    )
    
    ;; Create initial manufacturing checkpoint
    (try! (add-waypoint
           item-id
           source-location
           "manufacture"
           none
           none
           (some u"Product manufactured with batch code")
           (sha256 (ascii-to-buff lot-code))
         ))
    
    ;; Increment product ID counter
    (var-set next-item-id (+ item-id u1))
    
    (ok item-id)
  )
)

;; Add a checkpoint to a product's supply chain journey
(define-public (add-waypoint
                (item-id uint)
                (waypoint-location (string-utf8 128))
                (waypoint-category (string-ascii 32))
                (ambient-temperature (optional int))
                (ambient-humidity (optional uint))
                (waypoint-notes (optional (string-utf8 512)))
                (verification-hash (buff 32)))
  (let
    ((inventory-item (unwrap! (map-get? inventory-items { item-id: item-id }) (err u"Product not found")))
     (waypoint-counter (unwrap! (map-get? next-waypoint-id { item-id: item-id })
                                  (err u"Counter not found")))
     (waypoint-id (get id waypoint-counter)))
    
    ;; Validate
    (asserts! (or (is-eq tx-sender (get current-holder inventory-item))
                  (is-organization-validator (get current-holder inventory-item) tx-sender))
              (err u"Not authorized to add checkpoint"))
    (asserts! (not (is-eq (get item-status inventory-item) "recalled")) (err u"Product has been recalled"))
    
    ;; Create the checkpoint
    (map-set waypoints
      { item-id: item-id, waypoint-id: waypoint-id }
      {
        waypoint-location: waypoint-location,
        waypoint-timestamp: block-height,
        waypoint-custodian: (get current-holder inventory-item),
        validated-by: tx-sender,
        waypoint-category: waypoint-category,
        ambient-temperature: ambient-temperature,
        ambient-humidity: ambient-humidity,
        waypoint-notes: waypoint-notes,
        verification-hash: verification-hash
      }
    )
    
    ;; Update product status based on checkpoint type
    (map-set inventory-items
      { item-id: item-id }
      (merge inventory-item
        {
          item-status: (if (is-eq waypoint-category "delivery") "delivered"
                     (if (is-eq waypoint-category "retail-sale") "sold" "in-transit"))
        }
      )
    )
    
    ;; Increment checkpoint counter
    (map-set next-waypoint-id
      { item-id: item-id }
      { id: (+ waypoint-id u1) }
    )
    
    (ok waypoint-id)
  )
)

;; Check if a principal is an authorized verifier for a company
(define-private (is-organization-validator (organization principal) (validator principal))
  (match (map-get? organization-validators { organization: organization, validator: validator })
    validator-data (get validator-active validator-data)
    false
  )
)

;; Authorize a verifier for a company
(define-public (authorize-validator
                (validator principal)
                (validator-name (string-utf8 128))
                (validator-role (string-ascii 64)))
  (begin
    ;; Set verifier as authorized
    (map-set organization-validators
      { organization: tx-sender, validator: validator }
      {
        validator-name: validator-name,
        validator-role: validator-role,
        validated-at: block-height,
        validated-by: tx-sender,
        validator-active: true
      }
    )
    
    (ok true)
  )
)

;; Revoke a verifier's authorization
(define-public (revoke-validator (validator principal))
  (let
    ((validator-data (unwrap! (map-get? organization-validators { organization: tx-sender, validator: validator })
                            (err u"Verifier not found"))))
    
    (map-set organization-validators
      { organization: tx-sender, validator: validator }
      (merge validator-data { validator-active: false })
    )
    
    (ok true)
  )
)

;; Initiate custody transfer of a product
(define-public (initiate-ownership-transfer
                (item-id uint)
                (receiver principal)
                (transfer-conditions (optional (string-utf8 512))))
  (let
    ((inventory-item (unwrap! (map-get? inventory-items { item-id: item-id }) (err u"Product not found")))
     (transfer-counter (unwrap! (map-get? next-transfer-id { item-id: item-id })
                                (err u"Counter not found")))
     (transfer-id (get id transfer-counter)))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get current-holder inventory-item))
              (err u"Only current custodian can initiate transfer"))
    (asserts! (not (is-eq (get item-status inventory-item) "recalled"))
              (err u"Product has been recalled"))
    
    ;; Create transfer record
    (map-set ownership-transfers
      { item-id: item-id, transfer-id: transfer-id }
      {
        sender: tx-sender,
        receiver: receiver,
        initiated-timestamp: block-height,
        finalized-timestamp: none,
        transfer-status: "pending",
        transfer-conditions: transfer-conditions
      }
    )
    
    ;; Increment transfer counter
    (map-set next-transfer-id
      { item-id: item-id }
      { id: (+ transfer-id u1) }
    )
    
    (ok transfer-id)
  )
)

;; Accept a custody transfer
(define-public (accept-ownership-transfer (item-id uint) (transfer-id uint))
  (let
    ((inventory-item (unwrap! (map-get? inventory-items { item-id: item-id }) (err u"Product not found")))
     (ownership-transfer (unwrap! (map-get? ownership-transfers { item-id: item-id, transfer-id: transfer-id })
                       (err u"Transfer not found"))))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get receiver ownership-transfer)) (err u"Only recipient can accept"))
    (asserts! (is-eq (get transfer-status ownership-transfer) "pending") (err u"Transfer not pending"))
    
    ;; Update transfer record
    (map-set ownership-transfers
      { item-id: item-id, transfer-id: transfer-id }
      (merge ownership-transfer
        {
          finalized-timestamp: (some block-height),
          transfer-status: "completed"
        }
      )
    )
    
    ;; Update product custodian
    (map-set inventory-items
      { item-id: item-id }
      (merge inventory-item { current-holder: tx-sender })
    )
    
    ;; Add a checkpoint for the custody transfer
    (try! (add-waypoint
           item-id
           u"custody-transfer" ;; Generic location for transfer as utf8
           "transfer"
           none
           none
           (some u"Custody transferred")
           (sha256 (string-utf8-to-buff u"custody-transfer"))
         ))
    
    (ok true)
  )
)

;; Reject a custody transfer
(define-public (reject-ownership-transfer (item-id uint) (transfer-id uint) (rejection-reason (string-utf8 512)))
  (let
    ((ownership-transfer (unwrap! (map-get? ownership-transfers { item-id: item-id, transfer-id: transfer-id })
                       (err u"Transfer not found"))))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get receiver ownership-transfer)) (err u"Only recipient can reject"))
    (asserts! (is-eq (get transfer-status ownership-transfer) "pending") (err u"Transfer not pending"))
    
    ;; Update transfer record
    (map-set ownership-transfers
      { item-id: item-id, transfer-id: transfer-id }
      (merge ownership-transfer
        {
          finalized-timestamp: (some block-height),
          transfer-status: "rejected",
          transfer-conditions: (some rejection-reason)
        }
      )
    )
    
    (ok true)
  )
)

;; Cancel a pending transfer (only current custodian)
(define-public (cancel-ownership-transfer (item-id uint) (transfer-id uint))
  (let
    ((ownership-transfer (unwrap! (map-get? ownership-transfers { item-id: item-id, transfer-id: transfer-id })
                       (err u"Transfer not found"))))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get sender ownership-transfer)) (err u"Only sender can cancel"))
    (asserts! (is-eq (get transfer-status ownership-transfer) "pending") (err u"Transfer not pending"))
    
    ;; Update transfer record
    (map-set ownership-transfers
      { item-id: item-id, transfer-id: transfer-id }
      (merge ownership-transfer
        {
          finalized-timestamp: (some block-height),
          transfer-status: "cancelled"
        }
      )
    )
    
    (ok true)
  )
)

;; Add certification to a product
(define-public (add-compliance-certificate
                (item-id uint)
                (certificate-type (string-ascii 64))
                (certificate-valid-until uint)
                (certificate-verification-hash (buff 32))
                (certificate-document-uri (optional (string-utf8 256))))
  (let
    ((inventory-item (unwrap! (map-get? inventory-items { item-id: item-id }) (err u"Product not found"))))
    
    ;; Validate
    (asserts! (or (is-eq tx-sender (get producer inventory-item))
                  (is-organization-validator (get producer inventory-item) tx-sender))
              (err u"Not authorized to add certification"))
    (asserts! (> certificate-valid-until block-height) (err u"Certification must be valid for future blocks"))
    
    ;; Add certification
    (map-set compliance-certificates
      { item-id: item-id, certificate-type: certificate-type }
      {
        certificate-issuer: tx-sender,
        certificate-issued-at: block-height,
        certificate-valid-until: certificate-valid-until,
        certificate-verification-hash: certificate-verification-hash,
        certificate-document-uri: certificate-document-uri,
        certificate-status: "valid"
      }
    )
    
    (ok true)
  )
)

;; Revoke a certification
(define-public (revoke-compliance-certificate (item-id uint) (certificate-type (string-ascii 64)))
  (let
    ((compliance-certificate (unwrap! (map-get? compliance-certificates
                                { item-id: item-id, certificate-type: certificate-type })
                             (err u"Certification not found"))))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get certificate-issuer compliance-certificate))
              (err u"Only issuer can revoke certification"))
    
    ;; Update certification
    (map-set compliance-certificates
      { item-id: item-id, certificate-type: certificate-type }
      (merge compliance-certificate { certificate-status: "revoked" })
    )
    
    (ok true)
  )
)

;; Issue a product recall
(define-public (recall-inventory-item (item-id uint) (recall-reason (string-utf8 512)))
  (let
    ((inventory-item (unwrap! (map-get? inventory-items { item-id: item-id }) (err u"Product not found"))))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get producer inventory-item))
              (err u"Only manufacturer can recall product"))
    
    ;; Update product status
    (map-set inventory-items
      { item-id: item-id }
      (merge inventory-item { item-status: "recalled" })
    )
    
    ;; Add a checkpoint for the recall
    (try! (add-waypoint
           item-id
           u"recall" ;; Using utf8 string for location
           "recall"
           none
           none
           (some recall-reason)
           (sha256 (string-utf8-to-buff recall-reason))
         ))
    
    (ok true)
  )
)

;; Set final destination and expected delivery
(define-public (set-delivery-details
                (item-id uint)
                (target-destination (string-utf8 128))
                (anticipated-delivery uint))
  (let
    ((inventory-item (unwrap! (map-get? inventory-items { item-id: item-id }) (err u"Product not found"))))
    
    ;; Validate
    (asserts! (or (is-eq tx-sender (get current-holder inventory-item))
                  (is-organization-validator (get current-holder inventory-item) tx-sender))
              (err u"Not authorized to set shipping details"))
    
    ;; Update product
    (map-set inventory-items
      { item-id: item-id }
      (merge inventory-item
        {
          target-destination: (some target-destination),
          anticipated-delivery: (some anticipated-delivery)
        }
      )
    )
    
    (ok true)
  )
)

;; Read-only functions
;; Get product details
(define-read-only (get-inventory-item-details (item-id uint))
  (ok (unwrap! (map-get? inventory-items { item-id: item-id }) (err u"Product not found")))
)

;; Get checkpoint details
(define-read-only (get-waypoint (item-id uint) (waypoint-id uint))
  (ok (unwrap! (map-get? waypoints { item-id: item-id, waypoint-id: waypoint-id })
              (err u"Checkpoint not found")))
)

;; Get transfer details
(define-read-only (get-ownership-transfer (item-id uint) (transfer-id uint))
  (ok (unwrap! (map-get? ownership-transfers { item-id: item-id, transfer-id: transfer-id })
              (err u"Transfer not found")))
)

;; Get certification details
(define-read-only (get-compliance-certificate (item-id uint) (certificate-type (string-ascii 64)))
  (ok (unwrap! (map-get? compliance-certificates { item-id: item-id, certificate-type: certificate-type })
              (err u"Certification not found")))
)

;; Check if certification is valid
(define-read-only (is-certificate-valid (item-id uint) (certificate-type (string-ascii 64)))
  (match (map-get? compliance-certificates { item-id: item-id, certificate-type: certificate-type })
    compliance-certificate (and (is-eq (get certificate-status compliance-certificate) "valid")
                       (> (get certificate-valid-until compliance-certificate) block-height))
    false
  )
)

;; Verify product authenticity (basic check)
(define-read-only (verify-inventory-item-authenticity (item-id uint))
  (match (map-get? inventory-items { item-id: item-id })
    inventory-item (ok {
              authentic: true,
              producer: (get producer inventory-item),
              lot-code: (get lot-code inventory-item),
              item-status: (get item-status inventory-item)
            })
    (err u"Product not found")
  )
)