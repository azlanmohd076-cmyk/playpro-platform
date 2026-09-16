-- PlayPro private KYC storage policy for organizer/referee/club-owner identities.
-- Applied to production playpro2 as role_kyc_storage_policies.

drop policy if exists role_kyc_upload_own on storage.objects;
create policy role_kyc_upload_own on storage.objects for insert to authenticated with check (
  bucket_id='kyc-documents' and (storage.foldername(name))[1]=auth.uid()::text and exists(
    select 1 from public.identity_verifications iv where iv.profile_id=auth.uid() and iv.subject_type in ('organizer','referee','club_owner') and iv.status='pending'
  )
);

drop policy if exists role_kyc_read_own on storage.objects;
create policy role_kyc_read_own on storage.objects for select to authenticated using (
  bucket_id='kyc-documents' and owner_id=auth.uid()::text and exists(
    select 1 from public.identity_verifications iv where iv.profile_id=auth.uid() and iv.subject_type in ('organizer','referee','club_owner')
  )
);
