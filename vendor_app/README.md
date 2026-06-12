# DODO BOOKER - VENDOR APP

## Overview

The Vendor App is designed for service providers to manage their business, services, bookings, team members, earnings, customer interactions, and operational activities.

The Vendor App is part of the DODO BOOKER ecosystem, which consists of:

* Customer Application
* Vendor Application
* Admin Panel

The Vendor App must be:

* Dynamic
* Modular
* RBAC-Based
* Scalable
* Mobile First
* Flutter Based (Android & iOS)
* API Driven
* Integrated with Supabase Backend

---

# Core Principles

## Dynamic Architecture

All configurations should be controlled by the Admin Panel.

Examples:

* Service Categories
* Services
* Add-ons
* Required Documents
* Pricing Rules
* Coverage Rules
* Vendor Status

No business data should be hardcoded.

---

## Vendor RBAC

The Vendor App must support its own internal RBAC system.

Example Roles:

* Vendor Owner
* Manager
* Supervisor
* Technician
* Worker

Example Permissions:

* Accept Booking
* Assign Staff
* Manage Services
* View Earnings
* Upload Work Images
* Complete Jobs

---

# MODULES

---

# 1. Authentication Module

## Features

### Signup

Vendor registration using:

* Mobile Number
* OTP Verification
* Email (Optional)

### Login

* Mobile OTP Login
* Password Login
* Email Login (Optional)

### Account Recovery

* Forgot Password
* Reset Password
* Change Password

---

# 2. Vendor Profile Module

## Basic Information

* Business Name
* Owner Name
* Mobile Number
* Email
* Address
* Profile Photo

## Business Information

* GST Number
* Business Type
* Registration Number

## Bank Information

* Account Holder Name
* Account Number
* IFSC Code
* Bank Name

---

# 3. KYC & Document Verification Module

Document requirements must be dynamic and controlled by Admin.

Examples:

* Aadhaar Card
* PAN Card
* GST Certificate
* Shop License
* Business Registration
* Bank Passbook

## Verification Workflow

Draft
→ Submitted
→ Under Review
→ Approved
→ Rejected

---

# 4. Service Selection Module

Vendor cannot create Categories or Services.

Categories and Services are managed by Admin.

Vendor can:

* Browse Categories
* Browse Sub Categories
* Select Services Offered
* Activate Services
* Deactivate Services

---

# 5. Service Pricing Module

Vendor can configure:

* Service Price
* Add-on Price
* Package Price

Admin can control whether:

* Pricing is fixed
* Pricing is vendor controlled

---

# 6. Service Coverage Module

Vendor defines service availability.

## Coverage Structure

* Country
* State
* City
* Zone
* Area
* Pincode

## Radius Management

Examples:

* 5 KM
* 10 KM
* 20 KM

## Availability Zones

Vendor can manage:

* Active Zones
* Restricted Zones

---

# 7. Availability Management Module

Vendor can configure:

## Working Days

* Monday to Sunday

## Working Hours

Examples:

* 9:00 AM - 6:00 PM
* 10:00 AM - 8:00 PM

## Holidays

## Leave Management

## Temporary Pause

Examples:

* Vacation
* Emergency
* Staff Shortage

---

# 8. Dashboard Module

Vendor dashboard displays:

* Today's Bookings
* Ongoing Jobs
* Pending Jobs
* Revenue
* Wallet Balance
* Ratings
* Performance Metrics

---

# 9. Booking Management Module

## Booking Statuses

Pending
→ Assigned
→ Accepted
→ Ongoing
→ Completed
→ Cancelled

## Vendor Actions

* View Booking
* Accept Booking
* Reject Booking
* Start Service
* Update Status
* Complete Service

---

# 10. Job Details Module

Each booking contains:

## Customer Information

* Name
* Phone
* Address

## Service Information

* Service Name
* Add-ons
* Package Details

## Schedule Information

* Date
* Time Slot

## Notes

* Customer Notes
* Internal Notes

---

# 11. Work Proof Module

## Before Images

Mandatory before starting service.

Vendor uploads:

* Photos
* Videos (Optional)

## After Images

Mandatory before completing service.

Vendor uploads:

* Photos
* Videos (Optional)

## Work Notes

Examples:

* AC Filter Cleaned
* Gas Refilled
* Deep Cleaning Completed

---

# 12. OTP Verification Module

Service completion requires customer verification.

Workflow:

Booking Started
→ Work Completed
→ OTP Sent To Customer
→ Vendor Enters OTP
→ Service Marked Completed

Purpose:

* Fraud Prevention
* Customer Confirmation
* Dispute Reduction

---

# 13. Wallet & Earnings Module

## Wallet Dashboard

Displays:

* Available Balance
* Pending Balance
* Total Earnings

## Transactions

* Credits
* Debits
* Refund Adjustments
* Commission Deductions

## Withdrawals

Vendor can request:

* Bank Transfer
* Settlement Request

---

# 14. Settlement Module

Track:

* Settled Amount
* Pending Settlement
* Settlement History

Status:

Pending
→ Processing
→ Completed

---

# 15. Customer Feedback Module

Customer can:

* Rate Vendor
* Submit Review

Vendor can view:

* Ratings
* Reviews
* Feedback History

---

# 16. Customer Rating Module

Vendor can also rate customers.

Examples:

* Cooperative Customer
* Unresponsive Customer
* Fraudulent Activity

This helps improve service quality and dispute management.

---

# 17. Vendor Team Management Module

Vendor can manage staff.

## Team Roles

* Manager
* Supervisor
* Technician
* Worker

## Team Operations

* Create Staff Accounts
* Edit Staff Accounts
* Deactivate Staff Accounts

---

# 18. Vendor Staff RBAC Module

Vendor Owner assigns permissions.

Examples:

### Manager

* Manage Staff
* View Revenue
* Assign Jobs

### Technician

* View Jobs
* Upload Images
* Complete Service

### Worker

* View Assigned Tasks

---

# 19. Internal Job Assignment Module

Vendor can assign bookings to team members.

Workflow:

Booking Received
→ Assign Technician
→ Technician Completes Work

---

# 20. Notification Module

Receive notifications for:

* New Booking
* Booking Assigned
* Booking Cancelled
* OTP Generated
* Payment Received
* Settlement Completed
* Document Approved
* Document Rejected

Channels:

* Push Notification
* SMS
* WhatsApp
* Email

---

# 21. Ticket Support Module

Vendor can raise support tickets.

Categories:

* Payment Issue
* Customer Issue
* Technical Issue
* Verification Issue
* Settlement Issue

Ticket Workflow:

Open
→ Assigned
→ In Progress
→ Resolved
→ Closed

---

# 22. Document Expiry Tracking Module

Track expiry dates for:

* License
* Insurance
* GST Registration
* Certifications

Alerts:

* 30 Days Before Expiry
* 15 Days Before Expiry
* 7 Days Before Expiry

---

# 23. Vendor Analytics Module

Display:

## Revenue Analytics

* Daily Revenue
* Weekly Revenue
* Monthly Revenue

## Booking Analytics

* Total Bookings
* Completed Jobs
* Cancelled Jobs

## Performance Analytics

* Acceptance Rate
* Completion Rate
* Customer Ratings

---

# 24. Vendor Performance Module

Track:

* Acceptance Percentage
* Response Time
* Completion Rate
* Customer Satisfaction Score

These metrics may influence automatic booking assignment.

---

# 25. Service Pause Module

Vendor can temporarily disable:

* Entire Account
* Individual Services
* Specific Locations

Without deleting configurations.

---

# Security Requirements

## Authentication

* OTP Verification
* Secure Sessions

## Authorization

* Vendor RBAC
* Permission Based Access

## Data Protection

* Secure APIs
* Encrypted Data Transfer

---

# Technical Requirements

## Frontend

* Flutter
* Android
* iOS

## Backend

* Supabase

## Architecture

* Modular Structure
* API Driven
* Scalable Design

---

# Future Enhancements

## Subscription Plans

* Free
* Silver
* Gold
* Premium

## AI-Based Assignment Recommendations

## Dynamic Pricing Suggestions

## Route Optimization

## Staff Attendance Tracking

## Inventory Management

---

# Final Goal

Build a fully dynamic, modular, RBAC-based Vendor Management System that enables service providers to manage services, bookings, staff, customers, earnings, and operational workflows efficiently while integrating seamlessly with the Admin Panel and Customer Application.
