# Database Schema Proposal - Secure Community Management System

## Overview

This document proposes a comprehensive PostgreSQL database schema for the Secure Community Management System. The system is designed to manage multiple municipalities, their clients, service routers, invoices, payments, and service cutoffs with robust security through JWT authentication and role-based access control.

### Design Principles

The schema follows these core principles:

- **Multi-tenancy by municipality**: Data is partitioned by municipality for isolation and scalability
- **Audit trails**: All tables include `created_at` and `updated_at` timestamps for tracking changes
- **Soft deletes**: Critical tables support soft deletion via `deleted_at` timestamp to preserve data integrity
- **Security first**: Sensitive data such as passwords are stored as hashes, with additional security measures for PII
- **Referential integrity**: Foreign key constraints with appropriate CASCADE behaviors ensure data consistency
- **Performance optimization**: Strategic indexes on frequently queried columns and foreign keys
- **Extensibility**: Designed to accommodate future features and scaling requirements

### Entity List

The system comprises the following core entities:

1. **Users** - System users with authentication and role-based access
2. **Roles** - Predefined roles for authorization (admin, manager, clerk, etc.)
3. **Municipalities** - Community or organizational units
4. **Clients** - Service subscribers linked to municipalities
5. **Service Plans** - Available service tiers and packages
6. **Routers** - Network equipment inventory and assignments
7. **Invoices** - Billing documents with header and line items
8. **Invoice Lines** - Individual charges within an invoice
9. **Payments** - Payment records linked to invoices
10. **Service Cutoffs** - Service suspension tracking and status management
11. **File Uploads** - User images and document storage metadata

## PostgreSQL Extensions

The following PostgreSQL extensions are recommended for enhanced functionality:

```sql
-- UUID generation (PostgreSQL 13+)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- For case-insensitive text operations (emails, usernames)
CREATE EXTENSION IF NOT EXISTS "citext";
```

### Extension Benefits

- **uuid-ossp**: Provides `uuid_generate_v4()` function for generating universally unique identifiers, essential for distributed systems and avoiding ID conflicts
- **citext**: Case-insensitive text type ideal for email addresses and usernames, simplifying queries and preventing duplicate entries with different casing

## Enum Types

Enumerations provide type safety and data consistency for status and role fields.

```sql
-- User role enumeration
CREATE TYPE user_role AS ENUM (
  'super_admin',
  'admin',
  'manager',
  'clerk',
  'viewer',
  'technician'
);

-- Service cutoff status
CREATE TYPE cutoff_status AS ENUM (
  'pending',
  'scheduled',
  'active',
  'restored',
  'cancelled'
);

-- Invoice status
CREATE TYPE invoice_status AS ENUM (
  'draft',
  'pending',
  'sent',
  'paid',
  'overdue',
  'cancelled',
  'void'
);

-- Payment status
CREATE TYPE payment_status AS ENUM (
  'pending',
  'completed',
  'failed',
  'refunded'
);

-- Payment method
CREATE TYPE payment_method AS ENUM (
  'cash',
  'credit_card',
  'debit_card',
  'bank_transfer',
  'mobile_payment',
  'check'
);

-- Router status
CREATE TYPE router_status AS ENUM (
  'available',
  'assigned',
  'maintenance',
  'retired',
  'lost'
);
```

## Core Tables

### 1. Roles Table

The `roles` table defines system-wide authorization levels and permissions.

```sql
CREATE TABLE roles (
  id SERIAL PRIMARY KEY,
  role_name user_role NOT NULL UNIQUE,
  description TEXT,
  permissions JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_roles_role_name ON roles(role_name);

COMMENT ON TABLE roles IS 'System roles for authorization and access control';
COMMENT ON COLUMN roles.permissions IS 'JSON object storing granular permissions for the role';
```

**Key Design Decisions:**
- `permissions` column uses JSONB for flexible, queryable permission structures
- Unique constraint on `role_name` prevents duplicate role definitions
- Index on `role_name` optimizes authorization checks

### 2. Municipalities Table

Municipalities represent organizational units or communities served by the system.

```sql
CREATE TABLE municipalities (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  code VARCHAR(50) UNIQUE NOT NULL,
  address TEXT,
  city VARCHAR(100),
  state VARCHAR(100),
  postal_code VARCHAR(20),
  country VARCHAR(100) DEFAULT 'USA',
  contact_email VARCHAR(255),
  contact_phone VARCHAR(50),
  is_active BOOLEAN DEFAULT true,
  settings JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_municipalities_code ON municipalities(code);
CREATE INDEX idx_municipalities_is_active ON municipalities(is_active) WHERE deleted_at IS NULL;

COMMENT ON TABLE municipalities IS 'Community or organizational units managing services';
COMMENT ON COLUMN municipalities.code IS 'Unique identifier code for the municipality';
COMMENT ON COLUMN municipalities.settings IS 'JSON configuration for municipality-specific settings';
COMMENT ON COLUMN municipalities.deleted_at IS 'Soft delete timestamp';
```

**Key Design Decisions:**
- Soft delete support via `deleted_at` preserves historical data
- `settings` JSONB column allows customization per municipality
- Partial index on `is_active` for efficient active municipality queries

### 3. Users Table

The `users` table stores authentication credentials and user profiles.

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(100) UNIQUE NOT NULL,
  email CITEXT UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  municipality_id INTEGER REFERENCES municipalities(id) ON DELETE SET NULL,
  first_name VARCHAR(100),
  last_name VARCHAR(100),
  phone VARCHAR(50),
  profile_image_url TEXT,
  is_active BOOLEAN DEFAULT true,
  last_login TIMESTAMP WITH TIME ZONE,
  password_changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  email_verified BOOLEAN DEFAULT false,
  email_verified_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role_id ON users(role_id);
CREATE INDEX idx_users_municipality_id ON users(municipality_id);
CREATE INDEX idx_users_is_active ON users(is_active) WHERE deleted_at IS NULL;

COMMENT ON TABLE users IS 'System users with authentication and authorization';
COMMENT ON COLUMN users.password_hash IS 'Bcrypt hashed password (NEVER store plain text)';
COMMENT ON COLUMN users.email IS 'Case-insensitive email using CITEXT type';
COMMENT ON COLUMN users.profile_image_url IS 'URL or path to user profile image';
```

**Security Considerations:**
- Passwords MUST be hashed using bcrypt with appropriate work factor (minimum 10 rounds)
- Email uses CITEXT type for case-insensitive uniqueness
- `password_changed_at` supports password expiration policies
- Foreign key to `roles` uses `RESTRICT` to prevent accidental deletion of roles in use

### 4. Service Plans Table

Service plans define the available service tiers and pricing structures.

```sql
CREATE TABLE service_plans (
  id SERIAL PRIMARY KEY,
  municipality_id INTEGER NOT NULL REFERENCES municipalities(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  monthly_rate DECIMAL(10, 2) NOT NULL,
  setup_fee DECIMAL(10, 2) DEFAULT 0.00,
  bandwidth_mbps INTEGER,
  data_cap_gb INTEGER,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_service_plans_municipality_id ON service_plans(municipality_id);
CREATE INDEX idx_service_plans_is_active ON service_plans(is_active) WHERE deleted_at IS NULL;

COMMENT ON TABLE service_plans IS 'Available service packages and pricing tiers';
COMMENT ON COLUMN service_plans.monthly_rate IS 'Recurring monthly charge';
COMMENT ON COLUMN service_plans.bandwidth_mbps IS 'Maximum bandwidth in megabits per second';
```

**Key Design Decisions:**
- Municipality-scoped plans allow different pricing in different regions
- `DECIMAL(10, 2)` ensures precise monetary calculations
- Soft delete preserves plan history for existing subscriptions

### 5. Clients Table

Clients are service subscribers with their account and service information.

```sql
CREATE TABLE clients (
  id SERIAL PRIMARY KEY,
  municipality_id INTEGER NOT NULL REFERENCES municipalities(id) ON DELETE CASCADE,
  service_plan_id INTEGER REFERENCES service_plans(id) ON DELETE SET NULL,
  client_code VARCHAR(50) UNIQUE NOT NULL,
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  email CITEXT,
  phone VARCHAR(50),
  service_address TEXT NOT NULL,
  service_city VARCHAR(100),
  service_state VARCHAR(100),
  service_postal_code VARCHAR(20),
  billing_address TEXT,
  billing_city VARCHAR(100),
  billing_state VARCHAR(100),
  billing_postal_code VARCHAR(20),
  installation_date DATE,
  account_balance DECIMAL(10, 2) DEFAULT 0.00,
  is_active BOOLEAN DEFAULT true,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_clients_municipality_id ON clients(municipality_id);
CREATE INDEX idx_clients_service_plan_id ON clients(service_plan_id);
CREATE INDEX idx_clients_client_code ON clients(client_code);
CREATE INDEX idx_clients_email ON clients(email);
CREATE INDEX idx_clients_is_active ON clients(is_active) WHERE deleted_at IS NULL;

COMMENT ON TABLE clients IS 'Service subscribers with account information';
COMMENT ON COLUMN clients.client_code IS 'Unique customer identifier';
COMMENT ON COLUMN clients.account_balance IS 'Current outstanding balance (positive = owes, negative = credit)';
```

**Key Design Decisions:**
- Separate service and billing addresses accommodate different use cases
- `account_balance` tracks running balance for quick queries
- Foreign key to `service_plans` uses `SET NULL` to preserve client records when plans are deleted

### 6. Routers Table

The `routers` table manages network equipment inventory and assignments.

```sql
CREATE TABLE routers (
  id SERIAL PRIMARY KEY,
  municipality_id INTEGER NOT NULL REFERENCES municipalities(id) ON DELETE CASCADE,
  client_id INTEGER REFERENCES clients(id) ON DELETE SET NULL,
  serial_number VARCHAR(100) UNIQUE NOT NULL,
  model VARCHAR(100),
  mac_address VARCHAR(17),
  ip_address INET,
  status router_status DEFAULT 'available',
  purchase_date DATE,
  warranty_expiry DATE,
  location TEXT,
  assigned_date DATE,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_routers_municipality_id ON routers(municipality_id);
CREATE INDEX idx_routers_client_id ON routers(client_id);
CREATE INDEX idx_routers_serial_number ON routers(serial_number);
CREATE INDEX idx_routers_status ON routers(status);
CREATE INDEX idx_routers_mac_address ON routers(mac_address);

COMMENT ON TABLE routers IS 'Network equipment inventory and assignments';
COMMENT ON COLUMN routers.ip_address IS 'Uses PostgreSQL INET type for IP address validation';
COMMENT ON COLUMN routers.assigned_date IS 'Date when router was assigned to current client';
```

**Key Design Decisions:**
- `INET` type for IP addresses provides validation and efficient storage
- Unique constraint on `serial_number` prevents duplicate equipment entries
- `client_id` can be NULL for available/unassigned routers

### 7. Invoices Table

Invoices represent billing documents with header-level information.

```sql
CREATE TABLE invoices (
  id SERIAL PRIMARY KEY,
  municipality_id INTEGER NOT NULL REFERENCES municipalities(id) ON DELETE CASCADE,
  client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  invoice_number VARCHAR(50) UNIQUE NOT NULL,
  invoice_date DATE NOT NULL DEFAULT CURRENT_DATE,
  due_date DATE NOT NULL,
  status invoice_status DEFAULT 'draft',
  subtotal DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  tax_rate DECIMAL(5, 4) DEFAULT 0.0000,
  tax_amount DECIMAL(10, 2) DEFAULT 0.00,
  total_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  amount_paid DECIMAL(10, 2) DEFAULT 0.00,
  balance_due DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  notes TEXT,
  terms TEXT,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_invoices_municipality_id ON invoices(municipality_id);
CREATE INDEX idx_invoices_client_id ON invoices(client_id);
CREATE INDEX idx_invoices_invoice_number ON invoices(invoice_number);
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_due_date ON invoices(due_date);
CREATE INDEX idx_invoices_invoice_date ON invoices(invoice_date);

COMMENT ON TABLE invoices IS 'Billing documents with header information';
COMMENT ON COLUMN invoices.invoice_number IS 'Unique invoice identifier for reference';
COMMENT ON COLUMN invoices.balance_due IS 'Calculated as total_amount - amount_paid';
```

**Key Design Decisions:**
- Separate fields for subtotal, tax, and total enable flexible tax calculations
- `balance_due` tracks outstanding amount for payment tracking
- `created_by` links to user for audit trails
- Soft delete preserves invoice history

### 8. Invoice Lines Table

Invoice lines contain individual charges and line items within an invoice.

```sql
CREATE TABLE invoice_lines (
  id SERIAL PRIMARY KEY,
  invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  line_number INTEGER NOT NULL,
  description TEXT NOT NULL,
  quantity DECIMAL(10, 2) NOT NULL DEFAULT 1.00,
  unit_price DECIMAL(10, 2) NOT NULL,
  line_total DECIMAL(10, 2) NOT NULL,
  service_period_start DATE,
  service_period_end DATE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_invoice_line_number UNIQUE (invoice_id, line_number)
);

CREATE INDEX idx_invoice_lines_invoice_id ON invoice_lines(invoice_id);

COMMENT ON TABLE invoice_lines IS 'Individual charges within invoices';
COMMENT ON COLUMN invoice_lines.line_number IS 'Sequential line number within the invoice';
COMMENT ON COLUMN invoice_lines.line_total IS 'Calculated as quantity * unit_price';
COMMENT ON COLUMN invoice_lines.service_period_start IS 'Start date of service period for this charge';
```

**Key Design Decisions:**
- Composite unique constraint ensures line numbers are unique per invoice
- `CASCADE` delete ensures orphaned lines are removed with invoice
- Service period fields support recurring billing and proration

### 9. Payments Table

The `payments` table records all payment transactions linked to invoices.

```sql
CREATE TABLE payments (
  id SERIAL PRIMARY KEY,
  municipality_id INTEGER NOT NULL REFERENCES municipalities(id) ON DELETE CASCADE,
  client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  invoice_id INTEGER REFERENCES invoices(id) ON DELETE SET NULL,
  payment_number VARCHAR(50) UNIQUE NOT NULL,
  payment_date DATE NOT NULL DEFAULT CURRENT_DATE,
  amount DECIMAL(10, 2) NOT NULL,
  payment_method payment_method NOT NULL,
  status payment_status DEFAULT 'pending',
  reference_number VARCHAR(100),
  transaction_id VARCHAR(255),
  notes TEXT,
  processed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payments_municipality_id ON payments(municipality_id);
CREATE INDEX idx_payments_client_id ON payments(client_id);
CREATE INDEX idx_payments_invoice_id ON payments(invoice_id);
CREATE INDEX idx_payments_payment_number ON payments(payment_number);
CREATE INDEX idx_payments_payment_date ON payments(payment_date);
CREATE INDEX idx_payments_status ON payments(status);

COMMENT ON TABLE payments IS 'Payment transactions linked to invoices';
COMMENT ON COLUMN payments.reference_number IS 'External reference like check number or transaction ID';
COMMENT ON COLUMN payments.transaction_id IS 'Payment gateway transaction identifier';
```

**Key Design Decisions:**
- `invoice_id` can be NULL to support payments without specific invoice (e.g., deposits)
- `SET NULL` on invoice deletion preserves payment records
- Multiple indexes support common query patterns (by client, date, status)

### 10. Service Cutoffs Table

Service cutoffs track service suspensions and restoration activities.

```sql
CREATE TABLE service_cutoffs (
  id SERIAL PRIMARY KEY,
  municipality_id INTEGER NOT NULL REFERENCES municipalities(id) ON DELETE CASCADE,
  client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  router_id INTEGER REFERENCES routers(id) ON DELETE SET NULL,
  status cutoff_status DEFAULT 'pending',
  reason TEXT NOT NULL,
  scheduled_date DATE NOT NULL,
  executed_date DATE,
  restored_date DATE,
  executed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  restored_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_service_cutoffs_municipality_id ON service_cutoffs(municipality_id);
CREATE INDEX idx_service_cutoffs_client_id ON service_cutoffs(client_id);
CREATE INDEX idx_service_cutoffs_router_id ON service_cutoffs(router_id);
CREATE INDEX idx_service_cutoffs_status ON service_cutoffs(status);
CREATE INDEX idx_service_cutoffs_scheduled_date ON service_cutoffs(scheduled_date);

COMMENT ON TABLE service_cutoffs IS 'Service suspension and restoration tracking';
COMMENT ON COLUMN service_cutoffs.reason IS 'Explanation for service cutoff (e.g., non-payment)';
COMMENT ON COLUMN service_cutoffs.executed_by IS 'User who executed the cutoff';
COMMENT ON COLUMN service_cutoffs.restored_by IS 'User who restored the service';
```

**Key Design Decisions:**
- Separate tracking for scheduled vs executed vs restored dates
- User references for accountability in cutoff and restoration actions
- Status enum provides clear workflow state

### 11. File Uploads Table

File uploads store metadata for user images and documents.

```sql
CREATE TABLE file_uploads (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  client_id INTEGER REFERENCES clients(id) ON DELETE CASCADE,
  file_name VARCHAR(255) NOT NULL,
  file_path TEXT NOT NULL,
  file_type VARCHAR(100),
  file_size BIGINT,
  mime_type VARCHAR(100),
  upload_purpose VARCHAR(50),
  is_public BOOLEAN DEFAULT false,
  uploaded_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_file_uploads_user_id ON file_uploads(user_id);
CREATE INDEX idx_file_uploads_client_id ON file_uploads(client_id);
CREATE INDEX idx_file_uploads_uploaded_by ON file_uploads(uploaded_by);
CREATE INDEX idx_file_uploads_upload_purpose ON file_uploads(upload_purpose);

COMMENT ON TABLE file_uploads IS 'Metadata for user images and document uploads';
COMMENT ON COLUMN file_uploads.file_path IS 'Full path or URL to the stored file';
COMMENT ON COLUMN file_uploads.upload_purpose IS 'Purpose category (e.g., profile_image, document, invoice_attachment)';
COMMENT ON COLUMN file_uploads.is_public IS 'Whether file is publicly accessible without authentication';
```

**Key Design Decisions:**
- Stores metadata only; actual files stored on filesystem or object storage (S3, etc.)
- Flexible association with both users and clients
- `CASCADE` on user/client deletion ensures cleanup of associated files
- `upload_purpose` enables filtering by file category

## Relationships and Cardinality

### One-to-Many Relationships

1. **Roles → Users**: One role can be assigned to many users
2. **Municipalities → Users**: One municipality can have many users
3. **Municipalities → Clients**: One municipality serves many clients
4. **Municipalities → Service Plans**: One municipality defines many service plans
5. **Municipalities → Routers**: One municipality owns many routers
6. **Municipalities → Invoices**: One municipality generates many invoices
7. **Municipalities → Payments**: One municipality processes many payments
8. **Municipalities → Service Cutoffs**: One municipality manages many cutoffs
9. **Service Plans → Clients**: One service plan can be subscribed by many clients
10. **Clients → Routers**: One client can have many routers assigned (though typically one)
11. **Clients → Invoices**: One client receives many invoices
12. **Clients → Payments**: One client makes many payments
13. **Clients → Service Cutoffs**: One client can have many service cutoffs over time
14. **Invoices → Invoice Lines**: One invoice contains many line items
15. **Users → File Uploads**: One user can upload many files
16. **Clients → File Uploads**: One client record can have many associated files

### Many-to-One Relationships

1. **Payments → Invoices**: Many payments can be applied to one invoice (partial payments)

### Relationship Diagram Description

The database follows a hierarchical structure with **Municipalities** at the top level, providing multi-tenant isolation:

```
Municipality (root tenant)
├── Users (staff and administrators)
├── Roles (authorization)
├── Service Plans (offered packages)
├── Clients (service subscribers)
│   ├── Routers (assigned equipment)
│   ├── Invoices (billing documents)
│   │   └── Invoice Lines (charges)
│   ├── Payments (transactions)
│   └── Service Cutoffs (suspensions)
└── File Uploads (documents and images)
```

Each municipality operates independently with its own clients, plans, and transactions. Users can be scoped to a specific municipality or have system-wide access depending on their role.

## Foreign Key Relationships and Cascading Behavior

### ON DELETE CASCADE

Used when child records have no independent meaning without the parent:

- `municipalities → service_plans`
- `municipalities → clients`
- `municipalities → routers`
- `municipalities → invoices`
- `municipalities → payments`
- `municipalities → service_cutoffs`
- `clients → service_cutoffs`
- `invoices → invoice_lines`
- `users → file_uploads` (when associated with user)
- `clients → file_uploads` (when associated with client)

### ON DELETE SET NULL

Used when child records should be preserved but reference removed:

- `municipalities → users` (preserve user accounts)
- `service_plans → clients` (preserve client when plan deleted)
- `clients → routers` (router returns to available pool)
- `invoices → payments` (preserve payment records)
- `users → invoices.created_by` (preserve invoice)
- `users → payments.processed_by` (preserve payment)
- `users → service_cutoffs.executed_by/restored_by` (preserve cutoff record)
- `routers → service_cutoffs` (preserve cutoff history)

### ON DELETE RESTRICT

Used to prevent deletion when dependencies exist:

- `roles → users` (cannot delete role if users have it)

## Indexes and Performance

### Primary Indexes

All tables have primary key indexes on `id` (automatically created).

### Foreign Key Indexes

Foreign key columns are indexed for efficient JOIN operations:
- `role_id`, `municipality_id` on users
- `municipality_id` on all municipality-scoped tables
- `client_id` on invoices, payments, routers, service_cutoffs
- `invoice_id` on invoice_lines, payments
- `service_plan_id` on clients

### Business Logic Indexes

- **Unique constraints**: `username`, `email`, `client_code`, `invoice_number`, `payment_number`, `serial_number` (routers)
- **Status indexes**: Optimize queries filtering by status fields
- **Date indexes**: `due_date`, `invoice_date`, `payment_date`, `scheduled_date` for date-range queries
- **Partial indexes**: `is_active WHERE deleted_at IS NULL` for active record queries

### Composite Indexes

- `(invoice_id, line_number)` on invoice_lines ensures unique line ordering

## Security Considerations

### Password Storage

- **CRITICAL**: Passwords MUST NEVER be stored in plain text
- Use bcrypt hashing with work factor of 10-12 rounds
- Store only the hash in `users.password_hash`
- Backend must validate password complexity before hashing

### Sensitive Data

- **Email addresses**: Use CITEXT type for case-insensitive operations
- **Phone numbers**: Store in VARCHAR to accommodate various formats
- **PII fields**: Consider encryption at rest for highly sensitive deployments
- **File uploads**: Store files outside database in secure storage with signed URLs

### Access Control

- Application layer must enforce role-based access control
- Use parameterized queries to prevent SQL injection
- Database user (`appuser`) should have limited privileges (no DROP, ALTER on production)
- Separate read-only user for reporting queries

### Multi-tenancy Isolation

- All queries must filter by `municipality_id` to enforce tenant isolation
- Consider Row-Level Security (RLS) policies for additional enforcement:

```sql
-- Example RLS policy (optional, requires setup)
ALTER TABLE clients ENABLE ROW LEVEL SECURITY;

CREATE POLICY municipality_isolation ON clients
  USING (municipality_id = current_setting('app.current_municipality_id')::INTEGER);
```

### Audit Logging

All tables include audit fields:
- `created_at`: Timestamp of record creation
- `updated_at`: Timestamp of last modification (update via trigger)
- `created_by`: User who created the record (where applicable)

Consider implementing trigger-based audit logging for sensitive tables:

```sql
-- Example audit trigger (implementation required)
CREATE TABLE audit_log (
  id SERIAL PRIMARY KEY,
  table_name VARCHAR(100),
  record_id INTEGER,
  action VARCHAR(10),
  old_values JSONB,
  new_values JSONB,
  changed_by INTEGER,
  changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

## Triggers and Automation

### Updated At Trigger

All tables should have an automatic `updated_at` trigger:

```sql
-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to all tables with updated_at column
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Repeat for all other tables:
-- roles, municipalities, service_plans, clients, routers, 
-- invoices, invoice_lines, payments, service_cutoffs, file_uploads
```

### Invoice Calculation Trigger

Automatically calculate invoice totals when lines are modified:

```sql
CREATE OR REPLACE FUNCTION update_invoice_totals()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE invoices
  SET 
    subtotal = (
      SELECT COALESCE(SUM(line_total), 0)
      FROM invoice_lines
      WHERE invoice_id = COALESCE(NEW.invoice_id, OLD.invoice_id)
    ),
    tax_amount = subtotal * tax_rate,
    total_amount = subtotal + (subtotal * tax_rate),
    balance_due = total_amount - amount_paid,
    updated_at = CURRENT_TIMESTAMP
  WHERE id = COALESCE(NEW.invoice_id, OLD.invoice_id);
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_invoice_totals_trigger
  AFTER INSERT OR UPDATE OR DELETE ON invoice_lines
  FOR EACH ROW
  EXECUTE FUNCTION update_invoice_totals();
```

### Payment Application Trigger

Update invoice `amount_paid` and `balance_due` when payments are recorded:

```sql
CREATE OR REPLACE FUNCTION update_invoice_payment()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.invoice_id IS NOT NULL AND NEW.status = 'completed' THEN
    UPDATE invoices
    SET 
      amount_paid = amount_paid + NEW.amount,
      balance_due = total_amount - (amount_paid + NEW.amount),
      status = CASE 
        WHEN (total_amount - (amount_paid + NEW.amount)) <= 0 THEN 'paid'::invoice_status
        ELSE status
      END,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = NEW.invoice_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER apply_payment_to_invoice
  AFTER INSERT OR UPDATE ON payments
  FOR EACH ROW
  EXECUTE FUNCTION update_invoice_payment();
```

## Sample Data and Seed Scripts

### Seed Roles

```sql
INSERT INTO roles (role_name, description, permissions) VALUES
('super_admin', 'Full system access across all municipalities', '{"all": true}'),
('admin', 'Municipality administrator with full access to their municipality', '{"manage_users": true, "manage_clients": true, "manage_billing": true}'),
('manager', 'Service manager with operational access', '{"manage_clients": true, "view_billing": true, "manage_cutoffs": true}'),
('clerk', 'Customer service clerk with limited access', '{"view_clients": true, "create_payments": true}'),
('viewer', 'Read-only access for reporting', '{"view_clients": true, "view_billing": true}'),
('technician', 'Field technician for installations and repairs', '{"view_clients": true, "manage_routers": true, "manage_cutoffs": true}');
```

### Seed Municipality

```sql
INSERT INTO municipalities (name, code, address, city, state, postal_code, contact_email, contact_phone)
VALUES 
('Sunshine Community Network', 'SCN001', '123 Main Street', 'Springfield', 'IL', '62701', 'admin@sunshinecomm.net', '555-0100');
```

### Seed Admin User

```sql
-- Note: Password hash is for 'AdminPassword123!' - CHANGE IN PRODUCTION
INSERT INTO users (username, email, password_hash, role_id, municipality_id, first_name, last_name, is_active, email_verified)
VALUES 
('admin', 'admin@sunshinecomm.net', '$2b$10$abcdefghijklmnopqrstuvwxyz1234567890', 1, 1, 'System', 'Administrator', true, true);
```

### Seed Service Plans

```sql
INSERT INTO service_plans (municipality_id, name, description, monthly_rate, setup_fee, bandwidth_mbps, data_cap_gb, is_active)
VALUES 
(1, 'Basic Internet', '10 Mbps residential service', 29.99, 49.99, 10, 250, true),
(1, 'Standard Internet', '50 Mbps residential service', 49.99, 49.99, 50, 500, true),
(1, 'Premium Internet', '100 Mbps unlimited service', 79.99, 0.00, 100, NULL, true),
(1, 'Business Class', '200 Mbps business service with SLA', 149.99, 99.99, 200, NULL, true);
```

## Migrations Strategy

### Migration Tool Recommendations

For Node.js/Express backend:
- **node-pg-migrate**: Lightweight, PostgreSQL-specific
- **Knex.js**: Query builder with migration support
- **Sequelize**: Full ORM with migration system
- **TypeORM**: TypeScript-first ORM with migrations

### Migration Structure

Organize migrations chronologically:

```
migrations/
├── 001_create_extensions.sql
├── 002_create_enums.sql
├── 003_create_roles_table.sql
├── 004_create_municipalities_table.sql
├── 005_create_users_table.sql
├── 006_create_service_plans_table.sql
├── 007_create_clients_table.sql
├── 008_create_routers_table.sql
├── 009_create_invoices_table.sql
├── 010_create_invoice_lines_table.sql
├── 011_create_payments_table.sql
├── 012_create_service_cutoffs_table.sql
├── 013_create_file_uploads_table.sql
├── 014_create_triggers.sql
├── 015_seed_roles.sql
└── 016_seed_initial_data.sql
```

### Migration Best Practices

1. **Atomic migrations**: Each migration file should be independently executable
2. **Rollback support**: Include DOWN migrations to reverse changes
3. **Data migrations**: Separate schema changes from data migrations
4. **Testing**: Test migrations on copy of production data before deployment
5. **Backup**: Always backup database before running migrations in production
6. **Versioning**: Track migration version in database table

### Migration Tracking Table

```sql
CREATE TABLE schema_migrations (
  version VARCHAR(255) PRIMARY KEY,
  applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

## CSV Export Considerations

The system requires CSV export functionality for various entities. Key considerations:

### Export Query Examples

**Client Export:**
```sql
SELECT 
  c.client_code,
  c.first_name,
  c.last_name,
  c.email,
  c.phone,
  c.service_address,
  sp.name AS service_plan,
  c.account_balance,
  c.is_active,
  c.installation_date
FROM clients c
LEFT JOIN service_plans sp ON c.service_plan_id = sp.id
WHERE c.municipality_id = $1 AND c.deleted_at IS NULL
ORDER BY c.client_code;
```

**Invoice Export:**
```sql
SELECT 
  i.invoice_number,
  i.invoice_date,
  i.due_date,
  c.client_code,
  c.first_name || ' ' || c.last_name AS client_name,
  i.subtotal,
  i.tax_amount,
  i.total_amount,
  i.amount_paid,
  i.balance_due,
  i.status
FROM invoices i
JOIN clients c ON i.client_id = c.id
WHERE i.municipality_id = $1 AND i.deleted_at IS NULL
ORDER BY i.invoice_date DESC;
```

**Payment Export:**
```sql
SELECT 
  p.payment_number,
  p.payment_date,
  c.client_code,
  c.first_name || ' ' || c.last_name AS client_name,
  i.invoice_number,
  p.amount,
  p.payment_method,
  p.status,
  p.reference_number
FROM payments p
JOIN clients c ON p.client_id = c.id
LEFT JOIN invoices i ON p.invoice_id = i.id
WHERE p.municipality_id = $1
ORDER BY p.payment_date DESC;
```

### CSV Export Implementation

Backend should implement CSV generation using streaming for large datasets:

```javascript
// Example using fast-csv library
const csv = require('fast-csv');
const { pipeline } = require('stream');

async function exportClientsToCSV(municipalityId, res) {
  const query = `
    SELECT client_code, first_name, last_name, email, phone, service_address
    FROM clients
    WHERE municipality_id = $1 AND deleted_at IS NULL
  `;
  
  const client = await pool.connect();
  const stream = client.query(new Cursor(query, [municipalityId]));
  
  res.setHeader('Content-Type', 'text/csv');
  res.setHeader('Content-Disposition', 'attachment; filename=clients.csv');
  
  pipeline(
    stream,
    csv.format({ headers: true }),
    res,
    (err) => {
      client.release();
      if (err) console.error('CSV export error:', err);
    }
  );
}
```

## Backup and Disaster Recovery

### Backup Strategy

1. **Automated daily backups** using provided `backup_db.sh` script
2. **Transaction log archiving** for point-in-time recovery
3. **Off-site backup storage** for disaster recovery
4. **Backup retention policy**:
   - Daily backups: 7 days
   - Weekly backups: 4 weeks
   - Monthly backups: 12 months

### Backup Command

```bash
# Using the provided backup script
cd /path/to/database
bash backup_db.sh

# Or manual pg_dump
pg_dump -h localhost -p 5000 -U appuser -d myapp \
  --clean --if-exists --create \
  > backup_$(date +%Y%m%d_%H%M%S).sql
```

### Restore Command

```bash
# Using the provided restore script
cd /path/to/database
bash restore_db.sh

# Or manual restore
psql -h localhost -p 5000 -U appuser -d postgres < backup_file.sql
```

## Performance Optimization Recommendations

### Query Optimization

1. **Use EXPLAIN ANALYZE** to identify slow queries
2. **Avoid N+1 queries** by using JOINs or batch loading
3. **Use pagination** for large result sets (LIMIT/OFFSET or keyset pagination)
4. **Cache frequently accessed data** (Redis, application-level caching)
5. **Use connection pooling** to reduce connection overhead

### Index Optimization

1. **Monitor index usage**: `pg_stat_user_indexes`
2. **Remove unused indexes** that slow down writes
3. **Consider partial indexes** for commonly filtered columns
4. **Use BRIN indexes** for very large time-series data
5. **Composite indexes** for multi-column WHERE clauses

### Table Partitioning

For very large tables (millions of rows), consider partitioning:

```sql
-- Example: Partition invoices by year
CREATE TABLE invoices_2024 PARTITION OF invoices
  FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE invoices_2025 PARTITION OF invoices
  FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
```

### Maintenance Tasks

Schedule regular maintenance:

```sql
-- Update table statistics
ANALYZE;

-- Reclaim storage and update statistics
VACUUM ANALYZE;

-- Rebuild indexes
REINDEX DATABASE myapp;
```

## Future Enhancements

### Potential Schema Additions

1. **Payment Plans**: Support installment payments and payment schedules
2. **Service Tickets**: Track customer support requests and technician dispatches
3. **Usage Tracking**: Monitor bandwidth consumption per client
4. **Email Notifications**: Queue for automated email sending
5. **API Tokens**: Secure API access with token-based authentication
6. **Activity Log**: Detailed audit trail of all user actions
7. **Document Templates**: Store invoice and report templates
8. **Scheduled Tasks**: Background job tracking and management
9. **Webhooks**: External system integration via webhooks
10. **Multi-currency Support**: International operations support

### Scalability Considerations

1. **Read Replicas**: PostgreSQL streaming replication for read scaling
2. **Connection Pooling**: PgBouncer for connection management
3. **Caching Layer**: Redis for session storage and frequently accessed data
4. **Microservices**: Split into domain-specific services as system grows
5. **Message Queue**: RabbitMQ or AWS SQS for asynchronous processing
6. **CDN**: CloudFront or similar for static file delivery
7. **Load Balancing**: Multiple application servers behind load balancer

## Implementation Checklist

- [ ] Set up PostgreSQL 13+ database
- [ ] Enable required extensions (uuid-ossp, citext)
- [ ] Create enum types
- [ ] Execute table creation scripts in order
- [ ] Create indexes (included in table definitions)
- [ ] Set up triggers for automated fields
- [ ] Implement Row-Level Security policies (if needed)
- [ ] Seed roles and initial data
- [ ] Create database user with appropriate privileges
- [ ] Set up automated backup schedule
- [ ] Configure connection pooling in application
- [ ] Implement migration tracking system
- [ ] Test foreign key constraints and cascades
- [ ] Verify soft delete functionality
- [ ] Set up monitoring and alerting
- [ ] Document connection strings and credentials securely
- [ ] Review security settings with security team
- [ ] Load test with realistic data volumes
- [ ] Plan disaster recovery procedures

## Connection Configuration

Based on the current database setup:

```javascript
// Node.js connection example using pg library
const { Pool } = require('pg');

const pool = new Pool({
  host: 'localhost',
  port: 5000,
  user: 'appuser',
  password: 'dbuser123',
  database: 'myapp',
  max: 20, // Maximum pool size
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Example usage
async function getClientById(clientId) {
  const result = await pool.query(
    'SELECT * FROM clients WHERE id = $1 AND deleted_at IS NULL',
    [clientId]
  );
  return result.rows[0];
}
```

## Conclusion

This database schema provides a robust foundation for the Secure Community Management System. It balances flexibility, performance, and security while supporting all required features including authentication, multi-tenancy, billing, equipment tracking, and service management.

The schema is designed to scale from small deployments to large multi-municipality implementations. Regular monitoring, optimization, and incremental improvements will ensure the system continues to meet evolving business needs.

For questions or clarifications about this schema proposal, please consult the development team or database administrator.

---

**Document Version**: 1.0  
**Last Updated**: 2025  
**Author**: DocumentationAgent  
**Status**: Proposal - Pending Review and Approval
