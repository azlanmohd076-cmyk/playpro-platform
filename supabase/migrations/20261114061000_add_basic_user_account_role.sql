-- Basic PlayPro account is distinct from the Player role.
ALTER TYPE public.user_role ADD VALUE IF NOT EXISTS 'user';
