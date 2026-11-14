-- Ensure every KYC document storage path is gated by an active account.
-- Uploads require a pending KYC request; reads require the path to be attached to that request.
-- Developer review reads require an active Developer account.
drop policy if exists "coach kyc read own document" on storage.objects;
drop policy if exists "coach kyc upload own document" on storage.objects;
drop policy if exists "coach_kyc_read_developer_documents" on storage.objects;
drop policy if exists "player kyc read own document" on storage.objects;
drop policy if exists "player kyc upload own document" on storage.objects;
drop policy if exists "player_kyc_no_client_read" on storage.objects;
drop policy if exists "player_kyc_upload_own_documents" on storage.objects;
drop policy if exists "role_kyc_read_developer_documents" on storage.objects;
drop policy if exists "role_kyc_read_own" on storage.objects;
drop policy if exists "role_kyc_upload_own" on storage.objects;

create policy "coach_kyc_owner_read_attached_active"
on storage.objects for select to authenticated
using (
  bucket_id = 'kyc-documents'
  and owner_id = (select auth.uid())::text
  and public.playpro_account_is_active()
  and exists (
    select 1 from public.identity_verifications iv
    where iv.profile_id = (select auth.uid())
      and iv.subject_type = 'coach'
      and iv.document_storage_paths @> jsonb_build_array(objects.name)
  )
);

create policy "coach_kyc_owner_upload_pending_active"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'kyc-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.playpro_account_is_active()
  and exists (
    select 1 from public.coaches c
    where c.profile_id = (select auth.uid()) and c.is_active = true
  )
  and exists (
    select 1 from public.identity_verifications iv
    where iv.profile_id = (select auth.uid())
      and iv.subject_type = 'coach' and iv.status = 'pending'
  )
);

create policy "coach_kyc_developer_read_attached_active"
on storage.objects for select to authenticated
using (
  bucket_id = 'kyc-documents'
  and public.playpro_account_is_active()
  and public.get_my_role() = 'developer'::public.user_role
  and exists (
    select 1 from public.identity_verifications iv
    where iv.subject_type = 'coach'
      and (storage.foldername(objects.name))[1] = iv.profile_id::text
      and iv.document_storage_paths @> jsonb_build_array(objects.name)
  )
);

create policy "player_kyc_owner_read_attached_active"
on storage.objects for select to authenticated
using (
  bucket_id = 'kyc-documents'
  and owner_id = (select auth.uid())::text
  and public.playpro_account_is_active()
  and exists (
    select 1 from public.identity_verifications iv
    where iv.profile_id = (select auth.uid())
      and iv.subject_type = 'player'
      and iv.document_storage_paths @> jsonb_build_array(objects.name)
  )
);

create policy "player_kyc_owner_upload_pending_active"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'kyc-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.playpro_account_is_active()
  and exists (
    select 1 from public.players p
    where p.profile_id = (select auth.uid()) and p.is_active = true
  )
  and exists (
    select 1 from public.identity_verifications iv
    where iv.profile_id = (select auth.uid())
      and iv.subject_type = 'player' and iv.status = 'pending'
  )
);

create policy "role_kyc_owner_read_attached_active"
on storage.objects for select to authenticated
using (
  bucket_id = 'kyc-documents'
  and owner_id = (select auth.uid())::text
  and public.playpro_account_is_active()
  and exists (
    select 1 from public.identity_verifications iv
    where iv.profile_id = (select auth.uid())
      and iv.subject_type in ('organizer','referee','club_owner')
      and iv.document_storage_paths @> jsonb_build_array(objects.name)
  )
);

create policy "role_kyc_owner_upload_pending_active"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'kyc-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.playpro_account_is_active()
  and exists (
    select 1 from public.identity_verifications iv
    where iv.profile_id = (select auth.uid())
      and iv.subject_type in ('organizer','referee','club_owner')
      and iv.status = 'pending'
  )
);

create policy "role_kyc_developer_read_attached_active"
on storage.objects for select to authenticated
using (
  bucket_id = 'kyc-documents'
  and public.playpro_account_is_active()
  and public.get_my_role() = 'developer'::public.user_role
  and exists (
    select 1 from public.identity_verifications iv
    where iv.subject_type in ('organizer','referee','club_owner')
      and (storage.foldername(objects.name))[1] = iv.profile_id::text
      and iv.document_storage_paths @> jsonb_build_array(objects.name)
  )
);
