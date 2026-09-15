begin;

create or replace function public.playpro_request_coach_certification(
  p_track text,
  p_level integer,
  p_note text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_track not in ('player_assessment_authority','coach_attribute_certification') then raise exception 'INVALID_TRACK'; end if;
  if p_level < 1 or p_level > 5 then raise exception 'INVALID_LEVEL'; end if;
  if not exists (select 1 from public.coaches where profile_id=auth.uid()) then raise exception 'COACH_PROFILE_REQUIRED'; end if;
  if not exists (select 1 from public.coaches where profile_id=auth.uid() and verification_status='verified') then raise exception 'COACH_KYC_REQUIRED'; end if;
  if exists (select 1 from public.coach_certification_requests where coach_id=(select id from public.coaches where profile_id=auth.uid()) and track=p_track and requested_level=p_level and status in ('pending','approved')) then
    select id into v_id from public.coach_certification_requests where coach_id=(select id from public.coaches where profile_id=auth.uid()) and track=p_track and requested_level=p_level and status in ('pending','approved') order by created_at desc limit 1;
    return v_id;
  end if;
  insert into public.coach_certification_requests(coach_id,track,requested_level,note,status,created_at)
  values((select id from public.coaches where profile_id=auth.uid()),p_track,p_level,p_note,'pending',now()) returning id into v_id;
  return v_id;
end $$;

revoke all on function public.playpro_request_coach_certification(text,integer,text) from public;
grant execute on function public.playpro_request_coach_certification(text,integer,text) to authenticated;

commit;
