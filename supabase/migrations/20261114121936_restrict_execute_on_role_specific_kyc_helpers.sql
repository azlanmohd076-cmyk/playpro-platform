revoke all on function public.playpro_profile_kyc_verified_for(uuid,text) from public, anon;
revoke all on function public.playpro_profile_kyc_verified(uuid) from public, anon;
grant execute on function public.playpro_profile_kyc_verified_for(uuid,text) to authenticated, service_role;
grant execute on function public.playpro_profile_kyc_verified(uuid) to authenticated, service_role;