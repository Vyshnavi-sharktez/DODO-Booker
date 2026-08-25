# DODO Booker — Product Requirements Document v1.0

**Version:** 1.0
**Date:** August 2026
**Status:** Active
**Owner:** touchwood529@gmail.com

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Goals and Success Metrics](#2-goals-and-success-metrics)
3. [Users and Personas](#3-users-and-personas)
4. [Scope](#4-scope)
5. [Functional Requirements](#5-functional-requirements)
6. [Non-Functional Requirements](#6-non-functional-requirements)
7. [User Flows and Use Cases](#7-user-flows-and-use-cases)
8. [Constraints and Assumptions](#8-constraints-and-assumptions)
9. [Open Product Decisions](#9-open-product-decisions)
10. [Acceptance Criteria](#10-acceptance-criteria)

---

## 1. Problem Statement

### 1.1 The Problem

Households in India need reliable, vetted professionals for home services — cleaning, appliance repair, beauty, plumbing, home maintenance, and similar. The current options are fragmented: customers rely on word-of-mouth, unverified listings, or platforms with poor accountability. Service quality is inconsistent, job completion is unverifiable, and pricing is opaque.

For service providers (vendors), the reverse problem exists: they lack structured access to a steady customer base, have no transparent earnings model, and no platform accountability mechanism that rewards reliability.

### 1.2 Who Is Affected

- **Customers** who cannot easily find, book, and trust a home service professional.
- **Vendors** who cannot reliably acquire customers or demonstrate quality to build reputation.
- **Platform administrators** who need to manage a two-sided marketplace without deploying code for routine operations.

### 1.3 Why This Matters Now

Urban Indian households are increasingly comfortable booking services digitally. The home services market is large and underserved by platforms with strong accountability and verified job completion. An early, well-operated platform that solves trust and reliability can establish a durable market position.

---

## 2. Goals and Success Metrics

### 2.1 Product Goals

| Goal | Description |
|---|---|
| **Trusted job completion** | Every completed job has verifiable proof: before/after photos and a customer-confirmed OTP. Neither party can fake completion. |
| **Transparent pricing** | Customers see a full price breakdown before booking. No surprises. |
| **Fair vendor dispatch** | Bookings are offered to vendors in a fair, priority-ordered queue. Vendors have a clear window to accept or reject. |
| **Zero-code operations** | Administrators manage all services, pricing, geographies, promotions, and scheduling without a code deployment. |
| **Financial integrity** | Platform commission, vendor earnings, and vendor security deposits are accounted for separately and accurately. |
| **Multi-city scalability** | The platform can expand to new cities and services through admin configuration alone. |

### 2.2 Success Metrics

| Metric | Target (illustrative) |
|---|---|
| Booking completion rate | > 85% of accepted bookings reach Completed status |
| Dispatch acceptance rate | > 75% of bookings accepted by first-offered vendor |
| Customer repeat rate | > 40% of customers book again within 90 days |
| Vendor reliability score | < 10% rejection rate per active vendor |
| Average booking-to-assignment time | < 5 minutes |
| Customer support ticket volume | Decreasing month-over-month as self-service improves |
| Warranty claim rate | < 5% of completed bookings |

---

## 3. Users and Personas

### 3.1 Customer

**Who:** End consumers booking home services for their household.

**Goals:**
- Find the right service quickly.
- Know what they will pay before confirming.
- Trust that the vendor will show up and do the job.
- Have recourse if the job quality is poor.

**Pain points:** Opaque pricing, unreliable professionals, no proof of work done, no easy rebooking.

**Access model:** Browses catalog without signing in. Must authenticate (phone OTP) to book, pay, review, or claim a warranty.

---

### 3.2 Vendor

**Who:** Independent service professionals or small businesses providing home services.

**Goals:**
- Receive a steady stream of job assignments.
- Get paid reliably and transparently.
- Build a reputation that earns them better assignments over time.
- Understand their standing on the platform (balance, tier, ratings).

**Pain points:** Irregular customer flow, unclear commission deductions, no platform-backed credibility signal.

**Access model:** Authenticated on Android, iOS, and web/desktop. Single login per vendor organization (owner). Online/offline toggle governs dispatch eligibility.

---

### 3.3 DODO Supervisor

**Who:** A field supervisor employed by the DODO platform who monitors vendor job progress.

**Goals:**
- See active and recent bookings in their assigned area.
- Verify job progress without managing vendor accounts.

**Access model:** Uses the vendor app with a restricted view. Cannot manage wallet, profile, or subscriptions. Created and managed by Admin.

---

### 3.4 Platform Administrator

**Who:** Internal DODO Booker staff operating the marketplace.

**Goals:**
- Configure the service catalog and pricing without code changes.
- Monitor bookings, vendors, and platform health in real time.
- Manage vendor approvals, payouts, and disputes.
- Run promotions, manage SEO, and operate the content layer.

**Access model:** Web-based admin panel. Role-based permissions control what each admin user can see and do.

---

## 4. Scope

### 4.1 In Scope (v1.0)

- Customer-facing service catalog (browsing, search, service detail)
- Customer booking creation, management, and cancellation
- Vendor dispatch, assignment, accept/reject flow
- OTP-verified job completion with before/after photo evidence
- Razorpay online payment (UPI, card, net banking)
- Cash on Delivery (COD) with vendor security-bond eligibility gate
- Vendor security-bond wallet (top-up, deductions, balance visibility)
- Vendor earnings and admin-processed settlements (separate from security bond)
- Commission deduction on booking completion
- Loyalty program (earn on completion, redeem at checkout)
- Coupons and promotional discounts
- Surge pricing and tax configuration
- Annual Maintenance Contracts (AMC): purchase, visit scheduling, pause/resume/cancel
- Service warranties: auto-generated on completion, customer claim flow, rework booking
- Customer reviews and ratings
- Customer questions and admin answers (Q&A)
- Admin-curated service showcase (before/after images)
- GPS-based geofencing and customer cancellation audit
- Vendor app on Android, iOS, and web/desktop
- Vendor subscription plans (infrastructure; enforcement to be activated)
- Admin audit log for important administrative and financial actions
- Admin panel: full catalog, booking, vendor, customer, financial, SEO, and CMS management
- Platform CMS: landing page sections, blogs, banners, static pages
- SEO management: per-service metadata, location pages, sitemap, redirects
- Role-based access control for admin users
- Notification system (in-app; external channels planned)
- Multi-city geographic configuration

### 4.2 Explicitly Out of Scope (v1.0)

- Customer support ticket system (no ticket creation, assignment, or resolution)
- Real telephony via call bridge (call logging is recorded but no actual call is placed)
- Vendor wallet withdrawal (no withdrawal functionality is planned in v1.0)
- Vendor staff sub-accounts and internal vendor RBAC
- Automated refund processing via payment gateway
- Bulk/segment push notifications to customers or vendors
- Third-party SMS or push delivery (channel infrastructure exists but delivery is not confirmed active)
- Customer account deletion

---

## 5. Functional Requirements

### 5.1 Service Catalog

**FR-CAT-1:** The catalog must support unlimited category nesting. A service can appear under more than one parent category without being duplicated.

**FR-CAT-2:** Each service must display its name, description, base price, available addons, FAQs, customer Q&A (answered only), reviews (approved only), and admin-curated showcase photos.

**FR-CAT-3:** Services configured with location restrictions must only be visible to customers whose location satisfies those restrictions.

**FR-CAT-4:** Hidden or unavailable services must not appear in catalog browsing or search results.

**FR-CAT-5:** Search must support service name matching with a minimum of 2 characters. Search must respect availability and location restrictions.

**FR-CAT-6:** All catalog configuration — categories, services, pricing, scheduling, addons, FAQs, restrictions — must be manageable by admin without a code deployment.

---

### 5.2 Booking Creation

**FR-BK-1:** Customers must be able to select a service, fill in service-specific attributes, choose an address, select a date and time slot, apply a coupon or loyalty points, and confirm a booking in a single uninterrupted flow.

**FR-BK-2:** The price breakdown (base price, attribute adjustments, addons, surge, tax, coupon discount, loyalty discount, final amount) must be shown to the customer before they confirm.

**FR-BK-3:** The price displayed at checkout must exactly match the price recorded on the booking. Price changes to the catalog after booking creation must not affect the existing booking.

**FR-BK-4:** A booking cannot be created for a service that is not available at the customer's address.

**FR-BK-5:** Customers must be able to select an optional addon at booking time. Addons must have their own price.

**FR-BK-6:** Customers may select a preferred vendor from vendors who are currently online and available at the time of booking. Selecting a preferred vendor adds a preferred-vendor fee to the booking.

---

### 5.3 Payment

**FR-PAY-1:** Customers must be able to pay online via UPI, card, or net banking (through the configured payment gateway).

**FR-PAY-2:** Payment verification must happen server-side. A customer must not be able to fake a successful payment.

**FR-PAY-3:** Cash on Delivery (COD) must be available as a payment option for all services. COD availability is a platform-wide setting — it cannot be disabled per service, category, or location.

**FR-PAY-4:** A vendor may only be assigned a COD booking if their security-bond balance is at or above the platform-configured minimum balance. Vendors below the minimum must not receive COD assignments.

**FR-PAY-5:** Admin must be able to see why a vendor is ineligible for COD assignments (current balance and required minimum must both be visible on the vendor record).

**FR-PAY-6:** Payment gateway credentials must be configurable by admin without a code change.

**FR-PAY-7:** For COD bookings, the vendor must confirm in-app that cash has been collected from the customer. This confirmation must occur as part of the job completion flow and is required before the booking can transition to Completed. Admin must be able to view and reconcile all COD cash collections from the admin panel.

---

### 5.4 Booking Lifecycle

**FR-LIFE-1:** A booking moves through the following statuses: Pending → Assigned → Accepted → In Progress → Awaiting Verification → Completed. It may also be Rejected or Cancelled at any pre-completion stage.

**FR-LIFE-2:** Vendors must be able to accept or reject an assigned booking. A rejection reason is required. Rejection must trigger reassignment to the next eligible vendor automatically.

**FR-LIFE-3:** To start a job, the vendor must upload a before-photo. To complete a job, the vendor must upload an after-photo. Neither step can be skipped.

**FR-LIFE-4:** Job completion must be verified by a one-time code (OTP) provided to the customer and entered by the vendor. Completion cannot occur without OTP confirmation.

**FR-LIFE-5:** Customers must be able to cancel a booking before completion. If the assigned vendor is near the customer's address at the time of cancellation, the customer must receive a warning before confirming cancellation.

**FR-LIFE-6:** Admin must be able to manually assign, reassign, or cancel any booking.

**FR-LIFE-7:** Customers must be able to rebook from a completed or cancelled booking with service details pre-filled.

---

### 5.5 Vendor Dispatch

**FR-DISP-1:** When a booking is created, the system must automatically offer it to the highest-priority eligible vendor.

**FR-DISP-2:** Vendor eligibility for dispatch requires: vendor is active and vendor is online. These conditions apply to all bookings regardless of payment method.

**FR-DISP-3:** For COD bookings, the vendor's security-bond balance must additionally be at or above the platform-configured minimum balance. Vendors below the minimum are excluded from COD dispatch but remain eligible for non-COD bookings if all other conditions are satisfied.

**FR-DISP-4:** Vendors must be ranked for dispatch by their tier priority, then by rating. Lower-number tiers are offered bookings first.

**FR-DISP-5:** If a vendor does not respond to a booking offer within a configurable timeout, the booking must be automatically moved to the next eligible vendor.

**FR-DISP-6:** If no eligible vendor is found, the booking must be flagged for admin intervention.

**FR-DISP-7:** Admin must be able to manually assign any eligible vendor to a booking. For COD bookings, the security-bond minimum-balance rule applies to manual assignments in the same way it applies to auto-dispatch. A vendor below the minimum cannot be manually assigned to a COD booking.

---

### 5.6 Vendor Security-Bond Wallet

**FR-WALL-1:** Each vendor must hold a prepaid security-bond balance on the platform. This balance is a deposit — it is not an earnings wallet and does not accumulate income from completed jobs.

**FR-WALL-2:** Vendors must be able to top up their security-bond balance from the vendor app.

**FR-WALL-3:** Admin must be able to top up a vendor's security-bond balance from the admin panel.

**FR-WALL-4:** Platform-initiated deductions from the security bond include: commission on booking completion, cancellation/rejection/no-show penalties (if enabled by admin), and manual adjustments applied by admin with a mandatory reason.

**FR-WALL-5:** Every deduction must be recorded individually with the type, amount, resulting balance, date, and a human-readable description. Vendors must be able to see their full transaction history.

**FR-WALL-6:** There is no vendor withdrawal from the security-bond wallet. This is a platform design decision.

**FR-WALL-7:** The minimum required security-bond balance must be configurable by admin as a single platform-wide value.

**FR-WALL-8:** Vendors must see their current balance, the minimum required balance, and a clear eligibility indicator (eligible / low balance) in the vendor app.

---

### 5.7 Vendor Earnings and Settlements

**FR-SETT-1:** Vendor earnings are separate from the security bond. Earnings represent the net amount owed to the vendor for completed jobs.

**FR-SETT-2:** Admin must be able to select a set of completed, unsettled bookings for a vendor and record a settlement payout.

**FR-SETT-3:** Each settlement must display the gross booking amount, the commission rate and amount, and the net vendor payout per booking.

**FR-SETT-4:** A settlement must be all-or-nothing: if any booking in the selection is ineligible (not completed, already settled), the entire settlement must be rejected.

**FR-SETT-5:** Once recorded, a settlement record is immutable. It cannot be edited or deleted.

---

### 5.8 Commission

**FR-COMM-1:** A platform commission must be deducted automatically when a booking is completed. Commission is deducted from the vendor's security-bond balance.

**FR-COMM-2:** The commission rate must be configurable at the platform level, with the ability to override it per service or per vendor.

**FR-COMM-3:** The most specific applicable commission rule must take precedence (service-level > vendor-level > global).

**FR-COMM-4:** Commission rules must support both percentage-of-booking-total and fixed-amount types.

---

### 5.9 AMC (Annual Maintenance Contracts)

**FR-AMC-1:** Admin must be able to create AMC plan templates per service, defining visit frequency, duration, price per visit, and discount.

**FR-AMC-2:** Customers must be able to purchase an AMC plan for a service. On purchase, a contract is created with a pre-generated visit schedule.

**FR-AMC-3:** AMC visits must be executed as regular bookings, including OTP-verified completion.

**FR-AMC-4:** Customers must be able to pause, resume, and cancel their AMC contracts. Pause/resume requests require admin approval.

**FR-AMC-5:** When an AMC contract is resumed after a pause, all future visit dates must shift forward by the duration of the pause.

**FR-AMC-6:** Customers must be able to see all their AMC contracts, the visit history, and the next scheduled visit.

---

### 5.10 Warranties

**FR-WAR-1:** Every completed booking must automatically generate a service warranty. The warranty period is configurable by admin (default: 30 days).

**FR-WAR-2:** Customers must be able to claim a warranty by uploading evidence (minimum 2 photos) and describing the issue.

**FR-WAR-3:** A warranty claim must create a rework booking at zero cost, assigned to the original vendor where possible.

**FR-WAR-4:** When the rework booking is completed, the warranty must be marked as resolved.

**FR-WAR-5:** Expired warranties cannot be claimed.

---

### 5.11 Loyalty Program

**FR-LOY-1:** Customers must earn loyalty points automatically on booking completion. The earning rate (points per ₹100 spent) is configurable by admin, with per-service overrides.

**FR-LOY-2:** Customers must be able to redeem loyalty points at checkout for a discount. The redemption rate (points to rupees) is configurable.

**FR-LOY-3:** Redemption must be gated by a configurable minimum points threshold. Customers below the threshold cannot redeem.

**FR-LOY-4:** The maximum discount from loyalty redemption per order must be capped as a configurable percentage of the order subtotal.

**FR-LOY-5:** Customers must be able to see their point balance, transaction history, and current earn/redeem rates.

---

### 5.12 Coupons

**FR-CPN-1:** Admin must be able to create coupons with: discount type (flat or percentage), discount value, maximum discount cap, minimum order amount, usage limit, validity window, and active/inactive status.

**FR-CPN-2:** Coupon application must validate all conditions (active, within validity window, minimum order met, usage limit not reached) before applying the discount.

**FR-CPN-3:** Coupon usage must be enforced accurately under concurrent bookings. Two simultaneous bookings using the same coupon must not both succeed if the usage limit would be exceeded.

---

### 5.13 Pricing Configuration

**FR-PRICE-1:** Every service must have a base price. Attribute selections at booking time may add or subtract from the base price.

**FR-PRICE-2:** Services may have a surge pricing override (amount or percentage added to subtotal). A global surge default applies when no service-level override exists.

**FR-PRICE-3:** Tax (e.g. GST) must be configurable globally with per-service override capability. Tax may be displayed as a separate line or silently included in the total.

**FR-PRICE-4:** All pricing rules — base price, attributes, surge, tax — must be configurable by admin without a code change.

---

### 5.14 Reviews and Q&A

**FR-REV-1:** Customers must be able to submit a review (service rating, vendor rating, optional text) after a booking is completed. One review per booking.

**FR-REV-2:** Reviews must be moderated by admin before appearing publicly.

**FR-REV-3:** Customers must be able to submit questions about a service. Admin answers questions in the admin panel. Only answered questions appear publicly.

**FR-REV-4:** Admin must be able to create static FAQs per service that appear alongside customer Q&A.

---

### 5.15 Vendor Subscriptions

**FR-SUB-1:** Admin must be able to create subscription plans for vendors, defining: billing period, price, and permissions (COD eligibility, priority dispatch, reduced commission).

**FR-SUB-2:** Vendors must be able to browse available plans and subscribe from the vendor app.

**FR-SUB-3:** Subscriptions must expire automatically when their period ends.

**FR-SUB-4:** Vendors must receive a reminder notification before their subscription expires.

**FR-SUB-5:** Subscription enforcement (COD and dispatch effects) is a platform setting that must be activatable by admin without a code change. It is currently disabled.

---

### 5.16 GPS and Cancellation Audit

**FR-GPS-1:** The vendor app must continuously report the vendor's location while a booking is in an active state.

**FR-GPS-2:** When a customer cancels a booking, the system must check whether the assigned vendor was near the customer's address at the time of cancellation.

**FR-GPS-3:** If the vendor was within the configured geofence radius, the customer must see a warning before confirming cancellation.

**FR-GPS-4:** Admin must be able to review all cancellations where the vendor was within the geofence, and mark each as a verified false cancellation, verified valid cancellation, or dismissed.

---

### 5.17 CMS and Content

**FR-CMS-1:** Admin must be able to manage all customer-facing landing page sections (hero, service grid, promotions, testimonials, etc.) from the admin panel, including order and publish/draft status.

**FR-CMS-2:** Admin must be able to create, publish, and unpublish blogs, static pages, and promotional banners.

**FR-CMS-3:** Admin must be able to configure SEO metadata (title, description, keywords, canonical URL, Open Graph) per service node.

**FR-CMS-4:** Admin must be able to manage URL redirects and robots.txt configuration from the admin panel.

---

### 5.18 Admin Operations

**FR-ADM-1:** Admin must be able to approve or suspend vendors, manage their profiles, serving areas, and KYC documents.

**FR-ADM-2:** Admin must be able to apply a manual penalty to a vendor's security-bond balance. A written reason is mandatory for every manual penalty.

**FR-ADM-3:** Admin must be able to assign and manage admin roles and permissions without a code change. Roles define what each admin can see and do in the admin panel.

**FR-ADM-4:** Admin must be able to manage vendor tiers and run a batch re-evaluation that reassigns vendors to tiers based on performance.

**FR-ADM-5:** Admin must be able to send an individual notification to any customer or vendor.

**FR-ADM-6:** Important administrative and financial actions must be individually logged. Logged actions include: manual wallet penalties, settlement approvals, vendor suspensions and reinstatements, and commission rule changes. Each log entry must record the acting admin, timestamp, action type, and relevant details. The audit log must be viewable by admins with the appropriate permission. Audit log entries are immutable.

---

## 6. Non-Functional Requirements

**NFR-1 Performance:** Service catalog browsing must load within 2 seconds. Slot availability must be computed and returned within 2 seconds. Booking dispatch must complete within 500ms under normal load.

**NFR-2 Reliability:** Commission deduction, warranty generation, and loyalty point award must be atomic with booking completion. They cannot be partially applied or skipped. Settlement batches are all-or-nothing — partial commits are not permitted.

**NFR-3 Availability:** The platform must maintain high availability for the customer booking flow and vendor dispatch flow. Planned downtime must be communicated and scheduled outside peak hours.

**NFR-4 Payment Security:** Online payment verification must be server-side. Client-side payment status cannot be trusted. Payment credentials must never be stored in application code.

**NFR-5 Data Consistency:** Pricing recorded on a booking at creation is immutable. Settlement records are immutable. Wallet transaction history is append-only and cannot be edited.

**NFR-6 Scalability:** Adding a new city, service category, commission rule, or pricing configuration must require only admin data entry — no code deployment.

**NFR-7 Audit Trail:** All wallet deductions must be individually recorded with type, amount, balance after, date, and reason. Manual penalties must additionally record the admin who applied them. Important administrative and financial actions must be individually logged with the acting admin, timestamp, action type, and relevant details. All audit log entries are append-only and cannot be edited or deleted.

**NFR-8 Accessibility:** The customer app must be usable in both English and the target regional languages (language list to be defined before launch).

---

## 7. User Flows and Use Cases

### 7.1 Customer Books a Service

1. Customer opens the app and browses or searches for a service.
2. Customer opens the service detail page, reads description, FAQs, reviews, and pricing.
3. Customer taps Book and authenticates if not already signed in.
4. Customer fills in service-specific attributes (e.g. "How many bedrooms?").
5. Customer selects or adds a delivery address.
6. Customer selects an available date and time slot.
7. Customer optionally applies a coupon code or redeems loyalty points.
8. Customer reviews the full price breakdown.
9. Customer selects payment method (online or COD) and confirms.
10. Customer receives a booking confirmation with a reference number.

### 7.2 Vendor Receives and Completes a Job

1. Vendor receives a booking offer notification.
2. Vendor views the booking detail (service, address, schedule, amount).
3. Vendor accepts the booking.
4. On the day of the job, vendor navigates to the customer's address.
5. Vendor taps Start Job and uploads a before-photo.
6. Vendor completes the job.
7. Vendor taps Complete and uploads an after-photo.
8. Vendor requests the OTP from the customer and enters it.
9. For COD bookings, vendor confirms in-app that cash has been collected.
10. Booking is marked Completed. Vendor's commission is deducted from security bond.

### 7.3 Customer Claims a Warranty

1. Customer opens My Bookings and selects a completed booking within the warranty period.
2. Customer taps Claim Warranty and uploads a minimum of 2 evidence photos.
3. Customer describes the issue (minimum 10 characters).
4. Customer submits the claim.
5. A rework booking is created at zero cost and dispatched to the original vendor.
6. Vendor completes the rework booking via the standard OTP completion flow.
7. Warranty status updates to Resolved.

### 7.4 Admin Processes a Vendor Settlement

1. Admin opens the vendor's profile in the admin panel.
2. Admin navigates to the settlement section and views all unsettled completed bookings.
3. Admin selects the bookings to include in the settlement batch.
4. Admin reviews the gross amounts, commission amounts, and net payouts per booking.
5. Admin confirms the settlement.
6. Settlement record is created. Selected bookings are marked as settled.

### 7.5 Vendor Tops Up Security Bond

1. Vendor opens the Wallet section in the vendor app.
2. Vendor views current balance, minimum required balance, and eligibility status.
3. Vendor selects a top-up amount and proceeds to payment.
4. On payment success, balance is updated immediately.
5. Top-up appears as a transaction in the wallet history.

### 7.6 Customer Purchases an AMC Plan

1. Customer opens a service that has AMC plans available.
2. Customer views available plans with visit frequency, duration, and price.
3. Customer selects a plan and confirms purchase.
4. An AMC contract is created. Visit schedule is generated.
5. Customer sees the contract in My AMC with all visit dates and current status.

### 7.7 Customer Cancels While Vendor Is Nearby

1. Customer opens an active booking and taps Cancel.
2. System checks whether the vendor is within the geofence radius.
3. If the vendor is nearby, the customer sees a warning: "Your vendor is near your location. Are you sure you want to cancel?"
4. Customer may cancel anyway or go back.
5. If cancelled: booking is marked Cancelled. A GPS audit record is created for admin review.
6. Admin reviews the audit record and marks it as verified or dismissed.

### 7.8 Admin Applies a Manual Penalty

1. Admin opens a vendor's wallet in the admin panel.
2. Admin selects Apply Manual Penalty.
3. Admin enters the penalty amount and writes a mandatory reason.
4. Admin confirms.
5. Penalty is deducted from the vendor's security-bond balance.
6. Deduction appears in vendor's transaction history with the reason.
7. Vendor receives a notification about the deduction.

---

## 8. Constraints and Assumptions

### 8.1 Business Constraints

- **Security bond is not an earnings wallet.** Vendors pre-fund a deposit. Platform fees are deducted from this deposit. There is no mechanism for vendors to withdraw from this balance.
- **COD is a global setting.** COD cannot be enabled or disabled per service, category, or location. It is available platform-wide. Vendor eligibility for COD assignments is governed solely by the security-bond minimum-balance rule.
- **Vendor earnings are settled manually.** There is no automated payout to vendors. All settlements are initiated by admin.
- **Commission is deducted from the security bond.** When a job is completed, the platform commission is deducted from the vendor's security-bond balance, not tracked as a separate receivable.

### 8.2 Operational Assumptions

- Admin actively monitors the dispatch dashboard and intervenes when bookings exhaust all eligible vendors.
- Vendors are responsible for maintaining their security-bond balance above the minimum to remain eligible for COD assignments. A vendor below the minimum can still receive non-COD bookings.
- COD cash collection is confirmed by the vendor within the app as part of the job completion flow. Admin reconciles COD cash collections through the admin panel.
- Warranty rework jobs are assigned to the original vendor where possible. If the original vendor is unavailable, admin assigns manually.

### 8.3 Technical Constraints (Without Implementation Detail)

- All three applications (customer, vendor, admin) share a single database. Changes to shared data (pricing, settings, catalog) take effect immediately across all apps.
- The customer-facing web app must be SEO-crawlable for service and location pages.
- Platform configuration (commission rates, minimum balance, surge settings, etc.) changes take effect immediately — there is no staging or scheduling of configuration changes.

### 8.4 Market Assumptions

- The primary market is urban India. All prices are in Indian Rupees (₹).
- GST is the applicable tax framework.
- The Razorpay payment gateway is the primary online payment processor.
- Customers are comfortable authenticating via mobile phone OTP.

---

## 9. Open Product Decisions

These questions cannot be resolved from existing product requirements and confirmed decisions. Each must be decided before the affected feature can be built or activated.

---

**OPD-7: Refund Policy and Process**
The platform collects payment but has no defined refund policy. Under what conditions can a customer receive a refund (cancellation window, service failure, warranty rejection)? Is a refund returned to the original payment method, or issued as platform credit? When a refund is approved, is the vendor's commission clawed back from their security bond?

---

**OPD-8: OTP Expiry**
The completion OTP has no expiry. Should it expire after a time limit (e.g. 30 minutes from when the vendor requests completion)? If it expires, what happens to the booking — does the vendor need to request a new OTP?

---

**OPD-11: Catalog V1 Deprecation**
The admin panel contains a legacy service catalog that predates the current catalog system. Should it be removed? Does any existing service data need to be migrated to the current catalog before the legacy system is decommissioned?

---

## 10. Acceptance Criteria

### 10.1 Booking Creation

- [ ] A customer can complete a booking (browse → attribute form → address → slot → payment) without leaving the flow.
- [ ] The price shown at checkout is identical to the price recorded on the booking record.
- [ ] A booking cannot be created for a service that is not available at the customer's location.
- [ ] A coupon that has reached its usage limit cannot be applied by a new customer.
- [ ] Two simultaneous bookings with the same coupon cannot both succeed if the limit is one remaining use.

### 10.2 Dispatch and Assignment

- [ ] A new booking is dispatched to the highest-priority eligible vendor automatically (online and active).
- [ ] A vendor below the minimum security-bond balance is excluded from COD booking dispatch, including manual admin assignments to COD bookings.
- [ ] A vendor below the minimum security-bond balance can still be dispatched to and manually assigned to non-COD bookings if they are online and active.
- [ ] A vendor rejection immediately triggers dispatch to the next eligible vendor without waiting for the timeout.
- [ ] If all eligible vendors have been exhausted, the booking is flagged for admin intervention.

### 10.3 OTP-Verified Completion

- [ ] A vendor cannot start a job without uploading a before-photo.
- [ ] A vendor cannot complete a job without uploading an after-photo.
- [ ] A booking cannot transition to Completed without a matching OTP.
- [ ] An incorrect OTP shows an error. The vendor may retry.
- [ ] Booking completion atomically deducts commission from security bond, generates a warranty, and awards loyalty points.

### 10.4 Security Bond Wallet

- [ ] Commission appears as a negative transaction in the vendor's wallet history after every booking completion.
- [ ] A penalty deduction only fires for vendor-triggered events (rejection, vendor cancellation, no-show). Customer or admin cancellations do not trigger a vendor penalty.
- [ ] Admin can top up a vendor's wallet. Balance updates immediately.
- [ ] No withdrawal option is visible or accessible to vendors in the app.
- [ ] Vendor can see their current balance, minimum required balance, and eligibility status at any time.

### 10.5 COD Eligibility

- [ ] A vendor with balance ≥ minimum can receive COD booking assignments.
- [ ] A vendor with balance < minimum cannot receive COD booking assignments, even if they are online and active.
- [ ] Admin can see a vendor's current balance and the minimum required balance when reviewing a vendor record.
- [ ] For a COD booking, the vendor cannot mark the job as Completed without first confirming cash collection within the app.
- [ ] Admin can view and reconcile all COD cash collection confirmations from the admin panel.

### 10.6 Settlements

- [ ] Admin can create a settlement batch from a vendor's completed, unsettled bookings.
- [ ] If any booking in the selection is invalid (not completed, already settled), the entire batch is rejected.
- [ ] Settlement records cannot be edited after creation.
- [ ] Settlement does not change the vendor's security-bond wallet balance.

### 10.7 AMC

- [ ] Purchasing an AMC plan creates a contract and generates all scheduled visit records immediately.
- [ ] AMC visits appear as standard bookings with AMC context visible to the vendor.
- [ ] Pausing a contract prevents future visits from being dispatched.
- [ ] Resuming after a pause shifts all future visit dates by the exact pause duration.

### 10.8 Warranties

- [ ] Every completed booking generates exactly one warranty — no duplicates.
- [ ] A warranty claim requires a minimum of 2 photos and a 10-character description.
- [ ] Claim submission creates a rework booking at zero cost.
- [ ] A warranty in Expired or Claimed status cannot be claimed again.

### 10.9 Loyalty

- [ ] Points are awarded to the customer automatically on booking completion.
- [ ] Points are not awarded on cancelled bookings.
- [ ] A customer cannot redeem more points than they hold.
- [ ] Loyalty redemption does not exceed the configured maximum percentage of the order subtotal.

### 10.10 GPS Audit

- [ ] A customer cancellation where the vendor was within the geofence creates a GPS audit record for admin review.
- [ ] A customer cancellation where the vendor was outside the geofence does not create an audit record.
- [ ] Admin can view, filter, and resolve GPS audit records.

### 10.11 Admin Configuration

- [ ] Changing the global commission rate takes effect on the next booking completion without a code deployment.
- [ ] Changing the minimum security-bond balance takes effect on the next booking assignment attempt without a code deployment.
- [ ] Adding a new admin role with specific permissions takes effect immediately for any admin user assigned that role.

### 10.12 Admin Audit Log

- [ ] Applying a manual penalty to a vendor's wallet creates an audit log entry recording the acting admin, timestamp, amount, and reason.
- [ ] Approving a settlement creates an audit log entry.
- [ ] Suspending or reinstating a vendor creates an audit log entry.
- [ ] Changing a commission rule creates an audit log entry.
- [ ] Audit log entries cannot be edited or deleted.
- [ ] An admin with the appropriate permission can view the audit log; admins without that permission cannot access it.

---

*End of DODO Booker PRD v1.0*

*This document defines what DODO Booker must do and why. It does not prescribe implementation. For technical architecture and database design, see MASTER_ARCHITECTURE.md and DATABASE_ARCHITECTURE.md. For confirmed product-owner decisions, see the Decision Log maintained by the product owner.*
