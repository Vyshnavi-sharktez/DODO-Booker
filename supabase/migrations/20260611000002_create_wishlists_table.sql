-- Create wishlists table with duplicate prevention
CREATE TABLE IF NOT EXISTS public.wishlists (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  service_id  UUID NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT wishlists_customer_service_unique UNIQUE (customer_id, service_id)
);

CREATE INDEX IF NOT EXISTS wishlists_customer_id_idx ON public.wishlists (customer_id);
