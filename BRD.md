# Business Requirements Document (BRD) — Ziggo Super App

| Field | Detail |
|---|---|
| **Project** | Ziggo — Multi-vertical Super App (Rides · Food · Market · Flash) |
| **Prepared by** | Hashnate |
| **Status** | Updated v2.0 |
| **Platforms** | Android & iOS mobile app (customer + driver), Web admin panel |
| **Inspiration / benchmark** | PickMe (Sri Lanka super-app) |

---

## 1. Introduction

### 1.1 Purpose
This document defines the business requirements for **Ziggo**, a PickMe-style super app for Sri Lanka. It is the single reference for what the product does, for all stakeholders — business, design, engineering, and QA.

### 1.2 Product Summary
Ziggo is an on-demand platform combining four service verticals in one app:
- **Rides** — ride-hailing (bike, three-wheeler, car, van, truck)
- **Food** — restaurant food ordering & delivery
- **Market** — grocery / retail / pharmacy ordering & delivery
- **Flash** — parcel / courier delivery

It is delivered as three products:
1. **Customer mobile app** (Flutter)
2. **Driver mobile app** (same Flutter binary; role chosen at login)
3. **Backend API + Admin web panel** (FastAPI + server-rendered admin)

### 1.3 Status Legend
Each requirement is tagged with its delivery state:
- **[Built]** — implemented in the current codebase
- **[Partial]** — backend/model exists; UI or end-to-end flow incomplete
- **[Planned]** — required for PickMe-parity; not yet implemented

---

## 2. Business Objectives

| # | Objective |
|---|---|
| BO-1 | Provide a single app for everyday mobility and delivery needs in Sri Lanka |
| BO-2 | Onboard and manage a driver fleet across multiple vehicle and service types |
| BO-3 | Generate revenue via platform commission, surge pricing, and a Gold subscription tier |
| BO-4 | Give operations staff full control via a web admin panel (drivers, pricing, catalog, complaints) |
| BO-5 | Centralize corporate transport and logistics controls through Corporate Accounts |

---

## 3. Project Scope

### 3.1 In Scope
- Customer and driver mobile experiences for all four verticals (Rides, Food, Market, Flash)
- Phone-OTP authentication and role-based access
- Real-time ride/order dispatch, tracking, and status updates
- Fare/pricing engine, promo codes, digital wallet, Gold subscription
- Google Maps map rendering, Places search, and Directions routing
- Admin web panel for operations, catalog, pricing, support, and administrative user roles (RBAC)
- Corporate accounts (Ziggo for Business) and invoicing controls
- PayHere payment gateway integration

### 3.2 Out of Scope (Current Phase)
- SMS delivery of OTP (printed/returned in dev mode console)
- Cloud storage for documents/images
- Advanced AI-analytics predictive dashboards

---

## 4. Stakeholders & Actors

| Actor | Description |
|---|---|
| **Customer** | End user booking rides, food, market orders, and parcels |
| **Driver / Rider** | Fleet partner fulfilling rides and deliveries |
| **Admin / Operations** | Internal staff managing the platform via the web panel (Superadmin, Admin, Data Entry) |
| **Restaurant / Vendor partner** | Self-service partner managing menu/products & orders |
| **Support agent** | Staff handling complaints and support chat |

---

## 5. Functional Requirements

### 5.1 Platform-Wide / Cross-Cutting

| ID | Requirement | Status |
|---|---|---|
| FR-GEN-001 | Phone-number registration & login via OTP | Built |
| FR-GEN-002 | JWT-based session management | Built |
| FR-GEN-003 | Role-based access control (customer / driver / admin) | Built |
| FR-GEN-004 | Role selection at first launch (Ride & Order / Drive & Earn) | Built |
| FR-GEN-005 | Real-time event delivery via WebSocket (dispatch, status, alerts) | Built |
| FR-GEN-006 | In-app notification centre with read/unread state | Built |
| FR-GEN-007 | Profile management (name, email) | Built |
| FR-GEN-008 | Profile photo upload | Built |
| FR-GEN-009 | Saved addresses (Home / Work / custom labels) | Built |
| FR-GEN-010 | Two-way ratings & reviews (customer ↔ driver) | Built |
| FR-GEN-011 | Promo codes — percentage & fixed discounts, usage limits, validity window | Built |
| FR-GEN-012 | Digital wallet — balance, top-up, transaction ledger | Built |
| FR-GEN-013 | Auto-debit from wallet on wallet-paid trips/orders | Built |
| FR-GEN-014 | "Ziggo Gold" subscription — subscribe, status, expiry | Built |
| FR-GEN-015 | Gold perk enforcement (reduced delivery fees, prioritizations) | Built |
| FR-GEN-016 | Complaints / support ticket creation & history | Built |
| FR-GEN-017 | In-app support chat with live agent | Built |
| FR-GEN-018 | Multi-language support (English / Sinhala / Tamil) | Planned |
| FR-GEN-019 | Push notifications (FCM) | Built |
| FR-GEN-020 | Referral / invite program | Planned |
| FR-GEN-021 | Loyalty points / rewards program | Built |
| FR-GEN-022 | Gift cards / vouchers | Planned |

### 5.2 Maps & Location

| ID | Requirement | Status |
|---|---|---|
| FR-MAP-001 | Interactive map rendering (Google Maps SDK) | Built |
| FR-MAP-002 | Markers & route polylines on all map screens | Built |
| FR-MAP-003 | Google Places autocomplete for location search | Built |
| FR-MAP-004 | Place-detail resolution to coordinates | Built |
| FR-MAP-005 | Directions API — real road-following route & ETA | Built |
| FR-MAP-006 | Live driver GPS location streaming | Built |
| FR-MAP-007 | Device GPS for current location / pickup detection | Built |
| FR-MAP-008 | Reverse geocoding (coordinate → address) | Built |

### 5.3 Customer App — Rides

| ID | Requirement | Status |
|---|---|---|
| FR-RIDE-001 | Select pickup & destination via Places search | Built |
| FR-RIDE-002 | Fare estimate per vehicle class before booking | Built |
| FR-RIDE-003 | Vehicle classes: Bike, Three-wheeler, Car, Van, Truck | Built |
| FR-RIDE-004 | Apply promo code at booking | Built |
| FR-RIDE-005 | Choose payment method (cash / wallet / corporate) | Built |
| FR-RIDE-006 | Create booking; dispatch to nearest available driver | Built |
| FR-RIDE-007 | Driver accept / decline with auto-forward to next driver | Built |
| FR-RIDE-008 | Live ride tracking — driver position, route, status | Built |
| FR-RIDE-009 | Ride state machine: Searching → Accepted → Arrived → Started → Completed / Cancelled | Built |
| FR-RIDE-010 | Cancel ride with reason | Built |
| FR-RIDE-011 | Rate & review the driver after completion | Built |
| FR-RIDE-012 | Ride history with trip details | Built |
| FR-RIDE-013 | Card / online payment for rides via PayHere | Built |
| FR-RIDE-014 | Scheduled / advance ride booking | Planned |
| FR-RIDE-015 | Multiple stops / waypoints | Built |
| FR-RIDE-016 | In-app calling with the driver | Built |
| FR-RIDE-017 | Share live trip / ETA with contacts | Built |
| FR-RIDE-018 | SOS / emergency safety button | Built |
| FR-RIDE-019 | Special ride types (Pink Rides for women) | Planned |
| FR-RIDE-020 | Pooled / shared rides | Planned |
| FR-RIDE-021 | Trip receipts / invoices | Built |

### 5.4 Customer App — Food

| ID | Requirement | Status |
|---|---|---|
| FR-FOOD-001 | Browse restaurant listing (cuisine, rating, delivery fee, ETA) | Built |
| FR-FOOD-002 | View restaurant detail with menu by category | Built |
| FR-FOOD-003 | View menu item detail (price, veg flag, prep time) | Built |
| FR-FOOD-004 | Add items to cart & checkout with delivery address | Built |
| FR-FOOD-005 | Place food order; order history | Built |
| FR-FOOD-006 | Food order tracking (Pending → Confirmed → Preparing → Ready → Out for delivery → Delivered) | Built |
| FR-FOOD-007 | Restaurant search & filters (cuisine, rating, price) | Planned |
| FR-FOOD-008 | Item customization / add-ons / special instructions | Built |

### 5.5 Customer App — Market (Grocery / Retail)

| ID | Requirement | Status |
|---|---|---|
| FR-MKT-001 | Browse vendors by category (Grocery, Pharmacy, etc.) | Built |
| FR-MKT-002 | Browse product catalog (price, unit, stock) | Built |
| FR-MKT-003 | Add products to cart & checkout with delivery address | Built |
| FR-MKT-004 | Place market order; order history | Built |
| FR-MKT-005 | Market order tracking | Built |

### 5.6 Customer App — Flash (Parcel Courier)

| ID | Requirement | Status |
|---|---|---|
| FR-FLASH-001 | Book a parcel: pickup, drop-off, receiver name & phone | Built |
| FR-FLASH-002 | Capture parcel metadata (type, weight, instructions) | Built |
| FR-FLASH-003 | Same dispatch + state machine as rides (booking ref prefixed `FL`) | Built |
| FR-FLASH-004 | Live parcel-delivery tracking | Built |

### 5.7 Customer App — Wallet & Home

| ID | Requirement | Status |
|---|---|---|
| FR-WALLET-001 | View wallet balance & transaction history | Built |
| FR-WALLET-002 | Top up wallet | Built |
| FR-WALLET-003 | Card / PayHere / Stripe top-up | Built |
| FR-HOME-001 | Home dashboard — services grid, wallet, Gold upsell, active-ride awareness | Built |
| FR-HOME-002 | Bottom navigation shell (Mart · Rides · Home · Alerts · Profile) | Built |
| FR-HOME-003 | Global location search entry point | Built |

### 5.8 Driver App

| ID | Requirement | Status |
|---|---|---|
| FR-DRV-001 | Driver registration (vehicle, license, NIC details) | Built |
| FR-DRV-002 | Driver document upload (NIC, license, insurance, vehicle reg) | Built |
| FR-DRV-003 | Online / Offline toggle (gated on approval + complete profile) | Built |
| FR-DRV-004 | Live GPS location streaming while online | Built |
| FR-DRV-005 | Receive ride/parcel requests with 30-second accept/decline window | Built |
| FR-DRV-006 | Manage active trip (Arrived → Started → Completed) | Built |
| FR-DRV-007 | Decline request → backend forwards to next nearest driver | Built |
| FR-DRV-008 | Earnings dashboard (today's earnings, rides, total) | Built |
| FR-DRV-009 | Trip & earnings history | Built |
| FR-DRV-010 | Driver rating & acceptance-rate display | Built |
| FR-DRV-011 | Rate the customer | Built |
| FR-DRV-012 | Incentives / bonus targets / quests | Built |
| FR-DRV-013 | Demand heatmap / hotspot zones | Planned |
| FR-DRV-014 | In-app turn-by-turn navigation | Built |
| FR-DRV-015 | Driver payout & cash-settlement management | Built |
| FR-DRV-016 | Multi-service driver (fulfil Food/Market deliveries) | Built |

### 5.9 Admin Web Panel

| ID | Requirement | Status |
|---|---|---|
| FR-ADM-001 | Admin login (separate signed-cookie session) | Built |
| FR-ADM-002 | Dashboard — live counts, revenue, completed/cancelled, 7-day revenue chart | Built |
| FR-ADM-003 | Driver management — list, create, approve, suspend | Built |
| FR-ADM-004 | Customer management — list & profiles | Built |
| FR-ADM-005 | Bookings (rides) — list, status, customer/driver detail | Built |
| FR-ADM-006 | Flash (parcels) — list, active count, delivered-today, revenue stats | Built |
| FR-ADM-007 | Fare settings — base/per-km/per-min/min-fare/platform-fee/surge, live-editable | Built |
| FR-ADM-008 | Restaurant management — create restaurant, add menu categories & items | Built |
| FR-ADM-009 | Market vendor management — create vendor, add products | Built |
| FR-ADM-010 | Promotions — list & detail | Built |
| FR-ADM-011 | Promotions — create / edit / deactivate UI | Built |
| FR-ADM-012 | Complaints — list & status | Built |
| FR-ADM-013 | Complaints — assignment & resolution workflow | Built |
| FR-ADM-014 | Platform settings | Built |
| FR-ADM-015 | Analytics & reporting suite | Built |
| FR-ADM-016 | Driver payout management | Built |
| FR-ADM-017 | Surge-zone management | Planned |
| FR-ADM-018 | Push-notification / promo broadcaster | Built |
| FR-ADM-019 | Banner / content management | Built |
| FR-ADM-020 | Multiple admin users with sub-roles (RBAC) & audit log | Built |

---

## 6. Business Rules

| ID | Rule |
|---|---|
| BR-1 | **Fare** = max(base + per-km×distance + per-min×duration, min-fare) × surge − promo discount |
| BR-2 | **Platform fee** = final fare × platform-fee %; **driver earnings** = final fare − platform fee |
| BR-3 | Fare rates are per-vehicle-type and editable by admins; a default table applies if unset |
| BR-4 | A booking is dispatched only to the **nearest online + approved driver** of the matching vehicle type within the search radius |
| BR-5 | On ride completion: wallet payments debit the customer wallet & write a ledger entry; driver earnings totals are updated |
| BR-6 | A customer rating updates the driver's aggregate rating and total trips |
| BR-7 | A driver may go online only when their profile is complete **and** approved by an admin |
| BR-8 | Flash parcels require a receiver phone number; booking refs are prefixed `FL` (rides use `ZG`) |
| BR-9 | Admin login uses phone + password; customers/drivers use phone-OTP only |
| BR-10 | All monetary values are LKR; coordinates and timestamps are stored with full precision in UTC |

---

## 7. Non-Functional Requirements

| ID | Requirement | Status |
|---|---|---|
| NFR-1 | Pricing engine with surge, min-fare floor, promo, platform-fee split | Built |
| NFR-2 | Nearest-driver matching by vehicle type within radius | Built |
| NFR-3 | Production-scale geo-matching / spatial indexing | Built |
| NFR-4 | Real-time messaging must scale beyond a single server (Redis pub/sub) | Planned |
| NFR-5 | Payment gateway integration (PayHere) | Built |
| NFR-6 | SMS gateway integration (Twilio) for OTP | Built |
| NFR-7 | Cloud storage for documents & images | Planned |
| NFR-8 | Localisation framework (EN / SI / TA) | Planned |
| NFR-9 | API keys (Maps web services) secured server-side, not shipped in the app | Planned |
| NFR-10 | Responsive admin panel; secure session handling | Built |

---

## 8. Assumptions & Constraints

- The current build runs against **local stubs** for SMS OTP (printed/returned in dev mode console) and uses WebSockets for tracking.
- Google Maps SDK, Places, and Directions are **live integrations** as of this version.
- PostgreSQL is the production database; SQLite is configured for local testing.
