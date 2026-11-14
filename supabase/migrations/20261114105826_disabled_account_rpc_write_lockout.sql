do $block$
declare
  r record;
  v_def text;
  v_pos integer;
  v_count integer := 0;
begin
  for r in
    select p.oid, p.proname, pg_get_functiondef(p.oid) as definition
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    join pg_language l on l.oid=p.prolang
    where n.nspname='public'
      and p.prosecdef
      and l.lanname='plpgsql'
      and p.prorettype::regtype::text <> 'trigger'
      and has_function_privilege('authenticated',p.oid,'EXECUTE')
      and p.proname <> 'ensure_profile_after_signup'
      and p.prosrc not ilike '%playpro_require_active_account%'
      and (
        lower(p.prosrc) like '%insert into%'
        or lower(p.prosrc) like '%update %'
        or lower(p.prosrc) like '%delete from%'
      )
  loop
    v_def := r.definition;
    v_pos := strpos(lower(v_def), 'begin');
    if v_pos = 0 then
      raise exception 'Could not safely locate BEGIN in function %', r.proname;
    end if;
    v_def := overlay(
      v_def placing
      'BEGIN PERFORM public.playpro_require_active_account();'
      from v_pos for 5
    );
    execute v_def;
    v_count := v_count + 1;
  end loop;
  raise notice 'Added active-account guard to % mutating SECURITY DEFINER functions', v_count;
end;
$block$;

create or replace function public.get_assessment_workspace()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_level smallint;
  v_players jsonb;
begin
  perform public.playpro_require_active_account();
  if not exists (
    select 1 from public.profile_role_profiles rp
    where rp.profile_id=v_uid and rp.role_code='coach' and rp.is_active=true
  ) or not exists (
    select 1 from public.coach_accreditations ca
    where ca.coach_profile_id=v_uid and ca.status='active'
      and (ca.expires_at is null or ca.expires_at>now())
      and ca.accreditation_level between 1 and 7
  ) then
    raise exception 'FORBIDDEN: hanya Coach dengan akreditasi PlayPro aktif Level 1–7 boleh menilai pemain.'
      using errcode='42501';
  end if;
  select accreditation_level into v_level
  from public.coach_accreditations
  where coach_profile_id=v_uid and status='active'
    and (expires_at is null or expires_at>now())
  order by accreditation_level desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,
    'full_name',case when p.display_name_mode='legal'
      then p.full_name else coalesce(nullif(btrim(p.preferred_name),''),p.full_name) end,
    'position',p.position::text,'club_name',c.name,
    'assessment_source',coalesce(s.source,'none'),
    'assessed_count',(select count(*) from jsonb_each(to_jsonb(s)-'player_id'-'source'-'confidence'-'updated_at') e where e.value<>'null'::jsonb)
  ) order by p.full_name),'[]'::jsonb) into v_players
  from public.players p
  left join public.clubs c on c.id=p.club_id
  left join public.player_attribute_state s on s.player_id=p.id
  where p.is_active=true and coalesce(p.is_demo,false)=false;
  return jsonb_build_object('ok',true,'coach_level',v_level,'players',v_players);
end;
$function$;
