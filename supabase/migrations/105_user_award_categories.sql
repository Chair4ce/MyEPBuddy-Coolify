-- Migration: User Award Categories
-- Allows users to maintain their own custom list of award categories
-- Default system categories are still available and cannot be deleted

-- ============================================================================
-- TABLE: user_award_categories
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_award_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- Category identifier (lowercase, underscored for internal use)
  category_key TEXT NOT NULL,
  -- Display label for the category
  label TEXT NOT NULL,
  -- Optional description
  description TEXT,
  -- Whether this is a default category that was copied for the user
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  -- Display order for sorting
  display_order INTEGER NOT NULL DEFAULT 0,
  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  -- Each user can only have one category with a given key
  CONSTRAINT user_award_categories_user_key_unique UNIQUE (user_id, category_key)
);

-- Index for fast lookups by user
CREATE INDEX IF NOT EXISTS idx_user_award_categories_user_id 
  ON public.user_award_categories(user_id);

-- Index for ordering
CREATE INDEX IF NOT EXISTS idx_user_award_categories_display_order 
  ON public.user_award_categories(user_id, display_order);

-- ============================================================================
-- TRIGGER: Update updated_at timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_user_award_categories_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_user_award_categories_updated_at ON public.user_award_categories;
CREATE TRIGGER trigger_user_award_categories_updated_at
  BEFORE UPDATE ON public.user_award_categories
  FOR EACH ROW
  EXECUTE FUNCTION public.update_user_award_categories_updated_at();

-- ============================================================================
-- FUNCTION: Initialize default categories for a user
-- Called when user first accesses award categories feature
-- ============================================================================

CREATE OR REPLACE FUNCTION public.initialize_user_award_categories(p_user_id UUID)
RETURNS SETOF public.user_award_categories
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only insert if user has no categories yet
  IF NOT EXISTS (SELECT 1 FROM public.user_award_categories WHERE user_id = p_user_id) THEN
    INSERT INTO public.user_award_categories (user_id, category_key, label, is_default, display_order)
    VALUES
      (p_user_id, 'snco', 'SNCO', TRUE, 1),
      (p_user_id, 'nco', 'NCO', TRUE, 2),
      (p_user_id, 'amn', 'Airman', TRUE, 3),
      (p_user_id, 'jr_tech', 'Junior Technician', TRUE, 4),
      (p_user_id, 'sr_tech', 'Senior Technician', TRUE, 5),
      (p_user_id, 'innovation', 'Innovation', TRUE, 6),
      (p_user_id, 'volunteer', 'Volunteer', TRUE, 7),
      (p_user_id, 'team', 'Team', TRUE, 8);
  END IF;
  
  RETURN QUERY SELECT * FROM public.user_award_categories 
    WHERE user_id = p_user_id 
    ORDER BY display_order, created_at;
END;
$$;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.user_award_categories ENABLE ROW LEVEL SECURITY;

-- Users can only view their own categories
CREATE POLICY "Users can view own award categories"
  ON public.user_award_categories
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Users can insert their own categories
CREATE POLICY "Users can insert own award categories"
  ON public.user_award_categories
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Users can update their own categories
CREATE POLICY "Users can update own award categories"
  ON public.user_award_categories
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Users can delete their own categories
CREATE POLICY "Users can delete own award categories"
  ON public.user_award_categories
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_award_categories TO authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_user_award_categories(UUID) TO authenticated;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE public.user_award_categories IS 'User-customizable award categories for AF Form 1206 packages';
COMMENT ON COLUMN public.user_award_categories.category_key IS 'Unique identifier for the category (lowercase, underscored)';
COMMENT ON COLUMN public.user_award_categories.label IS 'Display label shown in the UI';
COMMENT ON COLUMN public.user_award_categories.is_default IS 'Whether this category was copied from the default set';
COMMENT ON FUNCTION public.initialize_user_award_categories(UUID) IS 'Initializes default award categories for a user if they have none';
