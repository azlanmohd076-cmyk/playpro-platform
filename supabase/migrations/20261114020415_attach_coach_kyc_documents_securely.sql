create or replace function public.attach_coach_kyc_documents(p_kyc_id uuid,p_document_paths jsonb) returns jsonb
language plpgsql security definer set search_path='' as $function$
declare v_uid uuid := (select auth.uid()); v_path text; v_count integer;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if p_kyc_id is null or p_document_paths is null or jsonb_typeof(p_document_paths) is distinct from 'array' then raise exception 'INVALID_DOCUMENT_PATHS' using errcode='22023'; end if;
 v_count:=jsonb_array_length(p_document_paths);
 if v_count<1 or v_count>2 then raise exception 'KYC requires one or two documents' using errcode='22023'; end if;
 if not exists(select 1 from public.identity_verifications iv where iv.id=p_kyc_id and iv.profile_id=v_uid and iv.subject_type='coach' and iv.status='pending') then raise exception 'KYC_REQUEST_NOT_OWNED_OR_PENDING' using errcode='42501'; end if;
 for v_path in select jsonb_array_elements_text(p_document_paths) loop
  if v_path is null or v_path not like v_uid::text||'/%' then raise exception 'DOCUMENT_PATH_NOT_OWNED' using errcode='42501'; end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='kyc-documents' and o.name=v_path and o.owner_id=v_uid::text) then raise exception 'DOCUMENT_NOT_FOUND_OR_NOT_OWNED' using errcode='42501'; end if;
 end loop;
 update public.identity_verifications set document_storage_paths=p_document_paths,updated_at=now() where id=p_kyc_id and profile_id=v_uid;
 return jsonb_build_object('ok',true,'kyc_id',p_kyc_id,'document_count',v_count);
end;$function$;
revoke all on function public.attach_coach_kyc_documents(uuid,jsonb) from public;
grant execute on function public.attach_coach_kyc_documents(uuid,jsonb) to authenticated;