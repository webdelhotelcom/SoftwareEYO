-- ════════════════════════════════════════════════════════════════
-- 0024 — Personalización por cuenta: nombre comercial, colores y
-- logo propio, cada uno guardado por tenant y protegido por RLS.
--
-- Decisión técnica (ver docs/obsidian/Personalizacion.md para el
-- detalle completo): SÍ es factible con la arquitectura actual y
-- sin costo — el logo va a Supabase Storage (parte del mismo
-- proyecto free, no un servicio nuevo), tope de 300 KB por archivo,
-- un solo logo activo por tenant (se reemplaza, no se acumula).
-- ════════════════════════════════════════════════════════════════

create table public.tenant_settings (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  business_name text,
  logo_path text,
  primary_color text,
  sidebar_color text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  constraint business_name_len check (business_name is null or char_length(business_name) <= 60),
  constraint business_name_no_html check (business_name is null or business_name !~ '[<>]'),
  constraint primary_color_hex check (primary_color is null or primary_color ~* '^#[0-9a-f]{6}$'),
  constraint sidebar_color_hex check (sidebar_color is null or sidebar_color ~* '^#[0-9a-f]{6}$')
);

comment on table public.tenant_settings is 'Personalización visual por cliente: nombre comercial, colores y logo. Una fila por tenant, valores NULL = usar el default de Software EYO.';

alter table public.tenant_settings enable row level security;

-- Cualquier usuario logueado del tenant puede LEER la personalización
-- (todos ven el mismo logo/colores/nombre — es apariencia, no un dato
-- sensible), pero solo un admin puede escribirla.
create policy "tenant_settings_select_own_tenant" on public.tenant_settings
  for select using (tenant_id = public.current_tenant_id());

create policy "tenant_settings_insert_admin" on public.tenant_settings
  for insert with check (tenant_id = public.current_tenant_id() and public.is_admin());

create policy "tenant_settings_update_admin" on public.tenant_settings
  for update using (tenant_id = public.current_tenant_id() and public.is_admin())
  with check (tenant_id = public.current_tenant_id() and public.is_admin());

-- Sin política de DELETE a propósito: "restaurar diseño original" es un
-- UPDATE que deja las columnas en NULL, no borra la fila — más simple
-- y evita el caso raro de "tenant sin fila de settings todavía".

-- ────────────────────────────────────────────────────────────────
-- Storage: bucket privado para los logos, un archivo por tenant en
-- tenant-logos/{tenant_id}/logo.webp (o .png/.jpg si no se pudo
-- convertir a webp en el navegador). Bucket NO público: todo acceso
-- pasa por las políticas de storage.objects de abajo, igual que
-- cualquier otra tabla — un tenant no puede ver el logo de otro ni
-- por URL directa.
-- ────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('tenant-logos', 'tenant-logos', false, 307200, array['image/webp','image/png','image/jpeg'])
on conflict (id) do nothing;

create policy "tenant_logos_select_own_tenant" on storage.objects
  for select using (
    bucket_id = 'tenant-logos'
    and (storage.foldername(name))[1] = public.current_tenant_id()::text
  );

create policy "tenant_logos_admin_insert" on storage.objects
  for insert with check (
    bucket_id = 'tenant-logos'
    and (storage.foldername(name))[1] = public.current_tenant_id()::text
    and public.is_admin()
  );

create policy "tenant_logos_admin_update" on storage.objects
  for update using (
    bucket_id = 'tenant-logos'
    and (storage.foldername(name))[1] = public.current_tenant_id()::text
    and public.is_admin()
  );

create policy "tenant_logos_admin_delete" on storage.objects
  for delete using (
    bucket_id = 'tenant-logos'
    and (storage.foldername(name))[1] = public.current_tenant_id()::text
    and public.is_admin()
  );
