create policy identity_verification_developer_read_coach on public.identity_verifications for select to authenticated
using(subject_type='coach' and (select public.get_my_role())='developer'::public.user_role);
create policy coach_kyc_read_developer_documents on storage.objects for select to authenticated
using(bucket_id='kyc-documents' and (select public.get_my_role())='developer'::public.user_role and exists(
 select 1 from public.identity_verifications iv where iv.subject_type='coach'
 and (storage.foldername(name))[1]=iv.profile_id::text
 and iv.document_storage_paths @> jsonb_build_array(name)
));
create or replace function public.get_coach_kyc_admin_list() returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_uid uuid := (select auth.uid()); v_rows jsonb;
begin
 if v_uid is null or (select public.get_my_role()) is distinct from 'developer'::public.user_role then raise exception 'FORBIDDEN: Developer PlayPro only' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('kyc_id',iv.id,'profile_id',iv.profile_id,'coach_id',c.id,'coach_code',c.coach_code,'coach_name',coalesce(nullif(btrim(c.preferred_name),''),c.full_name),'id_type',iv.id_type,'legal_name_claimed',iv.legal_name_claimed,'masked_identifier',iv.masked_identifier,'birth_state_code',iv.birth_state_code,'submitted_at',iv.submitted_at,'provider_status',iv.provider_status,'match_status',iv.match_status,'extracted_legal_name',iv.extracted_legal_name,'extracted_birth_date',iv.extracted_birth_date,'document_storage_paths',iv.document_storage_paths) order by iv.submitted_at),'[]'::jsonb) into v_rows
 from public.identity_verifications iv join public.coaches c on c.profile_id=iv.profile_id
 where iv.subject_type='coach' and iv.status='pending' and c.is_active=true;
 return jsonb_build_object('ok',true,'requests',v_rows);
end;$function$;
revoke all on function public.get_coach_kyc_admin_list() from public;
grant execute on function public.get_coach_kyc_admin_list() to authenticated;