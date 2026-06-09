# DODO BOOKER — RBAC Architecture

> **Document Version:** 1.0  
> **Last Updated:** June 2026  
> **Scope:** Role-Based Access Control across Admin Panel, Vendor App, Customer App, and Supabase Backend

---

## Table of Contents

1. [Overview](#1-overview)
2. [RBAC Model](#2-rbac-model)
3. [Platform Roles](#3-platform-roles)
4. [Permissions](#4-permissions)
5. [Permission Groups](#5-permission-groups)
6. [Access Rules](#6-access-rules)
7. [Module Permissions](#7-module-permissions)
8. [Supabase RLS Strategy](#8-supabase-rls-strategy)
9. [Enforcement Architecture](#9-enforcement-architecture)
10. [Audit & Compliance](#10-audit--compliance)
11. [Dynamic RBAC Management](#11-dynamic-rbac-management)

---

## 1. Overview

DODO BOOKER implements a **multi-layered authorization model** that governs who can access what data and perform which actions across the platform. Authorization is not hardcoded — roles, permissions, and permission groups are **database-driven entities** managed through the Admin Panel.

### Design Goals

| Goal | Description |
|------|-------------|
| **Least privilege** | Every user receives only the permissions required for their function |
| **Defense in depth** | Authorization enforced at UI, API, and database layers |
| **Dynamic configurability** | New roles and permissions created without code deployment |
| **Tenant isolation** | Vendor data scoped to vendor organizations; customer data scoped to individuals |
| **Auditability** | All permission-sensitive actions logged with actor, action, and context |

### Platform Identity Types

The platform recognizes five identity types. Each maps to a distinct authentication flow, data scope, and authorization model:

| Identity Type | Application | Auth Method | Authorization Model |
|---------------|-------------|-------------|---------------------|
| **Super Admin** | Admin Panel | Email + Password | Full platform access (system role) |
| **Admin User** | Admin Panel | Email + Password | Role → Permission (configurable) |
| **Vendor Owner** | Vendor App | Mobile OTP / Password | Full vendor organization access |
| **Vendor Staff** | Vendor App | Mobile OTP / Password | Vendor Role → Vendor Permission (configurable) |
| **Customer** | Customer App / PWA | Mobile OTP | Binary access (public vs authenticated) |

---

## 2. RBAC Model

DODO BOOKER uses **two independent RBAC domains** that share the same Supabase backend but operate at different scopes:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PLATFORM RBAC (Admin Panel)                      │
│                                                                     │
│   Admin User ──→ Role(s) ──→ Permission(s) ──→ Module Actions    │
│                                                                     │
│   Scope: Entire platform (all vendors, customers, bookings)        │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    VENDOR RBAC (Vendor App)                         │
│                                                                     │
│   Vendor Staff ──→ Vendor Role ──→ Vendor Permission ──→ Actions │
│                                                                     │
│   Scope: Single vendor organization (own bookings, staff, earnings)│
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    CUSTOMER ACCESS (Customer App)                     │
│                                                                     │
│   Unauthenticated ──→ Public read access                         │
│   Authenticated   ──→ Own data only (no role/permission model)     │
│                                                                     │
│   Scope: Individual customer (own bookings, profile, payments)     │
└─────────────────────────────────────────────────────────────────────┘
```

### Authorization Chain

**Platform RBAC:**

```
Super Admin / Admin User
  └── has one or more → Roles
        └── each Role grants → Permissions
              └── each Permission authorizes → Module Action(s)
                    └── enforced by → UI Guard + API Guard + RLS Policy
```

**Vendor RBAC:**

```
Vendor Owner / Vendor Staff
  └── belongs to → Vendor Organization
        └── assigned → Vendor Role
              └── grants → Vendor Permission(s)
                    └── scoped to → vendor_id
                          └── enforced by → UI Guard + API Guard + RLS Policy
```

### Permission Naming Convention

All permissions follow a consistent dot-notation pattern:

```
{module}.{action}
```

| Segment | Description | Examples |
|---------|-------------|----------|
| `module` | The platform module or domain | `booking`, `vendor`, `seo`, `staff` |
| `action` | The operation being authorized | `view`, `create`, `update`, `delete`, `approve`, `process` |

Extended actions for complex operations:

| Action | Meaning |
|--------|---------|
| `view` | Read/list access |
| `create` | Create new records |
| `update` | Modify existing records |
| `delete` | Remove or archive records |
| `approve` | Approve pending items (vendors, refunds, documents) |
| `assign` | Assign resources (bookings to vendors, tickets to agents) |
| `process` | Execute workflows (refunds, settlements, payments) |
| `manage` | Full CRUD within a module (implies view + create + update + delete) |
| `export` | Export data (reports, CSV, PDF) |
| `configure` | Modify system settings and rules |

---

## 3. Platform Roles

### 3.1 Role Hierarchy Overview

```
Platform Level
├── Super Admin          (system role — immutable, full access)
└── Admin Users          (configurable roles)
    ├── Operations Manager
    ├── SEO Manager
    ├── Support Manager
    ├── Finance Manager
    └── Content Manager
    └── [Custom Roles]   (created dynamically via Admin Panel)

Vendor Level
├── Vendor Owner         (organization owner — full vendor access)
└── Vendor Staff         (configurable sub-roles)
    ├── Manager
    ├── Supervisor
    ├── Technician
    └── Worker
    └── [Custom Roles]   (created by Vendor Owner)

Customer Level
└── Customer             (no sub-roles — binary authenticated/unauthenticated)
```

---

### 3.2 Super Admin

| Attribute | Value |
|-----------|-------|
| **Identity Type** | Platform administrator |
| **Application** | Admin Panel |
| **Scope** | Entire platform — all data, all modules, all settings |
| **Assignable** | No — system role, not created via Admin Panel |
| **Cloneable** | No |
| **Deletable** | No |

**Characteristics:**

- Bypasses permission checks at the application layer (RLS still applies via service role or elevated policy)
- Manages all other admin users, roles, and permissions
- Only identity that can create, modify, or delete roles and permissions
- Only identity that can assign the Super Admin-equivalent capabilities to other users (if multi-super-admin is enabled)
- All actions logged with elevated audit priority

**Default Permissions:** All permissions across all permission groups (see Section 5).

---

### 3.3 Admin Users

| Attribute | Value |
|-----------|-------|
| **Identity Type** | Platform administrator |
| **Application** | Admin Panel |
| **Scope** | Platform-wide, limited by assigned role(s) |
| **Assignable** | Yes — created and managed by Super Admin or users with `rbac.manage` permission |
| **Multi-role** | Yes — an admin user can hold multiple roles simultaneously |

Admin Users are **not a single role** — they are a class of platform identities whose access is determined by dynamically assigned roles. The platform ships with predefined role templates that can be cloned and customized.

#### Predefined Admin Roles

| Role | Primary Responsibility | Key Modules |
|------|---------------------|-------------|
| **Operations Manager** | Day-to-day marketplace operations | Bookings, Vendors, Assignment, CRM, Locations |
| **SEO Manager** | Search visibility and content SEO | SEO, CMS, Sitemap, Redirects |
| **Support Manager** | Customer and vendor support | Tickets, Complaints, Refunds |
| **Finance Manager** | Financial operations | Payments, Invoices, Settlements, Sales, Refunds |
| **Content Manager** | Marketing and editorial content | CMS, Banners, Blogs, FAQs, Promotions |

#### Admin User Lifecycle

```
Created → Active → Deactivated → (optionally) Deleted
```

| State | Access |
|-------|--------|
| **Created** | No access until activated and roles assigned |
| **Active** | Access governed by assigned roles and permissions |
| **Deactivated** | Login blocked; sessions invalidated; data preserved |

#### Admin User Constraints

- Cannot access vendor-scoped internal data (staff RBAC config, internal vendor notes) unless permission explicitly grants it
- Cannot modify their own roles (prevents privilege escalation)
- Cannot deactivate their own account
- Session and login activity tracked in security logs

---

### 3.4 Vendor Owner

| Attribute | Value |
|-----------|-------|
| **Identity Type** | Vendor organization owner |
| **Application** | Vendor App |
| **Scope** | Single vendor organization (`vendor_id`) |
| **Assignable** | Created during vendor registration; ownership transferable by Admin |
| **Sub-roles** | No — Vendor Owner is the top role within a vendor organization |

**Characteristics:**

- Full access to all vendor organization data and operations
- Creates and manages Vendor Staff accounts
- Defines and assigns Vendor Roles and Vendor Permissions to staff
- Configures services, coverage, availability, and pricing (when permitted by platform)
- Manages bank details and settlement requests
- Cannot access other vendors' data
- Cannot modify platform-level configuration (categories, services, global settings)
- Subject to platform-level vendor lifecycle (Applied → Approved → Active → Suspended)

**Default Vendor Permissions:** All vendor-scoped permissions (see Section 4.2).

**Platform Override:** Admin Users with `vendor.manage` can suspend, approve, or modify vendor accounts regardless of Vendor Owner actions.

---

### 3.5 Vendor Staff

| Attribute | Value |
|-----------|-------|
| **Identity Type** | Vendor organization employee |
| **Application** | Vendor App |
| **Scope** | Single vendor organization (`vendor_id`), limited by assigned vendor role |
| **Assignable** | Yes — created by Vendor Owner or staff with `staff.manage` permission |
| **Multi-role** | No — one vendor role per staff member |

Vendor Staff are employees within a vendor organization. Their access is governed by **Vendor RBAC**, which is independent of platform RBAC.

#### Predefined Vendor Staff Roles

| Role | Primary Responsibility | Typical Permissions |
|------|---------------------|---------------------|
| **Manager** | Team and operations oversight | Staff management, revenue view, job assignment, booking accept/reject |
| **Supervisor** | Field team coordination | Job oversight, booking accept, work upload, status updates |
| **Technician** | Service execution | View assigned jobs, upload work images, complete service, OTP verification |
| **Worker** | Task execution (limited) | View assigned tasks only |

#### Vendor Staff Lifecycle

```
Created → Active → Deactivated
```

| State | Access |
|-------|--------|
| **Created** | No access until activated and vendor role assigned |
| **Active** | Access governed by vendor role within the organization |
| **Deactivated** | Login blocked; cannot be assigned new jobs |

#### Vendor Staff Constraints

- Cannot access earnings, settlements, or bank details unless role grants `earnings.view`
- Cannot create or modify other staff accounts unless role grants `staff.manage`
- Can only view and act on bookings assigned to them (unless role grants organization-wide booking access)
- Cannot modify vendor profile or KYC documents unless role grants `profile.manage`
- All actions scoped to their `vendor_id` — cross-vendor access is impossible

---

### 3.6 Customer

| Attribute | Value |
|-----------|-------|
| **Identity Type** | End customer |
| **Application** | Customer App / Customer Website (PWA) |
| **Scope** | Individual customer (`customer_id`) |
| **RBAC Model** | None — binary access model |

Customers do not have roles or permissions. Access is determined by authentication state:

#### Unauthenticated Access (Public)

| Allowed | Denied |
|---------|--------|
| Browse categories, sub categories, services, packages | Create or view bookings |
| Search and filter catalog | Access personal profile or addresses |
| View service details, reviews, ratings, FAQs | Make payments |
| View promotional banners and featured content | Submit reviews or feedback |
| View public CMS pages and blogs | Raise support tickets |
| View SEO landing pages | View booking history |

#### Authenticated Access (Customer)

| Allowed | Denied |
|---------|--------|
| All unauthenticated access | Access other customers' data |
| Create, view, and manage own bookings | Modify platform configuration |
| Manage own profile and addresses | Access vendor internal data |
| Make payments and view own invoices | Approve or manage vendors |
| Apply coupons and view own coupon history | View other customers' reviews |
| Submit reviews and ratings for own completed bookings | Access admin functions |
| Raise and track own support tickets | Modify service catalog |
| Request and track own refunds | View vendor earnings or settlements |
| View before/after gallery for own bookings | Manage vendor staff |
| Receive real-time booking updates | |
| Manage wishlist | |
| View own booking analytics | |

#### Customer Account States

| State | Access |
|-------|--------|
| **Active** | Full authenticated access |
| **Blocked** | Login blocked by Admin (via CRM module); existing sessions invalidated |
| **Incomplete Profile** | Can browse and authenticate but cannot place bookings until profile is complete |

---

## 4. Permissions

Permissions are atomic authorization units. They are stored in the database, grouped into permission groups, and assigned to roles. New permissions can be created dynamically through the Admin Panel.

### 4.1 Platform Permissions (Admin Panel)

#### RBAC & User Management

| Permission | Description |
|------------|-------------|
| `rbac.view` | View roles, permissions, and permission groups |
| `rbac.manage` | Create, update, delete, and clone roles |
| `rbac.assign` | Assign and revoke roles from admin users |
| `admin_user.view` | View admin user list and details |
| `admin_user.create` | Create new admin users |
| `admin_user.update` | Update admin user details |
| `admin_user.delete` | Deactivate or delete admin users |
| `audit.view` | View audit and activity logs |
| `security.view` | View login logs and session logs |

#### Service Management

| Permission | Description |
|------------|-------------|
| `category.view` | View categories and sub categories |
| `category.manage` | Create, update, delete, activate/deactivate categories |
| `service.view` | View services, packages, and add-ons |
| `service.manage` | Create, update, archive services, packages, and add-ons |
| `attribute.view` | View attribute groups, attributes, and values |
| `attribute.manage` | Create and configure dynamic attributes and values |
| `pricing.view` | View pricing slabs and pricing rules |
| `pricing.manage` | Create and configure pricing slabs and rules |

#### Vendor Management

| Permission | Description |
|------------|-------------|
| `vendor.view` | View vendor list, profiles, and performance |
| `vendor.approve` | Approve or reject vendor applications |
| `vendor.update` | Update vendor details and status |
| `vendor.suspend` | Suspend or reactivate vendor accounts |
| `vendor.document.verify` | Verify vendor KYC documents |
| `vendor.zone.manage` | Manage vendor zone and area mappings |

#### Booking Management

| Permission | Description |
|------------|-------------|
| `booking.view` | View booking list and details |
| `booking.create` | Create bookings on behalf of customers |
| `booking.update` | Update booking details |
| `booking.cancel` | Cancel bookings |
| `booking.reschedule` | Reschedule bookings |
| `booking.assign` | Manually assign vendors to bookings |

#### Assignment Engine

| Permission | Description |
|------------|-------------|
| `assignment.view` | View assignment rules and history |
| `assignment.manage` | Configure auto-assignment rules |
| `assignment.override` | Override auto-assignment with manual assignment |

#### CRM (Customer Management)

| Permission | Description |
|------------|-------------|
| `customer.view` | View customer profiles and history |
| `customer.update` | Edit customer profiles |
| `customer.block` | Block or activate customer accounts |
| `customer.tag.manage` | Manage customer tags |

#### Sales

| Permission | Description |
|------------|-------------|
| `quotation.view` | View quotations |
| `quotation.manage` | Create and update quotations |
| `sales_order.view` | View sales orders |
| `sales_order.manage` | Create and manage sales orders |
| `invoice.view` | View invoices |
| `invoice.create` | Generate invoices |
| `credit_note.manage` | Create credit and debit notes |

#### Payment Management

| Permission | Description |
|------------|-------------|
| `payment.view` | View payment records and status |
| `payment.record` | Record manual payments |
| `settlement.view` | View vendor settlement records |
| `settlement.process` | Process vendor settlements |

#### Coupon & Promotions

| Permission | Description |
|------------|-------------|
| `coupon.view` | View coupons and promotion campaigns |
| `coupon.manage` | Create and configure coupons |
| `promotion.manage` | Manage promotional campaigns and banners |

#### Ticket & Complaint Management

| Permission | Description |
|------------|-------------|
| `ticket.view` | View support tickets |
| `ticket.assign` | Assign tickets to support agents |
| `ticket.resolve` | Resolve and close tickets |
| `ticket.escalate` | Escalate tickets to higher levels |

#### Refund Management

| Permission | Description |
|------------|-------------|
| `refund.view` | View refund requests and status |
| `refund.approve` | Approve refund requests |
| `refund.process` | Process approved refunds |
| `refund.policy.manage` | Configure refund policies and rules |

#### SEO & CMS

| Permission | Description |
|------------|-------------|
| `seo.view` | View SEO metadata and schema |
| `seo.manage` | Edit SEO metadata, schema, sitemaps, robots.txt |
| `redirect.manage` | Manage URL redirects |
| `page.view` | View CMS pages |
| `page.manage` | Create and edit CMS pages, landing pages |
| `blog.manage` | Create, publish, and schedule blogs |
| `faq.manage` | Manage FAQs |
| `banner.manage` | Manage website, app, and promotional banners |

#### Notification

| Permission | Description |
|------------|-------------|
| `notification.view` | View notification templates and logs |
| `notification.manage` | Create and edit notification templates |
| `notification.automation.manage` | Configure notification automation rules |

#### Location Management

| Permission | Description |
|------------|-------------|
| `location.view` | View geographic hierarchy |
| `location.manage` | Create and manage countries, states, cities, zones, areas, pincodes |

#### Settings

| Permission | Description |
|------------|-------------|
| `settings.view` | View platform settings |
| `settings.manage` | Modify platform settings, commission, tax, booking rules |
| `commission.manage` | Configure vendor and platform commission rates |
| `tax.manage` | Configure GST and regional tax settings |

#### Analytics & Reporting

| Permission | Description |
|------------|-------------|
| `analytics.view` | View dashboard metrics |
| `report.view` | View reports |
| `report.export` | Export reports (PDF, Excel, CSV) |

---

### 4.2 Vendor Permissions (Vendor App)

Vendor permissions are scoped to a single `vendor_id`. They are managed by the Vendor Owner and stored separately from platform permissions.

#### Vendor Profile & KYC

| Permission | Description |
|------------|-------------|
| `profile.view` | View vendor profile and business details |
| `profile.manage` | Update vendor profile, business info, bank details |
| `kyc.view` | View KYC documents and verification status |
| `kyc.submit` | Submit KYC documents for verification |

#### Service Configuration

| Permission | Description |
|------------|-------------|
| `service.view` | Browse and view available platform services |
| `service.select` | Select and activate/deactivate offered services |
| `pricing.manage` | Configure service, add-on, and package pricing (when platform allows) |
| `coverage.manage` | Configure service coverage areas and radius |
| `availability.manage` | Configure working days, hours, holidays, and leave |

#### Booking Operations

| Permission | Description |
|------------|-------------|
| `booking.view` | View bookings assigned to the vendor organization |
| `booking.view.assigned` | View only bookings assigned to the staff member |
| `booking.accept` | Accept or reject assigned bookings |
| `booking.start` | Start service (upload before images) |
| `booking.complete` | Complete service (upload after images, OTP verification) |
| `booking.update_status` | Update booking status during service |

#### Work Proof

| Permission | Description |
|------------|-------------|
| `work.upload` | Upload before and after work images |
| `work.notes` | Add work notes to bookings |

#### Job Assignment (Internal)

| Permission | Description |
|------------|-------------|
| `job.assign` | Assign bookings to team members |
| `job.reassign` | Reassign bookings between team members |

#### Team Management

| Permission | Description |
|------------|-------------|
| `staff.view` | View team member list |
| `staff.manage` | Create, edit, and deactivate staff accounts |
| `staff.role.assign` | Assign vendor roles to staff members |

#### Financial

| Permission | Description |
|------------|-------------|
| `earnings.view` | View wallet balance, earnings, and transactions |
| `settlement.view` | View settlement history and pending settlements |
| `settlement.request` | Request withdrawals and settlements |

#### Feedback & Rating

| Permission | Description |
|------------|-------------|
| `feedback.view` | View customer ratings and reviews |
| `customer.rate` | Rate customers after service completion |

#### Support

| Permission | Description |
|------------|-------------|
| `ticket.view` | View own support tickets |
| `ticket.create` | Raise support tickets |

#### Analytics & Performance

| Permission | Description |
|------------|-------------|
| `analytics.view` | View vendor revenue, booking, and performance analytics |
| `performance.view` | View acceptance rate, response time, satisfaction scores |

#### Service Control

| Permission | Description |
|------------|-------------|
| `service.pause` | Temporarily pause account, services, or locations |
| `document.track` | View document expiry tracking and alerts |

---

### 4.3 Customer Capabilities (Not Permission-Based)

Customer capabilities are gated by authentication state and account status, not by a permission system. They are listed here for completeness in access rule definitions.

| Capability | Unauthenticated | Authenticated | Blocked |
|------------|:-----------------:|:-------------:|:-------:|
| Browse catalog | Yes | Yes | Yes |
| Search and filter | Yes | Yes | Yes |
| View reviews | Yes | Yes | Yes |
| Create booking | No | Yes | No |
| Make payment | No | Yes | No |
| View booking history | No | Own only | No |
| Manage profile | No | Own only | No |
| Manage addresses | No | Own only | No |
| Submit review | No | Own bookings | No |
| Apply coupon | No | Yes | No |
| Raise support ticket | No | Own only | No |
| Request refund | No | Own bookings | No |
| Real-time tracking | No | Own bookings | No |
| View invoice | No | Own only | No |
| Manage wishlist | No | Own only | No |

---

## 5. Permission Groups

Permission groups organize permissions into logical clusters for role assignment in the Admin Panel and Vendor App. Groups simplify the UI when creating or editing roles.

### 5.1 Platform Permission Groups

| Group | Permissions Included | Typical Roles |
|-------|---------------------|---------------|
| **Platform Administration** | `rbac.*`, `admin_user.*`, `audit.view`, `security.view` | Super Admin |
| **Service Catalog** | `category.*`, `service.*`, `attribute.*`, `pricing.*` | Operations Manager |
| **Vendor Operations** | `vendor.*`, `assignment.*` | Operations Manager |
| **Booking Operations** | `booking.*`, `assignment.view`, `assignment.override` | Operations Manager |
| **Customer Management** | `customer.*` | Operations Manager, Support Manager |
| **Financial Operations** | `payment.*`, `settlement.*`, `invoice.*`, `quotation.*`, `sales_order.*`, `credit_note.*` | Finance Manager |
| **Refund Operations** | `refund.*` | Finance Manager, Support Manager |
| **Support Operations** | `ticket.*` | Support Manager |
| **Marketing & Content** | `page.*`, `blog.*`, `faq.*`, `banner.*`, `coupon.*`, `promotion.*` | Content Manager |
| **SEO Operations** | `seo.*`, `redirect.*` | SEO Manager |
| **Notification Management** | `notification.*` | Operations Manager, Content Manager |
| **Location Management** | `location.*` | Operations Manager |
| **Platform Settings** | `settings.*`, `commission.*`, `tax.*` | Super Admin, Operations Manager |
| **Analytics & Reporting** | `analytics.*`, `report.*` | All admin roles (view); Finance Manager (export) |

### 5.2 Vendor Permission Groups

| Group | Permissions Included | Typical Roles |
|-------|---------------------|---------------|
| **Organization Management** | `profile.*`, `kyc.*`, `service.pause` | Vendor Owner |
| **Service Configuration** | `service.*`, `pricing.manage`, `coverage.manage`, `availability.manage` | Vendor Owner, Manager |
| **Booking Execution** | `booking.view`, `booking.accept`, `booking.start`, `booking.complete`, `booking.update_status` | Manager, Supervisor, Technician |
| **Assigned Jobs Only** | `booking.view.assigned`, `work.upload`, `work.notes`, `booking.complete` | Technician, Worker |
| **Job Assignment** | `job.assign`, `job.reassign` | Vendor Owner, Manager, Supervisor |
| **Team Management** | `staff.*` | Vendor Owner, Manager |
| **Financial Access** | `earnings.*`, `settlement.*` | Vendor Owner, Manager |
| **Customer Interaction** | `feedback.view`, `customer.rate` | Vendor Owner, Manager, Supervisor |
| **Support** | `ticket.*` | Vendor Owner, Manager |
| **Analytics** | `analytics.*`, `performance.*` | Vendor Owner, Manager |
| **Document Tracking** | `document.track`, `kyc.view` | Vendor Owner, Manager |

### 5.3 Predefined Role → Permission Group Mapping

#### Platform Roles

| Role | Permission Groups |
|------|-------------------|
| **Super Admin** | All groups |
| **Operations Manager** | Service Catalog, Vendor Operations, Booking Operations, Customer Management, Location Management, Notification Management, Analytics & Reporting |
| **SEO Manager** | SEO Operations, Analytics & Reporting (view only) |
| **Support Manager** | Customer Management, Support Operations, Refund Operations (view + approve), Booking Operations (view only), Analytics & Reporting (view only) |
| **Finance Manager** | Financial Operations, Refund Operations, Analytics & Reporting |
| **Content Manager** | Marketing & Content, Notification Management (view), SEO Operations (view) |

#### Vendor Roles

| Role | Permission Groups |
|------|-------------------|
| **Vendor Owner** | All vendor groups |
| **Manager** | Service Configuration, Booking Execution, Job Assignment, Team Management, Financial Access, Customer Interaction, Support, Analytics |
| **Supervisor** | Booking Execution, Job Assignment (assign only), Customer Interaction (view), Assigned Jobs + work upload |
| **Technician** | Assigned Jobs Only |
| **Worker** | `booking.view.assigned` only |

---

## 6. Access Rules

Access rules define the conditions under which an identity can read or write data. They apply across all applications and are enforced by RLS policies and application guards.

### 6.1 Global Access Rules

| Rule ID | Rule | Applies To |
|---------|------|------------|
| **G-01** | Every authenticated request must resolve to exactly one identity type | All |
| **G-02** | No identity can access data outside its defined scope | All |
| **G-03** | Deactivated or blocked identities cannot authenticate or perform actions | All |
| **G-04** | All write operations on permission-protected resources require explicit permission | Admin, Vendor |
| **G-05** | Public catalog data is readable without authentication | Customer (unauthenticated) |
| **G-06** | Pricing calculations are performed server-side; clients cannot bypass the pricing engine | All |
| **G-07** | Audit logs are append-only; no identity can modify or delete audit records | All |
| **G-08** | Role and permission definitions cannot be modified by identities lacking `rbac.manage` | Admin |

### 6.2 Super Admin Access Rules

| Rule ID | Rule |
|---------|------|
| **SA-01** | Super Admin has implicit access to all platform permissions |
| **SA-02** | Super Admin can view and manage all admin users, roles, and permissions |
| **SA-03** | Super Admin can view all vendor, customer, and booking data across the platform |
| **SA-04** | Super Admin can override vendor lifecycle states (approve, suspend, reactivate) |
| **SA-05** | Super Admin can process any financial operation (refunds, settlements, payments) |
| **SA-06** | Super Admin actions are logged with `actor_type: super_admin` in audit trail |
| **SA-07** | Super Admin cannot modify audit logs or delete audit records |
| **SA-08** | Super Admin cannot access vendor staff credentials or authentication tokens |

### 6.3 Admin User Access Rules

| Rule ID | Rule |
|---------|------|
| **AU-01** | Admin User access is the union of all permissions from all assigned roles |
| **AU-02** | Admin User can only access modules for which they hold at least one relevant permission |
| **AU-03** | Admin User cannot modify their own roles or permissions (privilege escalation prevention) |
| **AU-04** | Admin User cannot deactivate their own account |
| **AU-05** | Admin User with `booking.view` can view all bookings; without it, booking module is inaccessible |
| **AU-06** | Admin User with `vendor.approve` can change vendor lifecycle state; without it, vendor data is read-only |
| **AU-07** | Admin User with `refund.process` can execute refunds; `refund.view` alone is read-only |
| **AU-08** | Admin User with `customer.block` can block customers; `customer.view` alone cannot |
| **AU-09** | Admin User actions are scoped to platform-level data; admin users never receive vendor staff permissions |
| **AU-10** | Admin User sessions expire per platform security policy; re-authentication required |

### 6.4 Vendor Owner Access Rules

| Rule ID | Rule |
|---------|------|
| **VO-01** | Vendor Owner has all vendor permissions within their `vendor_id` |
| **VO-02** | Vendor Owner can create, edit, deactivate, and assign roles to Vendor Staff |
| **VO-03** | Vendor Owner can configure services, coverage, availability, and pricing (subject to platform rules) |
| **VO-04** | Vendor Owner can view all bookings assigned to their vendor organization |
| **VO-05** | Vendor Owner can assign bookings to any active staff member |
| **VO-06** | Vendor Owner can view earnings, wallet balance, and request settlements |
| **VO-07** | Vendor Owner cannot access other vendors' data, staff, or bookings |
| **VO-08** | Vendor Owner cannot modify platform catalog (categories, services, global pricing rules) |
| **VO-09** | Vendor Owner operations are blocked when vendor status is Suspended or not Approved |
| **VO-10** | Vendor Owner can pause their own account, services, or locations via `service.pause` |

### 6.5 Vendor Staff Access Rules

| Rule ID | Rule |
|---------|------|
| **VS-01** | Vendor Staff access is determined by their assigned vendor role within their `vendor_id` |
| **VS-02** | Vendor Staff can only access data belonging to their vendor organization |
| **VS-03** | Technician and Worker roles see only bookings assigned to them (via `booking.view.assigned`) |
| **VS-04** | Manager and Supervisor roles see all organization bookings (via `booking.view`) |
| **VS-05** | Staff without `earnings.view` cannot access wallet, settlement, or revenue data |
| **VS-06** | Staff without `staff.manage` cannot create or modify other staff accounts |
| **VS-07** | Staff without `job.assign` cannot reassign bookings to other team members |
| **VS-08** | Staff cannot modify vendor profile or bank details unless granted `profile.manage` |
| **VS-09** | Deactivated staff cannot log in or be assigned new bookings |
| **VS-10** | Staff actions on bookings are validated against booking status transitions |

### 6.6 Customer Access Rules

| Rule ID | Rule |
|---------|------|
| **CU-01** | Unauthenticated users can read public catalog, CMS, SEO, and promotional content |
| **CU-02** | Authenticated customers can only read and write their own profile, addresses, and bookings |
| **CU-03** | Customer cannot view other customers' personal data, bookings, or reviews |
| **CU-04** | Customer cannot modify service catalog, pricing, or platform settings |
| **CU-05** | Customer must complete profile before creating a booking |
| **CU-06** | Customer can only review and rate bookings they personally completed |
| **CU-07** | Customer can only request refunds for their own bookings |
| **CU-08** | Customer can only view invoices associated with their own payments |
| **CU-09** | Blocked customers cannot authenticate; active sessions are invalidated on block |
| **CU-10** | Customer booking data is visible to assigned vendor staff and admin users with `booking.view` |

### 6.7 Cross-Identity Access Rules

| Rule ID | Rule | Participants |
|---------|------|-------------|
| **X-01** | Customer booking details visible to assigned vendor (owner + relevant staff) | Customer ↔ Vendor |
| **X-02** | Customer contact info visible to assigned vendor only during active booking | Customer ↔ Vendor |
| **X-03** | Vendor work proof images visible to customer for their own bookings | Vendor → Customer |
| **X-04** | Admin with `booking.view` can see all bookings regardless of vendor or customer | Admin → All |
| **X-05** | Admin with `vendor.view` can see vendor profiles but not vendor staff passwords | Admin → Vendor |
| **X-06** | Vendor cannot see customer data beyond what is attached to their assigned bookings | Vendor → Customer |
| **X-07** | Support tickets are visible to the creator and admin users with `ticket.view` | Customer/Vendor ↔ Admin |
| **X-08** | Refund status visible to the requesting customer and admin users with `refund.view` | Customer ↔ Admin |

---

## 7. Module Permissions

This section maps each application module to the permissions required for access. A module may be visible in the UI only if the user holds at least the `view` permission for that module.

### 7.1 Admin Panel Module Permissions

| Module | View Permission | Manage Permission | Additional Permissions |
|--------|----------------|-------------------|----------------------|
| RBAC & User Management | `rbac.view`, `admin_user.view` | `rbac.manage`, `admin_user.create` | `rbac.assign`, `admin_user.update`, `admin_user.delete`, `audit.view`, `security.view` |
| Service Management | `category.view`, `service.view` | `category.manage`, `service.manage` | `attribute.view`, `attribute.manage` |
| Dynamic Attributes & Pricing | `attribute.view`, `pricing.view` | `attribute.manage`, `pricing.manage` | — |
| Vendor Management | `vendor.view` | `vendor.update` | `vendor.approve`, `vendor.suspend`, `vendor.document.verify`, `vendor.zone.manage` |
| Booking Management | `booking.view` | `booking.create`, `booking.update` | `booking.cancel`, `booking.reschedule` |
| Assignment Engine | `assignment.view` | `assignment.manage` | `assignment.override`, `booking.assign` |
| CRM | `customer.view` | `customer.update` | `customer.block`, `customer.tag.manage` |
| Sales | `quotation.view`, `invoice.view` | `quotation.manage`, `sales_order.manage` | `invoice.create`, `credit_note.manage` |
| Payment Management | `payment.view`, `settlement.view` | `payment.record` | `settlement.process` |
| Coupon & Promotions | `coupon.view` | `coupon.manage`, `promotion.manage` | — |
| Ticket & Complaint | `ticket.view` | `ticket.resolve` | `ticket.assign`, `ticket.escalate` |
| Refund Management | `refund.view` | `refund.policy.manage` | `refund.approve`, `refund.process` |
| SEO & CMS | `seo.view`, `page.view` | `seo.manage`, `page.manage` | `redirect.manage`, `blog.manage`, `faq.manage`, `banner.manage` |
| Notification | `notification.view` | `notification.manage` | `notification.automation.manage` |
| Location Management | `location.view` | `location.manage` | — |
| Settings | `settings.view` | `settings.manage` | `commission.manage`, `tax.manage` |
| Analytics & Reporting | `analytics.view`, `report.view` | — | `report.export` |
| Audit & Activity Logs | `audit.view` | — | — |

### 7.2 Vendor App Module Permissions

| Module | Required Permission(s) | Vendor Owner | Manager | Supervisor | Technician | Worker |
|--------|----------------------|:------------:|:-------:|:----------:|:----------:|:------:|
| Authentication | — (all active users) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Vendor Profile | `profile.view` / `profile.manage` | ✓ / ✓ | view | view | — | — |
| KYC & Documents | `kyc.view` / `kyc.submit` | ✓ / ✓ | view | — | — | — |
| Service Selection | `service.view` / `service.select` | ✓ / ✓ | ✓ | — | — | — |
| Service Pricing | `pricing.manage` | ✓ | ✓ | — | — | — |
| Service Coverage | `coverage.manage` | ✓ | ✓ | — | — | — |
| Availability | `availability.manage` | ✓ | ✓ | — | — | — |
| Dashboard | `booking.view` or `analytics.view` | ✓ | ✓ | ✓ | assigned | — |
| Booking Management | `booking.view` / `booking.accept` | ✓ / ✓ | ✓ / ✓ | ✓ / ✓ | assigned / ✓ | — |
| Job Details | `booking.view` or `booking.view.assigned` | ✓ | ✓ | ✓ | ✓ | ✓ |
| Work Proof | `work.upload` | ✓ | ✓ | ✓ | ✓ | — |
| OTP Verification | `booking.complete` | ✓ | ✓ | ✓ | ✓ | — |
| Wallet & Earnings | `earnings.view` | ✓ | ✓ | — | — | — |
| Settlement | `settlement.view` / `settlement.request` | ✓ / ✓ | view / — | — | — | — |
| Customer Feedback | `feedback.view` | ✓ | ✓ | ✓ | — | — |
| Customer Rating | `customer.rate` | ✓ | ✓ | ✓ | — | — |
| Team Management | `staff.view` / `staff.manage` | ✓ / ✓ | ✓ / ✓ | — | — | — |
| Staff RBAC | `staff.role.assign` | ✓ | — | — | — | — |
| Internal Job Assignment | `job.assign` | ✓ | ✓ | ✓ | — | — |
| Notification | — (all active users) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ticket Support | `ticket.view` / `ticket.create` | ✓ / ✓ | ✓ / ✓ | — | — |
| Document Expiry | `document.track` | ✓ | ✓ | — | — | — |
| Vendor Analytics | `analytics.view` | ✓ | ✓ | — | — | — |
| Vendor Performance | `performance.view` | ✓ | ✓ | — | — | — |
| Service Pause | `service.pause` | ✓ | — | — | — | — |

### 7.3 Customer App Module Access

| Module | Unauthenticated | Authenticated | Notes |
|--------|:---------------:|:-------------:|-------|
| Authentication | Signup/login only | Logout, change mobile | — |
| Customer Profile | — | Own profile only | Profile completion required for booking |
| Address Management | — | Own addresses only | — |
| Home | ✓ | ✓ | Dynamic content from Admin |
| Category | ✓ | ✓ | — |
| Service | ✓ | ✓ | — |
| Add-On | ✓ | ✓ | Selection requires auth at booking |
| Service Package | ✓ | ✓ | — |
| Search | ✓ | ✓ | — |
| Filter & Sorting | ✓ | ✓ | — |
| Booking | — | Own bookings only | Create requires complete profile |
| Advanced Scheduling | — | Own bookings only | — |
| Booking Tracking | — | Own bookings only | Realtime via Supabase |
| Real-Time Updates | — | Own bookings only | — |
| Payment | — | Own payments only | — |
| Coupon | View public | Apply to own bookings | — |
| Invoice | — | Own invoices only | — |
| Service Completion | — | Own bookings only | OTP verification |
| Review & Rating | — | Own completed bookings | — |
| Feedback | — | Own submissions | — |
| Booking History | — | Own history only | — |
| Rebooking | — | Own history only | — |
| Wishlist | — | Own wishlist only | — |
| Notification | — | Own notifications | — |
| Ticket Support | — | Own tickets only | — |
| Refund | — | Own bookings only | — |
| Before & After Gallery | — | Own bookings only | — |
| FAQ | ✓ | ✓ | — |
| Promotional Content | ✓ | ✓ | — |
| Customer Analytics | — | Own analytics only | — |

---

## 8. Supabase RLS Strategy

Row Level Security (RLS) is the **authoritative enforcement layer** for data access. Application-level guards provide UX convenience, but RLS ensures that even direct API access cannot bypass authorization.

### 8.1 RLS Design Principles

| Principle | Description |
|-----------|-------------|
| **RLS on every table** | All tables containing business data have RLS enabled; no exceptions |
| **Deny by default** | No policy = no access; policies must explicitly grant access |
| **Identity resolution in policies** | Policies resolve the current user's identity type and scope from JWT claims and profile tables |
| **Scope isolation** | Vendor data filtered by `vendor_id`; customer data filtered by `customer_id` |
| **Public read separation** | Catalog and CMS tables have explicit public-read policies for unauthenticated access |
| **Service role for system operations** | Edge Functions use the Supabase service role for system-level operations (assignment, pricing, notifications) |
| **No RLS bypass in clients** | Client applications never use the service role key |

### 8.2 Identity Resolution

When a request arrives at Supabase, the RLS policy resolves the caller's identity:

```
JWT Token (auth.uid())
  └── Lookup in identity profile table
        ├── admin_users     → identity_type: admin, roles[], permissions[]
        ├── vendors         → identity_type: vendor_owner, vendor_id
        ├── vendor_staff    → identity_type: vendor_staff, vendor_id, vendor_role, permissions[]
        └── customers       → identity_type: customer, customer_id
```

**JWT Custom Claims (set at login via Edge Function or database trigger):**

| Claim | Description | Set For |
|-------|-------------|---------|
| `identity_type` | `super_admin`, `admin`, `vendor_owner`, `vendor_staff`, `customer` | All |
| `vendor_id` | Vendor organization UUID | Vendor Owner, Vendor Staff |
| `customer_id` | Customer UUID | Customer |
| `staff_id` | Vendor staff record UUID | Vendor Staff |
| `is_active` | Account active status | All |

### 8.3 Policy Categories

RLS policies are organized into five categories based on data access patterns:

#### Category 1: Public Read

Tables with content accessible without authentication.

| Table Domain | Policy | Condition |
|-------------|--------|-----------|
| Categories, Sub Categories | `SELECT` | Always allowed for `is_active = true` records |
| Services, Packages, Add-ons | `SELECT` | Always allowed for `is_active = true` records |
| Attribute Groups, Attributes, Values | `SELECT` | Always allowed for active service attributes |
| Reviews (published) | `SELECT` | Always allowed for approved reviews |
| CMS Pages, Blogs, FAQs | `SELECT` | Always allowed for published content |
| Banners, Promotions | `SELECT` | Always allowed for active campaigns |
| SEO Metadata | `SELECT` | Always allowed |
| Locations (cities, zones) | `SELECT` | Always allowed for active locations |

**No `INSERT`, `UPDATE`, or `DELETE`** for unauthenticated or non-admin identities.

#### Category 2: Admin Full Access

Tables managed exclusively through the Admin Panel.

| Table Domain | Policy | Condition |
|-------------|--------|-----------|
| Roles, Permissions, Permission Groups | `ALL` | `identity_type` is `super_admin` OR admin has matching permission |
| Admin Users | `ALL` | `identity_type` is `super_admin` OR `admin_user.manage` permission |
| Platform Settings | `ALL` | `identity_type` is `super_admin` OR `settings.manage` permission |
| Audit Logs | `SELECT` | `identity_type` is `super_admin` OR `audit.view` permission |
| Audit Logs | `INSERT` | Service role only (system-generated) |
| Pricing Rules, Assignment Rules | `ALL` | Admin with `pricing.manage` or `assignment.manage` |
| Notification Templates | `ALL` | Admin with `notification.manage` |
| Coupon Definitions | `ALL` | Admin with `coupon.manage` |

**Admin write policies** validate the specific permission for the operation (e.g., `vendor.approve` required to update vendor status to "Approved").

#### Category 3: Customer Self-Access

Tables where customers access only their own records.

| Table Domain | `SELECT` Policy | `INSERT` Policy | `UPDATE` Policy |
|-------------|----------------|----------------|----------------|
| Customer Profiles | `customer_id = auth customer_id` | On signup (own record) | Own record only |
| Customer Addresses | `customer_id = auth customer_id` | Own `customer_id` | Own records only |
| Bookings | `customer_id = auth customer_id` | Own `customer_id`, profile complete | Own bookings, limited status changes (cancel) |
| Booking Attributes | Via booking ownership | Via booking ownership | — |
| Payments | `customer_id = auth customer_id` | Own `customer_id` | — |
| Invoices | Via booking/payment ownership | — | — |
| Reviews | `customer_id = auth customer_id` | Own completed bookings | Own reviews only |
| Support Tickets | `customer_id = auth customer_id` | Own `customer_id` | Own open tickets only |
| Refund Requests | `customer_id = auth customer_id` | Own bookings | — |
| Wishlists | `customer_id = auth customer_id` | Own `customer_id` | Own records only |
| Notifications | `customer_id = auth customer_id` | — | Mark as read only |

**Blocked customers:** Policies check `is_active = true` on the customer profile; blocked customers fail all authenticated policies.

#### Category 4: Vendor Organization Scope

Tables where vendor identities access data within their `vendor_id`.

| Table Domain | Vendor Owner | Vendor Staff | Policy Condition |
|-------------|:------------:|:------------:|-----------------|
| Vendor Profile | R/W | Read (if `profile.view`) | `vendor_id = auth vendor_id` |
| Vendor KYC Documents | R/W | Read (if `kyc.view`) | `vendor_id = auth vendor_id` |
| Vendor Services (selection) | R/W | — | `vendor_id = auth vendor_id` |
| Vendor Pricing | R/W | — (if `pricing.manage`) | `vendor_id = auth vendor_id` |
| Vendor Coverage | R/W | — | `vendor_id = auth vendor_id` |
| Vendor Availability | R/W | — | `vendor_id = auth vendor_id` |
| Bookings (org-wide) | R/W | Read (if `booking.view`) | `vendor_id = auth vendor_id` |
| Bookings (assigned) | R/W | R/W (if assigned) | `assigned_staff_id = auth staff_id` |
| Work Proof Images | R/W | Write (if `work.upload`) | Via booking `vendor_id` or `assigned_staff_id` |
| Vendor Staff | R/W | — (if `staff.manage`) | `vendor_id = auth vendor_id` |
| Vendor Roles & Permissions | R/W | — | `vendor_id = auth vendor_id` |
| Wallet & Transactions | R/W | Read (if `earnings.view`) | `vendor_id = auth vendor_id` |
| Settlements | R/W | Read (if `settlement.view`) | `vendor_id = auth vendor_id` |
| Vendor Tickets | R/W | R/W (if `ticket.create`) | `vendor_id = auth vendor_id` |
| Vendor Notifications | R | R | `vendor_id = auth vendor_id` OR `staff_id = auth staff_id` |

**Suspended vendors:** Policies check vendor status is `active`; suspended vendors fail all write policies and most read policies.

#### Category 5: Cross-Entity Access

Tables accessed by multiple identity types with different scopes.

| Table Domain | Customer | Vendor | Admin | Policy Logic |
|-------------|:--------:|:------:|:-----:|-------------|
| Bookings | Own (`customer_id`) | Assigned (`vendor_id` or `assigned_staff_id`) | All (`booking.view`) | Composite OR policy |
| Booking Status History | Own bookings | Assigned bookings | All (`booking.view`) | Via booking ownership chain |
| Reviews | Own + public read | Own vendor reviews (`feedback.view`) | All (`customer.view`) | Composite policy |
| Support Tickets | Own tickets | Own vendor tickets | All (`ticket.view`) | `creator_id` + `creator_type` match |
| Payments | Own payments | Own vendor settlements | All (`payment.view`) | Role-based column filtering |
| Notifications | Own | Own (vendor or staff) | — | `recipient_id` + `recipient_type` match |

### 8.4 Storage Bucket Policies

Supabase Storage buckets follow the same identity-scoped strategy:

| Bucket | Read Access | Write Access | Notes |
|--------|------------|-------------|-------|
| `profile-images` | Own profile image; admin (`customer.view` / `vendor.view`) | Own profile only | Customer, vendor, admin avatars |
| `kyc-documents` | Own vendor; admin (`vendor.document.verify`) | Own vendor (during submission) | Sensitive — no public access |
| `work-proofs` | Booking customer; assigned vendor staff; admin (`booking.view`) | Assigned vendor staff (`work.upload`) | Before/after service images |
| `invoices` | Own customer; admin (`invoice.view`) | Service role only (system-generated) | PDF invoices |
| `cms-media` | Public read | Admin (`banner.manage`, `blog.manage`) | Banners, blog images |
| `service-images` | Public read | Admin (`service.manage`) | Service catalog images |

### 8.5 Edge Function Authorization

Edge Functions handle operations too complex for simple RLS policies. They follow a separate authorization pattern:

| Function | Authorization Check | Identity |
|----------|-------------------|----------|
| **Pricing Engine** | Authenticated customer or admin | Customer (own booking), Admin (`pricing.view`) |
| **Assignment Engine** | Service role (system-triggered) or admin (`assignment.manage`) | System, Admin |
| **Notification Dispatcher** | Service role (system-triggered) | System |
| **OTP Generator** | Service role (system-triggered) | System |
| **Payment Webhook** | Service role (external webhook) | System |
| **Permission Resolver** | Authenticated user (own permissions) | All identities |
| **Refund Processor** | Admin (`refund.process`) | Admin |

**Edge Function authorization flow:**

```
Request → Validate JWT → Resolve identity_type → Check permission → Execute → Audit log
```

### 8.6 RLS Policy Implementation Strategy

Policies are organized in the `supabase/policies/` directory, grouped by identity type:

```
supabase/policies/
├── public_read_policies.sql       # Category 1: unauthenticated catalog access
├── admin_policies.sql             # Category 2: admin-scoped write access
├── customer_policies.sql          # Category 3: customer self-access
├── vendor_policies.sql            # Category 4: vendor organization scope
├── cross_entity_policies.sql      # Category 5: multi-identity tables
└── storage_policies.sql           # Storage bucket access
```

**Policy naming convention:**

```
{table_name}_{identity_type}_{operation}
```

Examples: `bookings_customer_select`, `bookings_vendor_update`, `bookings_admin_select`, `services_public_select`

### 8.7 Permission Check Helper (Database Level)

A database-level helper function resolves whether the current authenticated user holds a specific permission. This function is used inside RLS policies for admin and vendor staff authorization:

```
has_permission(permission_key) → boolean
```

**Resolution logic:**

| Identity Type | Resolution |
|---------------|------------|
| `super_admin` | Always returns `true` |
| `admin` | Check `admin_user_roles` → `role_permissions` → `permissions` |
| `vendor_owner` | Always returns `true` for vendor-scoped permissions |
| `vendor_staff` | Check `vendor_staff_roles` → `vendor_role_permissions` → `vendor_permissions` |
| `customer` | Not applicable — customers do not use permission checks |

### 8.8 Realtime Channel Authorization

Supabase Realtime channels are authorized per subscription:

| Channel Pattern | Subscribers | Authorization |
|----------------|-------------|---------------|
| `booking:{booking_id}` | Customer (owner), Vendor (assigned), Admin (`booking.view`) | Verify ownership via RLS before subscription |
| `vendor:{vendor_id}` | Vendor Owner, Vendor Staff | `vendor_id` match |
| `customer:{customer_id}` | Customer (owner) | `customer_id` match |
| `notifications:{recipient_id}` | Notification owner | `recipient_id` + `recipient_type` match |

Clients subscribe only to channels they are authorized to receive. Unauthorized subscription attempts are rejected.

---

## 9. Enforcement Architecture

Authorization is enforced at three layers. Each layer serves a distinct purpose; none is optional.

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 1: UI Guards (Presentation)                          │
│                                                              │
│  Purpose: User experience — hide/disable unauthorized actions│
│  Implementation: Permission checks before rendering UI       │
│  Bypass risk: High (client-side only)                        │
│  Required: Yes — prevents user confusion                     │
├──────────────────────────────────────────────────────────────┤
│  Layer 2: API / Client Guards (Application)                  │
│                                                              │
│  Purpose: Block unauthorized requests before they reach DB   │
│  Implementation: Permission checks in repositories/services  │
│  Bypass risk: Medium (determined client can skip)            │
│  Required: Yes — reduces unnecessary database load           │
├──────────────────────────────────────────────────────────────┤
│  Layer 3: RLS Policies (Database)                          │
│                                                              │
│  Purpose: Authoritative enforcement — cannot be bypassed    │
│  Implementation: PostgreSQL Row Level Security policies      │
│  Bypass risk: None (enforced by database engine)             │
│  Required: Yes — security guarantee                          │
└──────────────────────────────────────────────────────────────┘
```

### 9.1 UI Guard Behavior

| Scenario | UI Behavior |
|----------|-------------|
| User lacks `view` permission for a module | Module hidden from navigation |
| User has `view` but not `manage` | Module visible; create/edit/delete buttons hidden |
| User has `view` but not `approve` | Module visible; approve/reject buttons hidden |
| User has partial permissions within a module | Only authorized actions rendered |
| Permission check is loading | Module visible with skeleton/loading state |
| Permission check fails (network error) | Module hidden (fail-closed) |

### 9.2 Fail-Closed Principle

At every layer, authorization defaults to **deny**:

- Missing permission → action denied
- Unknown identity type → all access denied
- Deactivated account → login and all operations denied
- RLS policy evaluation error → query returns empty result
- Edge Function permission check failure → HTTP 403 response

---

## 10. Audit & Compliance

### 10.1 Audited Actions

All actions involving permission-protected operations are logged:

| Category | Actions Logged |
|----------|---------------|
| **RBAC Changes** | Role created/updated/deleted, permission assigned/revoked, admin user created/deactivated |
| **Vendor Lifecycle** | Vendor approved, suspended, reactivated, document verified/rejected |
| **Booking Operations** | Booking created, assigned, cancelled, rescheduled, status changed |
| **Financial** | Payment recorded, refund approved/processed, settlement processed |
| **Configuration** | Service updated, pricing changed, settings modified |
| **Customer Management** | Customer blocked, activated, profile modified by admin |
| **Vendor Staff** | Staff created, role changed, deactivated |

### 10.2 Audit Log Schema

| Field | Description |
|-------|-------------|
| `id` | Unique log entry ID |
| `actor_id` | UUID of the user who performed the action |
| `actor_type` | `super_admin`, `admin`, `vendor_owner`, `vendor_staff`, `system` |
| `action` | Action identifier (e.g., `vendor.approve`, `refund.process`) |
| `module` | Module where the action occurred |
| `entity_type` | Type of entity affected (e.g., `booking`, `vendor`, `role`) |
| `entity_id` | UUID of the affected entity |
| `changes` | JSON diff of before/after values |
| `ip_address` | IP address of the actor |
| `user_agent` | Client user agent string |
| `timestamp` | UTC timestamp of the action |

### 10.3 Security Logs

Separate from audit logs, security logs track authentication events:

| Event | Logged Fields |
|-------|---------------|
| Login success | User ID, identity type, IP, timestamp, device |
| Login failure | Attempted identity, IP, timestamp, failure reason |
| Session created | Session ID, user ID, IP, timestamp |
| Session expired | Session ID, user ID, timestamp |
| Password changed | User ID, timestamp, IP |
| Account deactivated | User ID, deactivated by, timestamp |

---

## 11. Dynamic RBAC Management

### 11.1 Admin Panel RBAC Management

The RBAC & User Management module in the Admin Panel provides full lifecycle management:

| Operation | Permission Required | Performed By |
|-----------|-------------------|-------------|
| Create role | `rbac.manage` | Super Admin, authorized Admin User |
| Clone role | `rbac.manage` | Super Admin, authorized Admin User |
| Update role permissions | `rbac.manage` | Super Admin, authorized Admin User |
| Delete role | `rbac.manage` | Super Admin (roles with assigned users cannot be deleted) |
| Create permission | `rbac.manage` | Super Admin |
| Group permissions | `rbac.manage` | Super Admin, authorized Admin User |
| Create admin user | `admin_user.create` | Super Admin, authorized Admin User |
| Assign role to admin user | `rbac.assign` | Super Admin, authorized Admin User |
| Deactivate admin user | `admin_user.delete` | Super Admin, authorized Admin User |

### 11.2 Vendor RBAC Management

Vendor RBAC is managed within the Vendor App by the Vendor Owner:

| Operation | Permission Required | Performed By |
|-----------|-------------------|-------------|
| Create vendor role | `staff.role.assign` | Vendor Owner |
| Assign permissions to vendor role | `staff.role.assign` | Vendor Owner |
| Create staff account | `staff.manage` | Vendor Owner, Manager (if granted) |
| Assign role to staff | `staff.role.assign` | Vendor Owner |
| Deactivate staff | `staff.manage` | Vendor Owner, Manager (if granted) |

### 11.3 Permission Registration

When new modules are added to the platform, corresponding permissions must be registered:

1. Define new permissions following the `{module}.{action}` convention
2. Assign permissions to appropriate permission groups
3. Update predefined role templates (optional — existing roles unaffected)
4. Create RLS policies for new tables
5. Add UI guards in the relevant application module

This process ensures RBAC remains synchronized with platform feature growth.

---

## Appendix A — Role-Permission Quick Reference

### Platform Roles at a Glance

| Capability | Super Admin | Operations Manager | SEO Manager | Support Manager | Finance Manager | Content Manager |
|------------|:-----------:|:------------------:|:-----------:|:---------------:|:---------------:|:---------------:|
| Manage roles/permissions | ✓ | — | — | — | — | — |
| Manage services/catalog | ✓ | ✓ | — | — | — | — |
| Manage vendors | ✓ | ✓ | — | — | — | — |
| Manage bookings | ✓ | ✓ | view | view | — | — |
| Manage customers | ✓ | ✓ | — | ✓ | — | — |
| Manage payments/settlements | ✓ | — | — | — | ✓ | — |
| Process refunds | ✓ | — | — | ✓ | ✓ | — |
| Manage tickets | ✓ | — | — | ✓ | — | — |
| Manage SEO | ✓ | — | ✓ | — | — | — |
| Manage content/CMS | ✓ | — | — | — | — | ✓ |
| Manage settings | ✓ | view | — | — | — | — |
| View analytics | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Export reports | ✓ | — | — | — | ✓ | — |

### Vendor Roles at a Glance

| Capability | Vendor Owner | Manager | Supervisor | Technician | Worker |
|------------|:------------:|:-------:|:----------:|:----------:|:------:|
| Manage profile/KYC | ✓ | view | — | — | — |
| Configure services/pricing | ✓ | ✓ | — | — | — |
| View all org bookings | ✓ | ✓ | ✓ | — | — |
| View assigned bookings | ✓ | ✓ | ✓ | ✓ | ✓ |
| Accept/reject bookings | ✓ | ✓ | ✓ | ✓ | — |
| Complete service (OTP) | ✓ | ✓ | ✓ | ✓ | — |
| Upload work proof | ✓ | ✓ | ✓ | ✓ | — |
| Assign jobs to staff | ✓ | ✓ | ✓ | — | — |
| Manage staff | ✓ | ✓ | — | — | — |
| View earnings/settlements | ✓ | ✓ | — | — | — |
| View analytics | ✓ | ✓ | — | — | — |
| Rate customers | ✓ | ✓ | ✓ | — | — |
| Raise support tickets | ✓ | ✓ | — | — | — |
| Pause services/account | ✓ | — | — | — | — |

---

## Appendix B — Related Documents

| Document | Purpose |
|----------|---------|
| [MASTER_ARCHITECTURE.md](./MASTER_ARCHITECTURE.md) | Platform-wide architecture and development order |
| [ADMIN_PANEL.md](./ADMIN_PANEL.md) | Admin Panel module specifications |
| [VENDOR_APP.md](./VENDOR_APP.md) | Vendor App module specifications |
| [CUSTOMER_APP.md](./CUSTOMER_APP.md) | Customer App module specifications |
| [DATABASE_ARCHITECTURE.md](./DATABASE_ARCHITECTURE.md) | Database schema and entity relationships |
| [MODULE_DEPENDENCIES.md](./MODULE_DEPENDENCIES.md) | Inter-module dependency graph |

---

*This document is the authoritative reference for DODO BOOKER authorization. All applications, RLS policies, and permission definitions must align with the roles, permissions, access rules, and enforcement strategy defined herein.*
