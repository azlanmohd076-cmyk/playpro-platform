create or replace function public.ensure_profile_after_signup(
  p_full_name text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_meta jsonb;
  v_row public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select email, raw_user_meta_data
    into v_email, v_meta
    from auth.users
   where id = v_uid;

  if v_email is null then
    raise exception 'Auth user % not found', v_uid using errcode = 'P0002';
  end if;

  insert into public.profiles (id, full_name, email, role, phone)
  values (
    v_uid,
    coalesce(nullif(trim(coalesce(p_full_name, '')), ''),
             nullif(trim(coalesce(v_meta->>'full_name', '')), ''),
             'New User'),
    v_email,
    public.playpro_safe_signup_role(v_meta->>'role'),
    nullif(trim(coalesce(p_phone, coalesce(v_meta->>'phone',''))), '')
  )
  on conflict (id) do nothing;

  -- New signups receive profiles.is_active=true by database default.
  -- Existing disabled accounts must not use this SECURITY DEFINER RPC
  -- to mutate their profile fields.
  perform public.playpro_require_active_account();

  update public.profiles
     set full_name  = coalesce(nullif(trim(coalesce(p_full_name,'')), ''), full_name),
         phone      = coalesce(nullif(trim(coalesce(p_phone,'')), ''), phone),
         email      = coalesce(email, v_email),
         updated_at = now()
   where id = v_uid
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'full_name', v_row.full_name,
    'email', v_row.email,
    'role', v_row.role,
    'phone', v_row.phone,
    'is_active', v_row.is_active
  );
end;
$function$;
