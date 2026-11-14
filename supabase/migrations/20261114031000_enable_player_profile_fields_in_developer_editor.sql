-- Expand safe Player editing fields in the Developer Database Editor.
create or replace function public.developer_editor_update(p_entity text,p_id uuid,p_changes jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_before jsonb; v_after jsonb; v_updated_at timestamptz;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='developer'::public.user_role and p.is_active=true) then raise exception 'Developer access required'; end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'object' or p_changes='{}'::jsonb then raise exception 'No changes supplied'; end if;
 if p_entity='players' then
  select to_jsonb(t) into v_before from public.players t where t.id=p_id; if v_before is null then raise exception 'Player not found'; end if;
  update public.players t set full_name=case when p_changes?'full_name' then nullif(p_changes->>'full_name','') else t.full_name end,
   preferred_name=case when p_changes?'preferred_name' then nullif(p_changes->>'preferred_name','') else t.preferred_name end,
   date_of_birth=case when p_changes?'date_of_birth' then (p_changes->>'date_of_birth')::date else t.date_of_birth end,
   position=case when p_changes?'position' then (p_changes->>'position')::public.player_position else t.position end,
   nationality=case when p_changes?'nationality' then nullif(p_changes->>'nationality','') else t.nationality end,
   is_active=case when p_changes?'is_active' then (p_changes->>'is_active')::boolean else t.is_active end,
   is_free_agent=case when p_changes?'is_free_agent' then (p_changes->>'is_free_agent')::boolean else t.is_free_agent end,
   updated_at=now() where t.id=p_id returning t.updated_at,to_jsonb(t) into v_updated_at,v_after;
 elsif p_entity='coaches' then
  select to_jsonb(t) into v_before from public.coaches t where t.id=p_id; if v_before is null then raise exception 'Coach not found'; end if;
  update public.coaches t set full_name=case when p_changes?'full_name' then nullif(p_changes->>'full_name','') else t.full_name end,
   preferred_name=case when p_changes?'preferred_name' then nullif(p_changes->>'preferred_name','') else t.preferred_name end,
   bio=case when p_changes?'bio' then nullif(p_changes->>'bio','') else t.bio end,
   coaching_role=case when p_changes?'coaching_role' then nullif(p_changes->>'coaching_role','') else t.coaching_role end,
   license_number=case when p_changes?'license_number' then nullif(p_changes->>'license_number','') else t.license_number end,
   license_status=case when p_changes?'license_status' then nullif(p_changes->>'license_status','') else t.license_status end,
   is_active=case when p_changes?'is_active' then (p_changes->>'is_active')::boolean else t.is_active end,
   updated_at=now() where t.id=p_id returning t.updated_at,to_jsonb(t) into v_updated_at,v_after;
 elsif p_entity='clubs' then
  select to_jsonb(t) into v_before from public.clubs t where t.id=p_id; if v_before is null then raise exception 'Club not found'; end if;
  update public.clubs t set name=case when p_changes?'name' then nullif(p_changes->>'name','') else t.name end,
   description=case when p_changes?'description' then nullif(p_changes->>'description','') else t.description end,
   city=case when p_changes?'city' then nullif(p_changes->>'city','') else t.city end,
   state=case when p_changes?'state' then nullif(p_changes->>'state','') else t.state end,
   country=case when p_changes?'country' then nullif(p_changes->>'country','') else t.country end,
   home_venue=case when p_changes?'home_venue' then nullif(p_changes->>'home_venue','') else t.home_venue end,
   colours=case when p_changes?'colours' then nullif(p_changes->>'colours','') else t.colours end,
   updated_at=now() where t.id=p_id returning t.updated_at,to_jsonb(t) into v_updated_at,v_after;
 else raise exception 'Updates are not enabled for this entity'; end if;
 insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data) values(auth.uid(),p_entity,p_id,'update',v_before,v_after);
 return jsonb_build_object('entity',p_entity,'id',p_id,'updated_at',v_updated_at,'saved',true);
end; $$;
revoke all on function public.developer_editor_update(text,uuid,jsonb) from public,anon;
grant execute on function public.developer_editor_update(text,uuid,jsonb) to authenticated;
