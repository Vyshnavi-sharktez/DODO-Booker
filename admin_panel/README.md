# admin_panel

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
# DODO BOOKER - ADMIN PANEL

## Overview

The Admin Panel is the central management system of the DODO BOOKER platform.

The platform consists of:

* Customer Application
* Vendor Application
* Admin Panel

The Admin Panel is responsible for managing all platform operations, users, services, bookings, vendors, payments, SEO, content, analytics, and system settings.

The entire system must be:

* Dynamic
* Modular
* RBAC-Based
* Scalable
* SEO-Friendly
* PWA Enabled

No business data should be hardcoded. All entities must be manageable through the Admin Panel.

---

# Core Architecture Principles

## Dynamic Architecture

All business entities must be created and managed dynamically.

Examples:

* Categories
* Sub Categories
* Services
* Service Packages
* Add-ons
* Coupons
* Cities
* Zones
* Roles
* Permissions
* Pages
* SEO Data
* Notification Templates

No developer intervention should be required for routine business operations.

---

## Modular Architecture

The Admin Panel must be organized into independent modules.

Each module should function independently and communicate through defined interfaces.

Examples:

* RBAC Module
* Service Module
* Vendor Module
* Booking Module
* CRM Module
* SEO Module
* Notification Module
* Analytics Module

---

## RBAC (Role-Based Access Control)

The entire application must be permission-driven.

Access must be controlled using:

Users → Roles → Permissions

Example Roles:

* Super Admin
* Operations Manager
* SEO Manager
* Support Manager
* Finance Manager
* Content Manager

Permissions must be configurable dynamically.

Examples:

* booking.view
* booking.assign
* vendor.approve
* seo.manage
* invoice.create
* refund.process

---

# MODULES

---

# 1. RBAC & User Management Module

## Features

### Role Management

* Create Roles
* Update Roles
* Delete Roles
* Clone Roles

### Permission Management

* Create Permissions
* Assign Permissions
* Group Permissions

### Admin User Management

* Create Admin Users
* Assign Roles
* Activate Users
* Deactivate Users

### Security Features

* Login Logs
* Session Logs
* Audit Logs
* Password Policies
* Two-Factor Authentication (Future)

---

# 2. Service Management Module

## Category Management

* Create Categories
* Edit Categories
* Delete Categories
* Activate/Deactivate Categories

## Sub Category Management

* Dynamic Sub Categories
* Category Mapping

## Service Management

* Create Services
* Edit Services
* Archive Services

## Service Attributes

Dynamic Service Fields

Examples:

AC Service

* Brand
* Capacity
* Type

Cleaning Service

* Property Size
* Number Of Rooms

Salon Service

* Gender
* Duration

## Service Packages

* Create Packages
* Bundle Services
* Package Pricing

## Add-On Management

Examples:

* Deep Cleaning
* Gas Refill
* Premium Products

# 2A. Dynamic Service Attributes & Pricing Engine Module

## Overview

The platform must support completely dynamic service configuration and pricing.

No service-specific forms, fields, or pricing logic should be hardcoded.

The Admin must be able to configure service structures, booking forms, attributes, options, and pricing rules dynamically.

---

## Service Hierarchy

Category
→ Sub Category
→ Service
→ Attribute Groups
→ Attributes
→ Pricing Rules

---

## Attribute Group Management

Admin can create Attribute Groups.

Examples:

### Cleaning Attributes

* Property Type
* Square Feet
* Number Of Rooms
* Number Of Bathrooms

### AC Service Attributes

* AC Type
* Brand
* Ton Capacity

### Salon Attributes

* Gender
* Duration
* Package Type

---

## Dynamic Attribute Management

Admin can create unlimited attributes.

Supported Types:

* Dropdown
* Radio Button
* Checkbox
* Number
* Text
* Date
* Multi Select

---

## Dynamic Attribute Values

Example:

Property Type

Values:

* Furnished
* Unfurnished

Square Feet

Values:

* 500 sqft
* 1000 sqft
* 1500 sqft
* 2000 sqft

---

## Dynamic Booking Form Builder

Booking forms must be generated dynamically based on configured attributes.

Examples:

Home Cleaning:

* Property Type
* Square Feet

Bathroom Cleaning:

* Number Of Bathrooms

AC Repair:

* AC Type
* Brand
* Ton Capacity

No hardcoded forms should exist.

---

## Dynamic Pricing Slabs

Pricing must support attribute-based calculations.

Example:

Property Type = Furnished
Square Feet = 500

Price = ₹999

---

Property Type = Furnished
Square Feet = 1000

Price = ₹1499

---

Property Type = Unfurnished
Square Feet = 500

Price = ₹799

---

## Pricing Components

Admin can configure:

* Base Price
* Attribute-Based Price
* Add-On Charges
* Distance Charges
* Time-Based Charges
* Surge Pricing
* Taxes
* Convenience Fees

---

## Pricing Rule Engine

Admin can create dynamic rules.

Example:

IF

Property Type = Furnished

AND

Square Feet > 1000

THEN

Add ₹500

---

## Dynamic Service Builder

Admin can:

* Create Service
* Assign Attribute Groups
* Create Attributes
* Configure Values
* Configure Pricing Slabs
* Configure Pricing Rules
* Activate/Deactivate Rules

without developer intervention.

---

## Goal

Support unlimited future service categories such as:

* Cleaning
* AC Repair
* Plumbing
* Electrical
* Salon
* Pest Control
* Laundry
* Car Wash
* Appliance Repair

without code changes.


---

# 3. Dynamic Pricing Engine

## Features

* Base Pricing
* Add-On Pricing
* Distance Charges
* Time-Based Charges
* Surge Pricing
* Tax Calculation

Pricing rules must be configurable without code changes.

---

# 4. Vendor Management Module

## Vendor Registration

* Vendor Onboarding
* Vendor Verification

## Document Verification

* ID Verification
* Address Verification
* Business Verification

## Vendor Lifecycle

Applied
→ Verification Pending
→ Approved
→ Active
→ Suspended

## Vendor Performance

* Ratings
* Reviews
* Job Acceptance Rate
* Cancellation Rate
* Earnings

## Vendor Zone Mapping

Assign Vendors To:

* Cities
* Zones
* Areas
* Pincodes

---

# 5. Booking Management Module

## Booking Lifecycle

Pending
→ Assigned
→ Accepted
→ In Progress
→ Completed
→ Cancelled

## Booking Operations

* Create Booking
* Update Booking
* Cancel Booking
* Reschedule Booking

---

# 6. Assignment Engine

## Auto Assignment

Vendor assignment based on:

* Distance
* Availability
* Rating
* Workload
* Skill Match
* Response Time

## Manual Assignment

Admin manually assigns vendors.

## Assignment Rules

Rules must be configurable dynamically.

---

# 7. CRM (Customer Management Module)

## Customer Profiles

* View Customers
* Edit Profiles
* Block Customers
* Activate Customers

## Customer History

* Bookings
* Complaints
* Refunds
* Payments

## Customer Tags

Examples:

* VIP
* Frequent Customer
* Corporate Customer
* High Value Customer

---

# 8. Sales Module

## Quotations

* Create Quotation
* Update Quotation
* Send Quotation

## Sales Orders

Convert Quotation → Sales Order

## Invoices

Convert Sales Order → Invoice

## Dynamic Workflow

Quotation
→ Sales Order
→ Invoice
→ Payment

## Additional Features

* GST Support
* Invoice Templates
* Credit Notes
* Debit Notes

---

# 9. Payment Management Module

## Payment Recording

* Cash
* UPI
* Card
* Wallet
* Bank Transfer

## Payment Tracking

* Paid
* Partial Paid
* Pending

## Vendor Settlements

Customer Payment
→ Platform Commission
→ Vendor Settlement

---

# 10. Coupon & Promotions Module

## Coupon Builder

* Flat Discount
* Percentage Discount
* Referral Coupon
* Festival Coupon
* First Booking Coupon

## Coupon Rules

* Expiry Date
* Usage Limits
* Service Restrictions
* City Restrictions

## Promotional Campaigns

* App Banners
* Website Banners
* Popups

---

# 11. Ticket & Complaint Management Module

## Ticket Creation

Categories:

* Refund
* Payment
* Vendor Issue
* Service Issue
* Technical Issue

## Ticket Lifecycle

Open
→ Assigned
→ In Progress
→ Resolved
→ Closed

## SLA Management

* Critical
* High
* Medium
* Low

## Escalation Management

* Level 1
* Level 2
* Level 3

---

# 12. Refund Management Module

## Refund Requests

* Customer Initiated
* Admin Initiated

## Refund Rules

* Full Refund
* Partial Refund
* Service-Based Refund Rules

Refund policies must be configurable dynamically.

---

# 13. SEO & CMS Module

## SEO Management

For:

* Categories
* Services
* Cities
* Blogs
* Landing Pages

## SEO Fields

* Meta Title
* Meta Description
* Keywords
* Canonical URL
* Open Graph Data

## Schema Management

* Local Business Schema
* FAQ Schema
* Service Schema
* Review Schema

## Sitemap Management

Automatic sitemap generation.

## Robots Management

Dynamic robots.txt management.

## Redirect Management

* 301 Redirects
* 302 Redirects

---

# 14. Content Management System (CMS)

## Page Management

* Homepage
* Landing Pages
* Static Pages

## FAQ Management

* Create FAQs
* Update FAQs

## Blog Management

* Create Blog
* Publish Blog
* Schedule Blog

## Banner Management

* Website Banners
* Mobile App Banners
* Promotional Banners

---

# 15. Notification Module

## Channels

* SMS
* WhatsApp
* Email
* Push Notifications

## Template Management

Dynamic variables:

* Customer Name
* Booking ID
* Vendor Name
* Service Name

## Automation Rules

Trigger notifications on:

* Booking Created
* Booking Assigned
* Booking Completed
* Refund Approved

---

# 16. Location Management Module

## Geographic Hierarchy

Country
→ State
→ City
→ Zone
→ Area
→ Pincode

All service availability should be location-driven.

---

# 17. Settings Module

## Platform Settings

* Business Hours
* Holidays
* Booking Rules
* Cancellation Rules
* Refund Rules

## Commission Settings

* Vendor Commission
* Platform Commission

## Tax Settings

* GST
* Regional Taxes

---

# 18. Analytics & Reporting Module

## Dashboard Metrics

* Total Revenue
* Total Bookings
* Active Vendors
* Active Customers
* Refund Statistics
* Conversion Rates

## Reports

* Vendor Reports
* Revenue Reports
* Booking Reports
* Service Reports
* Customer Reports

Export Formats:

* PDF
* Excel
* CSV

---

# 19. Audit & Activity Logs

Track all critical actions.

Examples:

* Vendor Approved
* Refund Processed
* Service Updated
* Pricing Changed
* Role Updated

Logs should include:

* User
* Action
* Timestamp
* IP Address
* Module

---

# Technical Requirements

## Frontend

* PWA Enabled
* Responsive Design
* Mobile Friendly
* Offline Support

## Backend

* Supabase

## Security

* RBAC
* Row Level Security
* Audit Logs
* Secure APIs

## Scalability

The architecture must support:

* Multiple Cities
* Multiple Countries
* Thousands Of Vendors
* Millions Of Customers

without major architectural changes.

---

# Final Goal

Build a fully dynamic, RBAC-based, modular, enterprise-grade service booking administration platform where business teams can manage operations without requiring developer intervention.
