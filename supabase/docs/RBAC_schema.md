# RBAC Schema

## Purpose

RBAC (Role Based Access Control) controls who can access what in the DODO BOOKER platform.

The entire platform is permission-based.

Users → Roles → Permissions

---

# Tables

## roles

Stores system roles.

Examples:

* Super Admin
* Operations Manager
* Finance Manager
* SEO Manager
* Support Manager

---

## permissions

Stores all permissions.

Examples:

* booking.view
* booking.assign
* vendor.approve
* refund.process
* seo.manage

---

## role_permissions

Maps roles to permissions.

Example:

Operations Manager

* booking.view
* booking.assign

Finance Manager

* payment.view
* refund.process

---

## admin_users

Stores Admin Panel users.

Examples:

* Super Admin
* Operations Manager
* Finance Manager

Each admin user belongs to Supabase Authentication.

---

## admin_user_roles

Maps Admin Users to Roles.

Example:

John
→ Operations Manager

Priya
→ Finance Manager

---

# Relationships

Role
↓
Role Permissions
↓
Permissions

Admin User
↓
Admin User Roles
↓
Role

---

# Example Flow

Super Admin Login
↓
Role Loaded
↓
Permissions Loaded
↓
Dashboard Access Granted

Operations Manager Login
↓
Role Loaded
↓
Only Booking Permissions Available

---

# Future Expansion

Vendor RBAC

* Vendor Owner
* Manager
* Supervisor
* Technician

Customer Roles

* Customer

All future permissions must follow the RBAC architecture.
