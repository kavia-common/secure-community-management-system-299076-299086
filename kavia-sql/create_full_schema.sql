-- =====================================================
-- Secure Community Management System - Full Schema
-- PostgreSQL Database Creation Script
-- =====================================================
-- This script creates the complete database schema including:
-- - Extensions
-- - Enum types
-- - All tables with constraints and indexes
-- - Triggers for automation
-- - Seed data for roles
-- 
-- Execute this script on a fresh database or after DROP statements
-- =====================================================

BEGIN;

-- =====================================================
-- SECTION 1: PostgreSQL Extensions
-- =====================================================

-- UUID generation (PostgreSQL 13+)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- For case-insensitive text operations (emails, usernames)
CREATE EXTENSION IF NOT EXISTS "citext";

-- =====================================================
-- SECTION 2: Custom ENUM Types
-- =====================================================

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

-- =====================================================
-- SECTION 3: Core Tables (in dependency order)
-- =====================================================

-- -----------------------------------------------------
-- Table: roles
-- System roles for authorization and access control
-- -----------------------------------------------------
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

-- -----------------------------------------------------
-- Table: municipalities
-- Community or organizational units managing services
-- -----------------------------------------------------
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

-- -----------------------------------------------------
-- Table: users
-- System users with authentication and authorization
-- -----------------------------------------------------
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

-- -----------------------------------------------------
-- Table: service_plans
-- Available service packages and pricing tiers
-- -----------------------------------------------------
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

-- -----------------------------------------------------
-- Table: clients
-- Service subscribers with account information
-- -----------------------------------------------------
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

-- -----------------------------------------------------
-- Table: routers
-- Network equipment inventory and assignments
-- -----------------------------------------------------
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

-- -----------------------------------------------------
-- Table: invoices
-- Billing documents with header information
-- -----------------------------------------------------
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

-- -----------------------------------------------------
-- Table: invoice_lines
-- Individual charges within invoices
-- -----------------------------------------------------
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

-- -----------------------------------------------------
-- Table: payments
-- Payment transactions linked to invoices
-- -----------------------------------------------------
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

-- -----------------------------------------------------
-- Table: service_cutoffs
-- Service suspension and restoration tracking
-- -----------------------------------------------------
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

-- -----------------------------------------------------
-- Table: file_uploads
-- Metadata for user images and document uploads
-- -----------------------------------------------------
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

-- =====================================================
-- SECTION 4: Triggers and Functions
-- =====================================================

-- -----------------------------------------------------
-- Function: update_updated_at_column
-- Automatically updates the updated_at timestamp
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to all tables with updated_at column
CREATE TRIGGER update_roles_updated_at
  BEFORE UPDATE ON roles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_municipalities_updated_at
  BEFORE UPDATE ON municipalities
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_service_plans_updated_at
  BEFORE UPDATE ON service_plans
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_clients_updated_at
  BEFORE UPDATE ON clients
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_routers_updated_at
  BEFORE UPDATE ON routers
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_invoices_updated_at
  BEFORE UPDATE ON invoices
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_invoice_lines_updated_at
  BEFORE UPDATE ON invoice_lines
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_payments_updated_at
  BEFORE UPDATE ON payments
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_service_cutoffs_updated_at
  BEFORE UPDATE ON service_cutoffs
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_file_uploads_updated_at
  BEFORE UPDATE ON file_uploads
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------
-- Function: update_invoice_totals
-- Automatically recalculates invoice totals when lines change
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION update_invoice_totals()
RETURNS TRIGGER AS $$
DECLARE
  v_invoice_id INTEGER;
  v_subtotal DECIMAL(10, 2);
  v_tax_rate DECIMAL(5, 4);
  v_tax_amount DECIMAL(10, 2);
  v_total_amount DECIMAL(10, 2);
  v_amount_paid DECIMAL(10, 2);
BEGIN
  -- Get the invoice_id from either NEW or OLD record
  v_invoice_id := COALESCE(NEW.invoice_id, OLD.invoice_id);
  
  -- Calculate subtotal from all invoice lines
  SELECT COALESCE(SUM(line_total), 0)
  INTO v_subtotal
  FROM invoice_lines
  WHERE invoice_id = v_invoice_id;
  
  -- Get tax rate and amount paid from invoice
  SELECT tax_rate, amount_paid
  INTO v_tax_rate, v_amount_paid
  FROM invoices
  WHERE id = v_invoice_id;
  
  -- Calculate tax and total
  v_tax_amount := v_subtotal * v_tax_rate;
  v_total_amount := v_subtotal + v_tax_amount;
  
  -- Update invoice with calculated values
  UPDATE invoices
  SET 
    subtotal = v_subtotal,
    tax_amount = v_tax_amount,
    total_amount = v_total_amount,
    balance_due = v_total_amount - v_amount_paid,
    updated_at = CURRENT_TIMESTAMP
  WHERE id = v_invoice_id;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_invoice_totals_trigger
  AFTER INSERT OR UPDATE OR DELETE ON invoice_lines
  FOR EACH ROW
  EXECUTE FUNCTION update_invoice_totals();

-- -----------------------------------------------------
-- Function: update_invoice_payment
-- Updates invoice amount_paid and balance_due when payments are recorded
-- -----------------------------------------------------
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

-- =====================================================
-- SECTION 5: Seed Data
-- =====================================================

-- -----------------------------------------------------
-- Seed: roles
-- Insert default system roles
-- -----------------------------------------------------
INSERT INTO roles (role_name, description, permissions) VALUES
('super_admin', 'Full system access across all municipalities', '{"all": true}'),
('admin', 'Municipality administrator with full access to their municipality', '{"manage_users": true, "manage_clients": true, "manage_billing": true}'),
('manager', 'Service manager with operational access', '{"manage_clients": true, "view_billing": true, "manage_cutoffs": true}'),
('clerk', 'Customer service clerk with limited access', '{"view_clients": true, "create_payments": true}'),
('viewer', 'Read-only access for reporting', '{"view_clients": true, "view_billing": true}'),
('technician', 'Field technician for installations and repairs', '{"view_clients": true, "manage_routers": true, "manage_cutoffs": true}');

-- =====================================================
-- SECTION 6: Schema Completion
-- =====================================================

COMMIT;

-- =====================================================
-- Schema creation completed successfully
-- =====================================================
-- Tables created: 11
-- - roles
-- - municipalities
-- - users
-- - service_plans
-- - clients
-- - routers
-- - invoices
-- - invoice_lines
-- - payments
-- - service_cutoffs
-- - file_uploads
--
-- Triggers created: 14
-- - 11 updated_at triggers (one per table with updated_at)
-- - 1 invoice totals calculation trigger
-- - 1 payment application trigger
--
-- Seed data inserted:
-- - 6 default roles
--
-- Next steps:
-- 1. Create initial municipality record
-- 2. Create admin user (remember to hash password)
-- 3. Configure application connection pool
-- 4. Test foreign key constraints
-- 5. Set up automated backups
-- =====================================================
