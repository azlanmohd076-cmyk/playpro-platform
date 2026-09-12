-- PLAYPRO — Private KYC storage upload policy
BEGIN;
DROP POLICY IF EXISTS "player_kyc_upload_own_documents" ON storage.objects;
CREATE POLICY "player_kyc_upload_own_documents"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'kyc-documents'
  AND (storage.foldername(name))[1] = (select auth.uid()::text)
);
DROP POLICY IF EXISTS "player_kyc_no_client_read" ON storage.objects;
CREATE POLICY "player_kyc_no_client_read"
ON storage.objects FOR SELECT TO authenticated
USING (false);
COMMIT;
