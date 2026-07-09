-- DUSUQ — Supabase Database Schema & Multi-Tenancy Rules

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TABLES SETUP
-- ─────────────────────────────────────────────────────────────────────────────

-- Organizations Table
CREATE TABLE public.organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  owner_uid UUID, -- references auth.users(id)
  plan_tier TEXT NOT NULL DEFAULT 'trial',
  animal_count INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now()),
  currency TEXT NOT NULL DEFAULT 'PKR',
  default_language TEXT NOT NULL DEFAULT 'en',
  
  -- Aggregates (kept up to date by triggers)
  total_milk_liters NUMERIC NOT NULL DEFAULT 0,
  net_revenue NUMERIC NOT NULL DEFAULT 0,
  total_income NUMERIC NOT NULL DEFAULT 0,
  total_expense NUMERIC NOT NULL DEFAULT 0,
  lactating_count INTEGER NOT NULL DEFAULT 0,
  active_farmer_count INTEGER NOT NULL DEFAULT 0,
  milk_by_month JSONB NOT NULL DEFAULT '{}'::jsonb,
  last_updated TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Profiles Table (Linked to auth.users)
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY, -- Matches auth.users.id
  org_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
  role TEXT NOT NULL DEFAULT 'Farmer', -- 'SuperAdmin' | 'OrgAdmin' | 'Farmer'
  email TEXT NOT NULL,
  phone TEXT,
  display_name TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active', -- 'active' | 'invited' | 'disabled'
  invited_by UUID,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now()),
  last_login_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Animals Table
CREATE TABLE public.animals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  tag_number TEXT NOT NULL,
  breed TEXT NOT NULL DEFAULT '',
  sex TEXT NOT NULL DEFAULT 'Female',
  status TEXT NOT NULL DEFAULT 'Active',
  lactation_status TEXT NOT NULL DEFAULT 'Dry', -- 'Lactating' | 'Dry' | etc.
  name TEXT,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Milk Records Table
CREATE TABLE public.milk_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  animal_id UUID NOT NULL REFERENCES public.animals(id) ON DELETE CASCADE,
  date TIMESTAMP WITH TIME ZONE NOT NULL,
  quantity NUMERIC NOT NULL, -- Liters
  session TEXT, -- 'Morning' | 'Evening' | etc.
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Breeding Records Table
CREATE TABLE public.breeding_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  animal_id UUID NOT NULL REFERENCES public.animals(id) ON DELETE CASCADE,
  date TIMESTAMP WITH TIME ZONE NOT NULL,
  event TEXT NOT NULL, -- enum name from client
  method TEXT,
  bull_sire_id TEXT,
  technician_name TEXT,
  expected_calving_date TIMESTAMP WITH TIME ZONE,
  notes TEXT,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Feed Expenses Table
CREATE TABLE public.feed_expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  cost NUMERIC NOT NULL, -- Total cost
  quantity NUMERIC NOT NULL,
  unit TEXT NOT NULL DEFAULT 'kg',
  supplier TEXT,
  date TIMESTAMP WITH TIME ZONE NOT NULL,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Medical Records Table
CREATE TABLE public.medical_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  animal_id UUID NOT NULL REFERENCES public.animals(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  description TEXT,
  medicine TEXT,
  dosage TEXT,
  vet_name TEXT,
  cost NUMERIC,
  date TIMESTAMP WITH TIME ZONE NOT NULL,
  follow_up_date TIMESTAMP WITH TIME ZONE,
  notes TEXT,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Finance Records Table
CREATE TABLE public.finance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL,
  type TEXT NOT NULL, -- 'Income' | 'Expense'
  category TEXT NOT NULL,
  description TEXT,
  date TIMESTAMP WITH TIME ZONE NOT NULL,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. TRIGGER FUNCTIONS (AUTOMATIC AGGREGATIONS)
-- ─────────────────────────────────────────────────────────────────────────────

-- Animal aggregate trigger
CREATE OR REPLACE FUNCTION public.on_animal_write()
RETURNS TRIGGER AS $$
DECLARE
  org_ref UUID;
  count_delta INTEGER := 0;
  lactating_delta INTEGER := 0;
BEGIN
  IF (TG_OP = 'INSERT') THEN
    org_ref := NEW.org_id;
    count_delta := 1;
    IF NEW.lactation_status = 'Lactating' THEN
      lactating_delta := 1;
    END IF;
  ELSIF (TG_OP = 'DELETE') THEN
    org_ref := OLD.org_id;
    count_delta := -1;
    IF OLD.lactation_status = 'Lactating' THEN
      lactating_delta := -1;
    END IF;
  ELSIF (TG_OP = 'UPDATE') THEN
    org_ref := NEW.org_id;
    IF (OLD.lactation_status = 'Lactating' AND NEW.lactation_status <> 'Lactating') THEN
      lactating_delta := -1;
    ELSIF (OLD.lactation_status <> 'Lactating' AND NEW.lactation_status = 'Lactating') THEN
      lactating_delta := 1;
    END IF;
  END IF;
  
  IF (count_delta <> 0 OR lactating_delta <> 0) THEN
    UPDATE public.organizations
    SET 
      animal_count = animal_count + count_delta,
      lactating_count = lactating_count + lactating_delta,
      last_updated = now()
    WHERE id = org_ref;
  END IF;
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trigger_animal_write
  AFTER INSERT OR UPDATE OR DELETE ON public.animals
  FOR EACH ROW EXECUTE FUNCTION public.on_animal_write();


-- Milk record aggregate trigger
CREATE OR REPLACE FUNCTION public.on_milk_record_write()
RETURNS TRIGGER AS $$
DECLARE
  org_ref UUID;
  liters_delta NUMERIC := 0;
  old_month_key TEXT;
  new_month_key TEXT;
  old_qty NUMERIC := 0;
  new_qty NUMERIC := 0;
BEGIN
  IF (TG_OP = 'INSERT') THEN
    org_ref := NEW.org_id;
    liters_delta := NEW.quantity;
    new_month_key := to_char(NEW.date, 'YYYY-MM');
    
    UPDATE public.organizations
    SET 
      total_milk_liters = total_milk_liters + liters_delta,
      milk_by_month = jsonb_set(
        milk_by_month,
        ARRAY[new_month_key],
        to_jsonb(coalesce((milk_by_month->>new_month_key)::numeric, 0) + liters_delta)
      ),
      last_updated = now()
    WHERE id = org_ref;
    
  ELSIF (TG_OP = 'DELETE') THEN
    org_ref := OLD.org_id;
    liters_delta := -OLD.quantity;
    old_month_key := to_char(OLD.date, 'YYYY-MM');
    
    UPDATE public.organizations
    SET 
      total_milk_liters = total_milk_liters + liters_delta,
      milk_by_month = jsonb_set(
        milk_by_month,
        ARRAY[old_month_key],
        to_jsonb(coalesce((milk_by_month->>old_month_key)::numeric, 0) + liters_delta)
      ),
      last_updated = now()
    WHERE id = org_ref;
    
  ELSIF (TG_OP = 'UPDATE') THEN
    org_ref := NEW.org_id;
    old_qty := OLD.quantity;
    new_qty := NEW.quantity;
    liters_delta := new_qty - old_qty;
    old_month_key := to_char(OLD.date, 'YYYY-MM');
    new_month_key := to_char(NEW.date, 'YYYY-MM');
    
    IF (old_month_key = new_month_key) THEN
      UPDATE public.organizations
      SET 
        total_milk_liters = total_milk_liters + liters_delta,
        milk_by_month = jsonb_set(
          milk_by_month,
          ARRAY[new_month_key],
          to_jsonb(coalesce((milk_by_month->>new_month_key)::numeric, 0) + liters_delta)
        ),
        last_updated = now()
      WHERE id = org_ref;
    ELSE
      UPDATE public.organizations
      SET 
        total_milk_liters = total_milk_liters + liters_delta,
        milk_by_month = jsonb_set(
          jsonb_set(
            milk_by_month,
            ARRAY[old_month_key],
            to_jsonb(coalesce((milk_by_month->>old_month_key)::numeric, 0) - old_qty)
          ),
          ARRAY[new_month_key],
          to_jsonb(coalesce((milk_by_month->>new_month_key)::numeric, 0) + new_qty)
        ),
        last_updated = now()
      WHERE id = org_ref;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trigger_milk_write
  AFTER INSERT OR UPDATE OR DELETE ON public.milk_records
  FOR EACH ROW EXECUTE FUNCTION public.on_milk_record_write();


-- Finance record aggregate trigger
CREATE OR REPLACE FUNCTION public.on_finance_record_write()
RETURNS TRIGGER AS $$
DECLARE
  org_ref UUID;
  net_delta NUMERIC := 0;
  income_delta NUMERIC := 0;
  expense_delta NUMERIC := 0;
  old_signed NUMERIC := 0;
  new_signed NUMERIC := 0;
  old_income NUMERIC := 0;
  new_income NUMERIC := 0;
  old_expense NUMERIC := 0;
  new_expense NUMERIC := 0;
BEGIN
  IF (TG_OP = 'INSERT') THEN
    org_ref := NEW.org_id;
    IF NEW.type = 'Income' THEN
      new_signed := NEW.amount;
      new_income := NEW.amount;
    ELSE
      new_signed := -NEW.amount;
      new_expense := NEW.amount;
    END IF;
    net_delta := new_signed;
    income_delta := new_income;
    expense_delta := new_expense;
  ELSIF (TG_OP = 'DELETE') THEN
    org_ref := OLD.org_id;
    IF OLD.type = 'Income' THEN
      old_signed := OLD.amount;
      old_income := OLD.amount;
    ELSE
      old_signed := -OLD.amount;
      old_expense := OLD.amount;
    END IF;
    net_delta := -old_signed;
    income_delta := -old_income;
    expense_delta := -old_expense;
  ELSIF (TG_OP = 'UPDATE') THEN
    org_ref := NEW.org_id;
    IF OLD.type = 'Income' THEN
      old_signed := OLD.amount;
      old_income := OLD.amount;
    ELSE
      old_signed := -OLD.amount;
      old_expense := OLD.amount;
    END IF;
    IF NEW.type = 'Income' THEN
      new_signed := NEW.amount;
      new_income := NEW.amount;
    ELSE
      new_signed := -NEW.amount;
      new_expense := NEW.amount;
    END IF;
    net_delta := new_signed - old_signed;
    income_delta := new_income - old_income;
    expense_delta := new_expense - old_expense;
  END IF;
  
  IF (net_delta <> 0 OR income_delta <> 0 OR expense_delta <> 0) THEN
    UPDATE public.organizations
    SET 
      net_revenue = net_revenue + net_delta,
      total_income = total_income + income_delta,
      total_expense = total_expense + expense_delta,
      last_updated = now()
    WHERE id = org_ref;
  END IF;
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trigger_finance_write
  AFTER INSERT OR UPDATE OR DELETE ON public.finance_records
  FOR EACH ROW EXECUTE FUNCTION public.on_finance_record_write();


-- Profile count aggregate trigger
CREATE OR REPLACE FUNCTION public.on_profile_write()
RETURNS TRIGGER AS $$
DECLARE
  org_ref UUID;
  was_active BOOLEAN := FALSE;
  is_active BOOLEAN := FALSE;
  delta INTEGER := 0;
BEGIN
  IF (TG_OP = 'INSERT') THEN
    org_ref := NEW.org_id;
    IF (NEW.role = 'Farmer' AND NEW.status = 'active') THEN
      delta := 1;
    END IF;
  ELSIF (TG_OP = 'DELETE') THEN
    org_ref := OLD.org_id;
    IF (OLD.role = 'Farmer' AND OLD.status = 'active') THEN
      delta := -1;
    END IF;
  ELSIF (TG_OP = 'UPDATE') THEN
    org_ref := NEW.org_id;
    was_active := (OLD.role = 'Farmer' AND OLD.status = 'active');
    is_active := (NEW.role = 'Farmer' AND NEW.status = 'active');
    IF (was_active AND NOT is_active) THEN
      delta := -1;
    ELSIF (NOT was_active AND is_active) THEN
      delta := 1;
    END IF;
  END IF;
  
  IF (delta <> 0 AND org_ref IS NOT NULL) THEN
    UPDATE public.organizations
    SET 
      active_farmer_count = active_farmer_count + delta,
      last_updated = now()
    WHERE id = org_ref;
  END IF;
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trigger_profile_write
  AFTER INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.on_profile_write();


-- Sync profile automatically on auth.users changes
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = NEW.id) THEN
    INSERT INTO public.profiles (id, email, phone, display_name, role, status)
    VALUES (
      NEW.id,
      NEW.email,
      NEW.phone,
      coalesce(NEW.raw_user_meta_data->>'display_name', NEW.email, ''),
      coalesce(NEW.raw_user_meta_data->>'role', 'Farmer'),
      'active'
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. DATABASE FUNCTIONS (RPC)
-- ─────────────────────────────────────────────────────────────────────────────

-- Atomic signup for organization admin + organization creation
CREATE OR REPLACE FUNCTION public.sign_up_org_admin(
  org_name TEXT,
  display_name TEXT
)
RETURNS JSONB
AS $$
DECLARE
  new_org_id UUID;
  user_email TEXT;
  user_phone TEXT;
BEGIN
  SELECT email, phone INTO user_email, user_phone
  FROM auth.users
  WHERE id = auth.uid();
  
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in before completing signup.';
  END IF;
  
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND org_id IS NOT NULL) THEN
    RAISE EXCEPTION 'This account is already linked to an organization.';
  END IF;

  INSERT INTO public.organizations (name, owner_uid, plan_tier, status)
  VALUES (org_name, auth.uid(), 'trial', 'active')
  RETURNING id INTO new_org_id;

  INSERT INTO public.profiles (id, org_id, role, email, phone, display_name, status)
  VALUES (auth.uid(), new_org_id, 'OrgAdmin', user_email, user_phone, display_name, 'active')
  ON CONFLICT (id) DO UPDATE
  SET 
    org_id = EXCLUDED.org_id,
    role = EXCLUDED.role,
    display_name = EXCLUDED.display_name,
    status = EXCLUDED.status;

  RETURN jsonb_build_object('orgId', new_org_id, 'role', 'OrgAdmin');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- ─────────────────────────────────────────────────────────────────────────────

-- Enable RLS on all tables
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.animals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.milk_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.breeding_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feed_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medical_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_records ENABLE ROW LEVEL SECURITY;

-- Profiles Policies
CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'SuperAdmin');

CREATE POLICY "OrgAdmins can view profiles in their own org"
  ON public.profiles FOR SELECT
  USING ((SELECT org_id FROM public.profiles WHERE id = auth.uid()) = org_id AND (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'OrgAdmin');

CREATE POLICY "OrgAdmins can insert/update profiles in their own org"
  ON public.profiles FOR ALL
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'SuperAdmin' OR
    ((SELECT org_id FROM public.profiles WHERE id = auth.uid()) = org_id AND (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'OrgAdmin')
  );

-- Organizations Policies
CREATE POLICY "Users can view their linked organization"
  ON public.organizations FOR SELECT
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'SuperAdmin' OR
    (SELECT org_id FROM public.profiles WHERE id = auth.uid()) = id
  );

CREATE POLICY "OrgAdmins can update their organization"
  ON public.organizations FOR UPDATE
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'SuperAdmin' OR
    (owner_uid = auth.uid() AND (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'OrgAdmin')
  );

-- Generic Org-scoped RLS policies helper creator
-- Applied to: animals, milk_records, breeding_records, feed_expenses, medical_records, finance_records

CREATE POLICY "Animals org access" ON public.animals FOR ALL USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'SuperAdmin' OR
  (SELECT org_id FROM public.profiles WHERE id = auth.uid()) = org_id
);

CREATE POLICY "Milk records org access" ON public.milk_records FOR ALL USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'SuperAdmin' OR
  (SELECT org_id FROM public.profiles WHERE id = auth.uid()) = org_id
);

CREATE POLICY "Breeding records org access" ON public.breeding_records FOR ALL USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'SuperAdmin' OR
  (SELECT org_id FROM public.profiles WHERE id = auth.uid()) = org_id
);

CREATE POLICY "Feed expenses org access" ON public.feed_expenses FOR ALL USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'SuperAdmin' OR
  (SELECT org_id FROM public.profiles WHERE id = auth.uid()) = org_id
);

CREATE POLICY "Medical records org access" ON public.medical_records FOR ALL USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'SuperAdmin' OR
  (SELECT org_id FROM public.profiles WHERE id = auth.uid()) = org_id
);

CREATE POLICY "Finance records org access" ON public.finance_records FOR ALL USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'SuperAdmin' OR
  (SELECT org_id FROM public.profiles WHERE id = auth.uid()) = org_id
);
