-- Role KYC Storage must only accept/read paths declared by the user's pending request.
drop policy if exists role_kyc_upload_own on storage.objects;
create policy role_kyc_upload_own
on storage.objects for insert to authenticated
with check (
  bucket_id='kyc-documents'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and exists (
    select 1 from public.identity_verifications iv
    where iv.profile_id=(select auth.uid())
      and iv.subject_type in ('organizer','referee','club_owner')
      and iv.status='pending'
      and iv.document_storage_paths @> jsonb_build_array(name)
  )
);

drop policy if exists role_kyc_read_own on storage.objects;
create policy role_kyc_read_own
on storage.objects for select to authenticated
using (
  bucket_id='kyc-documents'
  and owner_id=(select auth.uid())::text
  and exists (
    select 1 from public.identity_verifications iv
    where iv.profile_id=(select auth.uid())
      and iv.subject_type in ('organizer','referee','club_owner')
      and iv.document_storage_paths @> jsonb_build_array(name)
  )
);
