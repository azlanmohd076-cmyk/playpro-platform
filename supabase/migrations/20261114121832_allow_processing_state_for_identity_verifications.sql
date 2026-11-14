alter table public.identity_verifications
  drop constraint if exists identity_verifications_status_check;
alter table public.identity_verifications
  add constraint identity_verifications_status_check
  check (status = any (array['pending'::text,'processing'::text,'verified'::text,'rejected'::text,'cancelled'::text]));
