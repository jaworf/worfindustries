
-- Private, fixed per-church object keys. Storage enforces both file limits and
-- church membership, including upserts (SELECT + INSERT + UPDATE).
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('church-logos','church-logos',false,2097152,array['image/png','image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy church_logo_read on storage.objects for select to authenticated
using(bucket_id='church-logos' and name=private.current_church_id()::text||'/logo' and private.has_church_role(private.current_church_id(),array['admin','editor','viewer']));
create policy church_logo_insert on storage.objects for insert to authenticated
with check(bucket_id='church-logos' and name=private.current_church_id()::text||'/logo' and private.has_church_role(private.current_church_id(),array['admin']));
create policy church_logo_update on storage.objects for update to authenticated
using(bucket_id='church-logos' and name=private.current_church_id()::text||'/logo' and private.has_church_role(private.current_church_id(),array['admin']))
with check(bucket_id='church-logos' and name=private.current_church_id()::text||'/logo' and private.has_church_role(private.current_church_id(),array['admin']));
create policy church_logo_delete on storage.objects for delete to authenticated
using(bucket_id='church-logos' and name=private.current_church_id()::text||'/logo' and private.has_church_role(private.current_church_id(),array['admin']));
