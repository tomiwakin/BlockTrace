# 🧱 BlockTrace

### Supply Chain Verification Smart Contract on Stacks

**BlockTrace** is a Clarity smart contract designed to bring **transparency**, **traceability**, and **trust** to global supply chains. Built on the Stacks blockchain, it ensures that every step in a product's journey—from manufacturing to delivery—is securely recorded and verifiable.

---

## ✨ Key Features

* **Product Registration**
  Manufacturers can register detailed metadata about products including batch codes, origin, and type.

* **Immutable Checkpoints**
  Add verifiable checkpoints (e.g., customs, warehouse, retail) with attestation hashes and optional environmental data (temperature/humidity).

* **Custody Transfer**
  Enables secure, auditable transfer of product ownership with status tracking: pending, completed, rejected, or cancelled.

* **Verifier Management**
  Companies can authorize or revoke trusted agents to verify checkpoint data.

* **Certifications & Compliance**
  Issue, verify, and revoke compliance certificates with embedded metadata and hashes for proof.

* **Product Recall**
  Manufacturers can initiate product recalls and record justifications immutably.

* **Shipping Details**
  Assign final destinations and expected delivery blocks to track logistics flow.

---

## 🧩 Contract Components

### ✅ Data Maps

* `products` – Product metadata and current status
* `checkpoints` – Logs of each verification step
* `custody-transfers` – Ownership handoff records
* `company-verifiers` – Authorized checkpoint verifiers
* `certifications` – Regulatory or quality approvals

### ⚙️ Core Public Functions

* `register-product` – Adds a new product to the system
* `add-checkpoint` – Records a new supply chain event
* `initiate-transfer` – Starts custody handoff
* `accept-transfer`, `reject-transfer`, `cancel-transfer` – Handle custody flow
* `authorize-verifier` / `revoke-verifier` – Manage verifiers
* `add-certification` / `revoke-certification` – Manage product certifications
* `recall-product` – Marks a product as recalled
* `set-shipping-details` – Define destination and ETA

### 🔍 Read-only Functions

* `get-product-details`, `get-checkpoint`, `get-transfer`, etc.
* `verify-product-authenticity`
* `is-certification-valid`

---

## 🔐 Authorization Rules

* Only **manufacturers** can recall products or add certifications (unless verifiers are authorized).
* Only **current custodians** can initiate transfers.
* Only **authorized verifiers** or custodians can add checkpoints.

---

## 📦 Use Cases

* **Pharmaceuticals** – Track temperature-sensitive medicines.
* **Luxury Goods** – Prevent counterfeit products.
* **Food Supply** – Ensure freshness and compliance.
* **Electronics** – Monitor component traceability and recalls.

---

## 🛠 Deployment

Ensure Clarity language is installed. Deploy the `BlockTrace` contract using the Stacks CLI or Clarinet:

```bash
clarinet contract publish BlockTrace
```

Run tests or call functions via your preferred Stacks environment.

---

## 📄 License

MIT License
