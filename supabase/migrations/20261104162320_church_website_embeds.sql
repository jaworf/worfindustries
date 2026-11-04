-- Website framing is opt-in per church; it never grants access to church records.
create table public.church_embed_settings (
 church_id uuid primary key references public.churches(id),
 allowed_origins text[] not null default '{}',
 secure_enabled boolean not null default false,
 public_enabled boolean not null default false,
 updated_by uuid references public.profiles(user_id) on delete set null,
 updated_at timestamptz not null default now()
);
alter table public.church_embed_settings enable row level security;
revoke all on public.church_embed_settings from public,anon,authenticated;
grant select on public.church_embed_settings to authenticated;
grant all on public.church_embed_settings to service_role;
create policy church_embed_settings_admin_read on public.church_embed_settings for select to authenticated
 using(private.has_church_role(church_id,array['admin']));
create function private.save_website_embeds(p_origins text[],p_secure boolean,p_public boolean,p_directory_published boolean) returns void
language plpgsql security definer set search_path='' as $$
declare c uuid:=private.current_church_id(); v text;
begin
 if not private.has_church_role(c,array['admin']) then raise exception 'Administrator access required.'; end if;
 if p_origins is null or cardinality(p_origins)>10 then raise exception 'Enter up to 10 website addresses.'; end if;
 foreach v in array p_origins loop
  if v is null or length(v)>255 or v !~ '^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}(:[0-9]{1,5})?$' then raise exception 'Use an HTTPS website origin, without a path, password, wildcard or trailing slash.'; end if;
 end loop;
 if p_secure is null or p_public is null or p_directory_published is null then raise exception 'Choose your website sharing options.'; end if;
 if (p_secure or p_public) and cardinality(p_origins)=0 then raise exception 'Add the website address allowed to display the app.'; end if;
 if p_public and not p_directory_published then raise exception 'Public directory publishing must be enabled for an anonymous iframe.'; end if;
 update public.churches set public_directory_enabled=p_directory_published where id=c;
 insert into public.church_embed_settings(church_id,allowed_origins,secure_enabled,public_enabled,updated_by)
 values(c,array(select distinct x from unnest(p_origins) x),p_secure,p_public,auth.uid())
 on conflict(church_id) do update set allowed_origins=excluded.allowed_origins,secure_enabled=excluded.secure_enabled,public_enabled=excluded.public_enabled,updated_by=excluded.updated_by,updated_at=now();
end;$$;
revoke all on function private.save_website_embeds(text[],boolean,boolean,boolean) from public,anon;
grant execute on function private.save_website_embeds(text[],boolean,boolean,boolean) to authenticated;
create function public.save_website_embeds(p_origins text[],p_secure boolean,p_public boolean,p_directory_published boolean) returns void
language sql security invoker set search_path='' as $$select private.save_website_embeds(p_origins,p_secure,p_public,p_directory_published)$$;
revoke all on function public.save_website_embeds(text[],boolean,boolean,boolean) from public,anon;
grant execute on function public.save_website_embeds(text[],boolean,boolean,boolean) to authenticated;
create function public.website_embed_settings() returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('allowed_origins',coalesce(s.allowed_origins,'{}'::text[]),'secure_enabled',coalesce(s.secure_enabled,false),'public_enabled',coalesce(s.public_enabled,false),'directory_published',c.public_directory_enabled)
 from public.churches c left join public.church_embed_settings s on s.church_id=c.id
 where c.id=private.current_church_id() and private.has_church_role(c.id,array['admin']);
$$;
revoke all on function public.website_embed_settings() from public,anon;
grant execute on function public.website_embed_settings() to authenticated;
-- Intentional anonymous bootstrap: only enabled church branding and frame hosts.
-- No personnel, credentials, profiles, contact details or recruitment data.
create function public.website_embed_config(p_slug text,p_mode text) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('name',c.name,'slug',c.slug,'allowed_origins',s.allowed_origins)
 from public.churches c join public.church_embed_settings s on s.church_id=c.id
 where c.slug=p_slug and p_slug ~ '^[a-z0-9][a-z0-9-]{0,79}$' and c.is_active and cardinality(s.allowed_origins)>0
 and ((p_mode='app' and s.secure_enabled) or (p_mode='directory' and s.public_enabled and c.public_directory_enabled));
$$;
revoke all on function public.website_embed_config(text,text) from public;
grant execute on function public.website_embed_config(text,text) to anon,authenticated,service_role;
comment on function public.website_embed_config(text,text) is 'Public bootstrap metadata for an explicitly enabled church embed; never returns church records or authorizes data access.';
