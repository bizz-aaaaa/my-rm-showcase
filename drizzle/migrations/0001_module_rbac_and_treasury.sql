
CREATE TABLE public.churches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  conference text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.churches TO service_role;
GRANT SELECT ON public.churches TO anon, authenticated;
ALTER TABLE public.churches ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Churches viewable" ON public.churches FOR SELECT USING (true);
INSERT INTO public.churches (name, conference) VALUES ('SDA Chuo Kikuu', 'Default');

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS church_id uuid REFERENCES public.churches(id);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
UPDATE public.profiles SET church_id = (SELECT id FROM public.churches WHERE name='SDA Chuo Kikuu') WHERE church_id IS NULL;

CREATE TABLE public.rbac_roles (
  key text PRIMARY KEY,
  name text NOT NULL,
  description text NOT NULL DEFAULT '',
  is_protected boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0
);
CREATE TABLE public.rbac_permissions (
  key text PRIMARY KEY,
  module text NOT NULL,
  description text NOT NULL DEFAULT ''
);
CREATE TABLE public.rbac_role_permissions (
  role_key text NOT NULL REFERENCES public.rbac_roles(key) ON DELETE CASCADE,
  permission_key text NOT NULL REFERENCES public.rbac_permissions(key) ON DELETE CASCADE,
  PRIMARY KEY (role_key, permission_key)
);
CREATE TABLE public.rbac_user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role_key text NOT NULL REFERENCES public.rbac_roles(key) ON DELETE CASCADE,
  church_id uuid REFERENCES public.churches(id),
  is_active boolean NOT NULL DEFAULT true,
  assigned_by uuid REFERENCES public.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX rbac_user_roles_uniq ON public.rbac_user_roles (profile_id, role_key, COALESCE(church_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE TABLE public.rbac_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid,
  action text NOT NULL,
  target_profile_id uuid,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.treasury_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id uuid NOT NULL REFERENCES public.churches(id),
  name text NOT NULL,
  account_type text NOT NULL DEFAULT 'bank',
  is_restricted boolean NOT NULL DEFAULT false,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.treasury_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id uuid NOT NULL REFERENCES public.churches(id),
  account_id uuid REFERENCES public.treasury_accounts(id),
  source text NOT NULL DEFAULT 'manual',
  contribution_id uuid UNIQUE REFERENCES public.contributions(id),
  category text NOT NULL DEFAULT 'Offering',
  amount numeric NOT NULL,
  description text,
  receipt_url text,
  status text NOT NULL DEFAULT 'pending',
  recorded_by uuid,
  verified_by uuid,
  verified_at timestamptz,
  txn_date date NOT NULL DEFAULT current_date,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.treasury_expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id uuid NOT NULL REFERENCES public.churches(id),
  account_id uuid REFERENCES public.treasury_accounts(id),
  category text NOT NULL DEFAULT 'General',
  amount numeric NOT NULL,
  description text,
  receipt_url text,
  status text NOT NULL DEFAULT 'pending',
  created_by uuid,
  approved_by uuid,
  approved_at timestamptz,
  expense_date date NOT NULL DEFAULT current_date,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.treasury_remittances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id uuid NOT NULL REFERENCES public.churches(id),
  recipient text NOT NULL DEFAULT 'Conference',
  period text NOT NULL,
  amount numeric NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  created_by uuid,
  approved_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.treasury_audit_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  church_id uuid NOT NULL REFERENCES public.churches(id),
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  note text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  flagged_by uuid,
  resolved_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['rbac_roles','rbac_permissions','rbac_role_permissions','rbac_user_roles','rbac_audit_logs','treasury_accounts','treasury_transactions','treasury_expenses','treasury_remittances','treasury_audit_flags'] LOOP
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

INSERT INTO public.rbac_roles (key,name,description,is_protected,sort_order) VALUES
 ('full_admin','Full Admin','Unrestricted access to every module, users and settings.',true,0),
 ('rm_admin','RM Admin','Manages the Resource Mobilization (offering collection) module only.',false,1),
 ('treasurer','Treasurer','Manages church finances in the Treasury module.',false,2),
 ('assistant_treasurer','Assistant Treasurer','Records manual collections and assists reconciliation.',false,3),
 ('treasury_auditor','Treasury Auditor','Read-only review of treasury records; can flag discrepancies.',false,4);

INSERT INTO public.rbac_permissions (key,module,description) VALUES
 ('rm.view','rm','Access RM module'),
 ('rm.dashboard.view','rm','View RM dashboard'),
 ('rm.collections.view','rm','View online collections'),
 ('rm.collections.manage','rm','Manage collection configurations'),
 ('rm.categories.view','rm','View offering categories'),
 ('rm.categories.manage','rm','Manage offering categories'),
 ('rm.campaigns.view','rm','View campaigns'),
 ('rm.campaigns.manage','rm','Manage campaigns'),
 ('rm.reports.view','rm','View RM reports'),
 ('rm.settings.manage','rm','Manage RM settings'),
 ('treasury.view','treasury','Access Treasury module'),
 ('treasury.dashboard.view','treasury','View treasury dashboard'),
 ('treasury.transactions.view','treasury','View transactions'),
 ('treasury.transactions.create','treasury','Record manual collections'),
 ('treasury.transactions.edit','treasury','Edit unverified transactions'),
 ('treasury.transactions.verify','treasury','Verify transactions'),
 ('treasury.categories.view','treasury','View categories'),
 ('treasury.categories.manage','treasury','Manage categories'),
 ('treasury.accounts.view','treasury','View financial accounts'),
 ('treasury.accounts.manage','treasury','Manage financial accounts'),
 ('treasury.expenses.view','treasury','View expenses'),
 ('treasury.expenses.create','treasury','Record expenses'),
 ('treasury.expenses.approve','treasury','Approve expenses'),
 ('treasury.remittances.view','treasury','View remittances'),
 ('treasury.remittances.manage','treasury','Create and approve remittances'),
 ('treasury.reconciliation.manage','treasury','Reconcile records'),
 ('treasury.reports.view','treasury','View financial reports'),
 ('treasury.reports.export','treasury','Export financial reports'),
 ('treasury.settings.manage','treasury','Manage treasury settings'),
 ('treasury.audit.view','treasury','View audit logs and flag discrepancies');

INSERT INTO public.rbac_role_permissions (role_key, permission_key)
SELECT 'full_admin', key FROM public.rbac_permissions;
INSERT INTO public.rbac_role_permissions (role_key, permission_key)
SELECT 'rm_admin', key FROM public.rbac_permissions WHERE module='rm';
INSERT INTO public.rbac_role_permissions (role_key, permission_key)
SELECT 'treasurer', key FROM public.rbac_permissions WHERE module='treasury' AND key NOT IN ('treasury.settings.manage');
INSERT INTO public.rbac_role_permissions (role_key, permission_key) VALUES
 ('assistant_treasurer','treasury.view'),('assistant_treasurer','treasury.dashboard.view'),
 ('assistant_treasurer','treasury.transactions.view'),('assistant_treasurer','treasury.transactions.create'),
 ('assistant_treasurer','treasury.categories.view'),('assistant_treasurer','treasury.reconciliation.manage'),
 ('assistant_treasurer','treasury.reports.view'),('assistant_treasurer','treasury.expenses.view'),
 ('treasury_auditor','treasury.view'),('treasury_auditor','treasury.dashboard.view'),
 ('treasury_auditor','treasury.transactions.view'),('treasury_auditor','treasury.expenses.view'),
 ('treasury_auditor','treasury.accounts.view'),('treasury_auditor','treasury.remittances.view'),
 ('treasury_auditor','treasury.reports.view'),('treasury_auditor','treasury.reports.export'),
 ('treasury_auditor','treasury.audit.view'),('treasury_auditor','treasury.categories.view');

-- Existing admins/super admins become global Full Admins (backward compatible)
INSERT INTO public.rbac_user_roles (profile_id, role_key, church_id)
SELECT DISTINCT user_id, 'full_admin', NULL::uuid FROM public.user_roles WHERE role IN ('admin','super_admin')
ON CONFLICT DO NOTHING;

-- Import confirmed RM online payments into Treasury automatically (one row per contribution)
CREATE OR REPLACE FUNCTION public.import_contribution_to_treasury()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cid uuid;
BEGIN
  IF NEW.status = 'completed' THEN
    SELECT COALESCE(p.church_id, (SELECT id FROM public.churches ORDER BY created_at LIMIT 1))
      INTO cid FROM (SELECT 1) x LEFT JOIN public.profiles p ON p.id = NEW.user_id;
    INSERT INTO public.treasury_transactions (church_id, source, contribution_id, category, amount, description, status, verified_at, txn_date)
    VALUES (cid, 'rm_online', NEW.id, 'Online Offering', NEW.amount, 'Imported from RM: ' || COALESCE(NEW.reference, NEW.id::text), 'verified', now(), NEW.created_at::date)
    ON CONFLICT (contribution_id) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER contributions_to_treasury AFTER INSERT OR UPDATE OF status ON public.contributions
FOR EACH ROW EXECUTE FUNCTION public.import_contribution_to_treasury();

INSERT INTO public.treasury_transactions (church_id, source, contribution_id, category, amount, description, status, verified_at, txn_date)
SELECT COALESCE(p.church_id, (SELECT id FROM public.churches ORDER BY created_at LIMIT 1)), 'rm_online', c.id, 'Online Offering', c.amount,
       'Imported from RM: ' || COALESCE(c.reference, c.id::text), 'verified', now(), c.created_at::date
FROM public.contributions c LEFT JOIN public.profiles p ON p.id = c.user_id
WHERE c.status = 'completed'
ON CONFLICT (contribution_id) DO NOTHING;
