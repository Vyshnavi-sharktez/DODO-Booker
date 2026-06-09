# DODO BOOKER - MODULE DEPENDENCIES

## Purpose

This document defines module dependencies and development order.

---

# Core Dependency Flow

RBAC
↓
Admin Authentication
↓
Admin User Management

Location Management
↓
Category Management
↓
Sub Category Management
↓
Service Management
↓
Dynamic Service Attributes
↓
Dynamic Pricing Engine
↓
Booking Engine

---

# Admin Panel Dependencies

RBAC
↓
Admin Users
↓
Location Management
↓
Service Catalog
↓
Vendor Management
↓
Booking Management
↓
CRM
↓
Payments
↓
Reports

---

# Vendor App Dependencies

Vendor Authentication
↓
Vendor Profile
↓
Document Verification
↓
Service Management
↓
Booking Management
↓
Wallet
↓
Reviews

---

# Customer App Dependencies

Customer Authentication
↓
Customer Profile
↓
Browse Services
↓
Booking Engine
↓
Payments
↓
Reviews

---

# Payment Dependencies

Bookings
↓
Invoices
↓
Payments
↓
Vendor Settlements
↓
Wallets

---

# SEO Dependencies

Categories
↓
Sub Categories
↓
Services
↓
CMS
↓
SEO

---

# Critical Path

1. RBAC
2. Authentication
3. Locations
4. Categories
5. Sub Categories
6. Services
7. Dynamic Attributes
8. Pricing Engine
9. Vendor Management
10. Booking Engine
11. Payments
12. Notifications

---

# Independent Modules

These can be developed later:

* CMS
* SEO
* Analytics
* Reports
* Audit Logs
* Automation Engine

---

# Final Build Order

RBAC
→ Authentication
→ Locations
→ Categories
→ Services
→ Attributes
→ Pricing
→ Vendors
→ Bookings
→ Payments
→ Notifications
→ CMS
→ SEO
→ Analytics
