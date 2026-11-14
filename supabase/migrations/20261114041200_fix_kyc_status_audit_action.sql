create or replace function private.audit_identity_verification_status()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if old.status is distinct from new.status then
  insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data)
  values(
   coalesce(auth.uid(),new.reviewer_profile_id),
   'identity_verifications:'||new.subject_type,
   new.id,
   'update',
   jsonb_build_object('status',old.status,'reviewer_note',old.reviewer_note),
   jsonb_build_object('status',new.status,'reviewer_note',new.reviewer_note,'reviewer_profile_id',new.reviewer_profile_id)
  );
 end if;
 return new;
end $$;
