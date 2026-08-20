-- Vista previa de SOLO LECTURA. No copia nada todavía.
-- Empareja Alojamientos (grupo='hostal') con Tipos de habitación por
-- nombre normalizado, y muestra qué se copiaría, el nivel de
-- coincidencia, y los casos ambiguos o sin match — para revisar ANTES
-- de correr la copia real.

with t as (
  select tenant_id from public.profiles where email='orielesymama@gmail.com'
),
candidatos as (
  select
    p.id as alojamiento_id, p.nombre as alojamiento_nombre,
    rt.id as tipo_id, rt.nombre as tipo_nombre,
    (lower(trim(p.nombre)) = lower(trim(rt.nombre))) as coincidencia_exacta,
    count(*) over (partition by p.id) as candidatos_para_este_alojamiento,
    jsonb_build_object(
      'descripcion', case when p.descripcion is null then rt.descripcion else null end,
      'camas', case when p.camas is null then rt.camas else null end,
      'tipo_cama', case when p.tipo_cama is null then rt.tipo_cama else null end,
      'banio', case when p.banio is null then rt.banio else null end,
      'ac', case when p.ac is false and rt.ac is true then true else null end,
      'tv', case when p.tv is false and rt.tv is true then true else null end,
      'frigobar', case when p.frigobar is false and rt.frigobar is true then true else null end
    ) as campos_que_se_copiarian
  from public.properties p, t
  join public.room_types rt on rt.tenant_id = t.tenant_id
  where p.tenant_id = t.tenant_id and p.grupo = 'hostal'
    and (
      lower(trim(p.nombre)) = lower(trim(rt.nombre))
      or lower(trim(p.nombre)) like '%'||lower(trim(rt.nombre))||'%'
      or lower(trim(rt.nombre)) like '%'||lower(trim(p.nombre))||'%'
    )
)
select jsonb_pretty(jsonb_build_object(
  'coincidencias_exactas_no_ambiguas', (
    select jsonb_agg(jsonb_build_object(
      'alojamiento', alojamiento_nombre, 'tipo', tipo_nombre, 'copiaria', campos_que_se_copiarian
    ))
    from candidatos
    where coincidencia_exacta and candidatos_para_este_alojamiento = 1
  ),
  'coincidencias_aproximadas_o_ambiguas_NO_se_copian_automatico', (
    select jsonb_agg(jsonb_build_object(
      'alojamiento', alojamiento_nombre, 'tipo_candidato', tipo_nombre,
      'motivo', case when candidatos_para_este_alojamiento > 1 then 'más de un candidato' else 'coincidencia aproximada, no exacta' end
    ))
    from candidatos
    where not (coincidencia_exacta and candidatos_para_este_alojamiento = 1)
  ),
  'alojamientos_hostal_sin_ningun_candidato', (
    select jsonb_agg(p.nombre)
    from public.properties p, t
    where p.tenant_id = t.tenant_id and p.grupo = 'hostal'
      and not exists (select 1 from candidatos c where c.alojamiento_id = p.id)
  ),
  'room_types_sin_ningun_alojamiento_candidato', (
    select jsonb_agg(rt.nombre)
    from public.room_types rt, t
    where rt.tenant_id = t.tenant_id
      and not exists (select 1 from candidatos c where c.tipo_id = rt.id)
  )
)) as vista_previa;
