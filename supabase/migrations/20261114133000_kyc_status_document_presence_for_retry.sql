-- Expose only a boolean document-presence flag so the owner can retry OCR without uploading again.
create or replace function public.get_my_identity_kyc_status()
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_k public.identity_verifications%rowtype;
begin
 perform public.playpro_require_active_account();
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into v_k from public.identity_verifications
 where profile_id=v_uid and subject_type='individual'
 order by submitted_at desc,created_at desc limit 1;
 if not found then
   return jsonb_build_object('ok',true,'status','not_submitted','is_verified',false,'has_documents',false);
 end if;
 return jsonb_build_object(
   'ok',true,'kyc_id',v_k.id,'status',v_k.status,
   'is_verified',v_k.status in ('verified','approved') and v_k.expires_at>now(),
   'id_type',v_k.id_type,'submitted_at',v_k.submitted_at,
   'reviewed_at',v_k.reviewed_at,'expires_at',v_k.expires_at,
   'provider_status',v_k.provider_status,'match_status',v_k.match_status,
   'reviewer_note',v_k.reviewer_note,
   'has_documents',jsonb_array_length(coalesce(v_k.document_storage_paths,'[]'::jsonb))>0
 );
end;
$$;
revoke all on function public.get_my_identity_kyc_status() from public,anon;
grant execute on function public.get_my_identity_kyc_status() to authenticated,service_role;
