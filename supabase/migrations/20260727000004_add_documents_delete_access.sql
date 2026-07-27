-- Step 13B: DELETE access on public.documents for owner/admin/manager.

DROP POLICY IF EXISTS documents_delete_manage ON public.documents;
CREATE POLICY documents_delete_manage
  ON public.documents
  FOR DELETE
  TO authenticated
  USING (
    private.has_company_role(
      company_id,
      ARRAY['owner', 'admin', 'manager']::public.company_role[],
      auth.uid()
    )
  );

GRANT DELETE ON TABLE public.documents TO authenticated;
