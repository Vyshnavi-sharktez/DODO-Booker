# DODO BOOKER - CUSTOMER APP

## Overview

The Customer App is the primary interface through which customers discover services, schedule bookings, make payments, track service progress, communicate with vendors, provide feedback, and manage their booking history.

The Customer App is part of the DODO BOOKER ecosystem:

* Customer Application
* Vendor Application
* Admin Panel

The application must be:

* Dynamic
* Modular
* Scalable
* Mobile First
* Flutter Based
* API Driven
* Integrated with Supabase
* PWA Compatible (Web Version)

---

# Core Principles

## Browse Without Login

Customers can browse:

* Categories
* Sub Categories
* Services
* Packages
* Reviews
* Featured Services

without authentication.

Authentication is required only when:

* Booking a Service
* Making Payments
* Viewing Personal Data
* Creating Reviews

---

## Dynamic Configuration

All service-related content is controlled from the Admin Panel.

Examples:

* Categories
* Services
* Add-ons
* Packages
* Banners
* Coupons
* FAQs
* Promotions

No business data should be hardcoded.

---

# MODULES

---

# 1. Authentication Module

## Signup

* Mobile Number
* OTP Verification

## Login

* Mobile OTP Login

## Account Recovery

* Change Mobile Number
* Logout

---

# 2. Customer Profile Module

## Basic Information

* Full Name
* Mobile Number
* Email
* Profile Picture

## Profile Completion

Profile completion is mandatory before placing a booking.

---

# 3. Address Management Module

Customers can:

* Add Address
* Edit Address
* Delete Address

Address Fields:

* House Number
* Street
* Area
* Landmark
* City
* State
* Pincode

## Multiple Addresses

Examples:

* Home
* Office
* Other

---

# 4. Home Module

Displays:

* Featured Services
* Featured Categories
* Popular Services
* Trending Services
* Promotional Banners
* Coupons
* Recommended Services

All content managed dynamically by Admin.

---

# 5. Category Module

Customers can browse:

* Categories
* Sub Categories

Examples:

* Cleaning
* Appliance Repair
* Beauty Services
* Home Maintenance

---

# 6. Service Module

Displays:

* Service Name
* Description
* Pricing
* Duration
* Reviews
* Images
* FAQs

---

# 7. Add-On Module

Customers can select optional add-ons.

Example:

AC Service

Add-ons:

* Gas Refill
* Deep Cleaning
* Filter Replacement

---

# 8. Service Package Module

Customers can purchase service bundles.

Example:

Package:

* Bathroom Cleaning
* Kitchen Cleaning
* Living Room Cleaning

Package pricing configured by Admin.

---

# 9. Search Module

Customers can search:

* Categories
* Services
* Packages

---

# 10. Filter & Sorting Module

## Filters

* Category
* Sub Category
* Price Range
* Rating
* Location
* Service Type

## Sorting

* Price Low To High
* Price High To Low
* Most Reviewed
* Highest Rated
* Newest

---

# 11. Booking Module

## Booking Workflow

Browse Service
→ Select Service
→ Select Add-ons
→ Select Address
→ Select Date & Time
→ Confirm Booking

---

# 12. Advanced Scheduling Module

Supports:

## Date Selection

## Time Slot Selection

## Dynamic Slot Availability

## Same Day Booking

## Future Booking

## Recurring Booking (Future)

Examples:

* Daily
* Weekly
* Monthly

---

# 13. Booking Tracking Module

Customers can track booking status in real time.

Statuses:

Pending
→ Assigned
→ Accepted
→ Technician En Route
→ Service Started
→ Service Completed
→ Closed

---

# 14. Real-Time Updates Module

Real-time status updates using Supabase Realtime.

Examples:

* Vendor Assigned
* Vendor Accepted
* Service Started
* OTP Generated
* Service Completed

---

# 15. Payment Module

Supported Payment Methods:

* Cash On Delivery
* UPI
* Credit Card
* Debit Card
* Net Banking
* Wallet (Future)

## Payment Status

Pending
→ Paid
→ Failed
→ Refunded

---

# 16. Coupon Module

Customers can:

* View Coupons
* Apply Coupons
* Remove Coupons

Coupon eligibility controlled by Admin.

---

# 17. Invoice Module

Customers can:

* View Invoice
* Download Invoice
* Share Invoice

Formats:

* PDF
* Digital Invoice

---

# 18. Service Completion Module

Service completion requires OTP verification.

Workflow:

Vendor Completes Work
→ OTP Sent To Customer
→ Customer Shares OTP
→ Service Marked Completed

---

# 19. Review & Rating Module

Customers can:

* Rate Service
* Rate Vendor
* Submit Review

Rating Scale:

* 1 Star
* 2 Star
* 3 Star
* 4 Star
* 5 Star

---

# 20. Feedback Module

Customers can submit:

* Suggestions
* Complaints
* Service Feedback

---

# 21. Booking History Module

Displays:

## Upcoming Bookings

## Ongoing Bookings

## Completed Bookings

## Cancelled Bookings

---

# 22. Rebooking Module

Customers can quickly rebook previous services.

Workflow:

History
→ Select Previous Booking
→ Rebook

---

# 23. Wishlist Module

Customers can save:

* Services
* Packages

for future bookings.

---

# 24. Notification Module

Receive notifications for:

* Booking Confirmation
* Vendor Assigned
* Vendor Arrival
* OTP Generated
* Payment Updates
* Refund Updates
* Promotional Offers

Channels:

* Push Notifications
* SMS
* WhatsApp
* Email

---

# 25. Ticket Support Module

Customers can raise support requests.

Categories:

* Refund
* Payment
* Service Quality
* Vendor Issue
* Technical Issue

Ticket Status:

Open
→ Assigned
→ In Progress
→ Resolved
→ Closed

---

# 26. Refund Module

Customers can:

* Request Refund
* Track Refund Status

Refund policies controlled by Admin.

---

# 27. Before & After Gallery Module

Customers can view:

* Before Images
* After Images

uploaded by vendors.

This improves transparency.

---

# 28. FAQ Module

Dynamic FAQ management.

Examples:

* Service FAQs
* Booking FAQs
* Payment FAQs

Managed by Admin.

---

# 29. Promotional Content Module

Displays:

* Banners
* Featured Services
* Featured Categories
* Special Offers

Managed dynamically by Admin.

---

# 30. Customer Analytics Module

Displays:

* Total Bookings
* Total Spend
* Saved Amount
* Favorite Services

---

# Security Requirements

## Authentication

* OTP Verification
* Secure Sessions

## Data Protection

* Secure APIs
* Encrypted Data Transfer

---

# Technical Requirements

## Frontend

* Flutter
* Android
* iOS

## Web

* PWA Version

## Backend

* Supabase

## Architecture

* Dynamic Structure
* Modular Structure
* Scalable Design

---

# Future Enhancements

## Referral Program

## Wallet System

## Loyalty Rewards

## Live Vendor Tracking

## Emergency Services

## AI-Based Service Recommendations

---

# Final Goal

Build a modern, scalable, dynamic, customer-centric booking application that allows users to discover services, schedule appointments, make payments, track bookings in real time, manage history, and interact seamlessly with vendors and administrators.
