-- Consolidate Developer KYC read access into one policy on identity_verifications.
drop policy if exists identity_verification_developer_read_role on public.identity_verifications;
drop policy if exists identity_verification_developer_read_coach on public.identity_verifications;

create policy identity_verification_developer_read_coach
on public.identity_verifications for select to authenticated
using (
  subject_type in ('coach','club_owner','organizer','referee')
  and (select public.get_my_role())='developer'::public.user_role
);
