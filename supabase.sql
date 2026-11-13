-- Novax Engine · demo de los dos tiempos (Lookahead de 2 semanas)
-- Pegar entero en Supabase → SQL Editor → Run. Se puede volver a correr: borra y crea todo de nuevo.

drop view if exists v_plan, v_tarea;
drop function if exists crear_plan(text, date, jsonb), cerrar_plan(bigint, jsonb);
drop table if exists tarea, plan, causa, rubro, proyecto;

create table proyecto (
  codigo text primary key,
  nombre text not null,
  supervisor text not null,
  estado text not null default 'En ejecución'
);

create table rubro (
  id int generated always as identity primary key,
  proyecto text not null references proyecto,
  item text not null,
  descripcion text not null,
  unidad text not null,
  cantidad_contrato numeric not null check (cantidad_contrato > 0),
  precio_unitario numeric not null check (precio_unitario >= 0),
  rendimiento_dia numeric not null check (rendimiento_dia > 0),
  inicio date not null,
  fin date not null check (fin >= inicio),
  unique (proyecto, item)
);

create table causa (
  codigo text primary key,
  nombre text not null,
  detalle text not null,
  tipo text not null check (tipo in ('evitable', 'externa'))
);

create table plan (
  id bigint generated always as identity primary key,
  proyecto text not null references proyecto,
  inicio date not null check (extract(isodow from inicio) = 1),
  entregado date not null default (now() at time zone 'America/Guayaquil')::date,
  cerrado boolean not null default false,
  unique (proyecto, inicio)
);

create table tarea (
  id bigint generated always as identity primary key,
  plan_id bigint not null references plan on delete cascade,
  rubro_id int not null references rubro,
  cantidad_plan numeric not null check (cantidad_plan > 0),
  secuencia_ok boolean not null,
  recursos_ok boolean not null,
  anticipacion_ok boolean not null,
  restriccion text,
  restriccion_liberada boolean not null default false,
  cantidad_real numeric check (cantidad_real >= 0),
  causa text references causa,
  dias_atraso int not null default 0 check (dias_atraso >= 0),
  unique (plan_id, rubro_id)
);

-- El plan cubre 10 días hábiles: del lunes de inicio al viernes de la semana siguiente.
create view v_tarea with (security_invoker = true) as
select t.*, p.proyecto, p.inicio, p.entregado, p.cerrado,
  r.item, r.descripcion, r.unidad, r.precio_unitario, r.rendimiento_dia,
  p.entregado <= p.inicio - 3 as entrega_ok,
  r.inicio <= p.inicio + 13 and r.fin >= p.inicio as cronograma_ok,
  t.cantidad_plan <= r.rendimiento_dia * 10 as cantidad_ok,
  t.cantidad_real >= t.cantidad_plan as cumplida,
  c.nombre as causa_nombre, c.tipo as causa_tipo
from tarea t
join plan p on p.id = t.plan_id
join rubro r on r.id = t.rubro_id
left join causa c on c.codigo = t.causa;

create view v_plan with (security_invoker = true) as
select plan_id as id, proyecto, inicio, entregado, cerrado,
  count(*) as tareas,
  round(100 * bool_and(entrega_ok)::int)::int as c_entrega,
  round(100 * avg(cronograma_ok::int))::int as c_cronograma,
  round(100 * avg(secuencia_ok::int))::int as c_secuencia,
  round(100 * avg(cantidad_ok::int))::int as c_cantidad,
  round(100 * avg(recursos_ok::int))::int as c_recursos,
  round(100 * avg(anticipacion_ok::int))::int as c_anticipacion,
  round(100 * (bool_and(entrega_ok)::int + avg(cronograma_ok::int) + avg(secuencia_ok::int)
    + avg(cantidad_ok::int) + avg(recursos_ok::int) + avg(anticipacion_ok::int)) / 6)::int as nota,
  count(restriccion) as restricciones,
  count(restriccion) filter (where restriccion_liberada) as liberadas,
  count(*) filter (where cumplida) as cumplidas,
  count(*) filter (where not cumplida and causa_tipo = 'evitable') as evitables,
  count(*) filter (where not cumplida and causa_tipo = 'externa') as externas,
  coalesce(sum(dias_atraso) filter (where causa_tipo = 'externa'), 0) as dias_externos,
  sum(cantidad_plan * precio_unitario) as valor_plan,
  coalesce(sum(least(cantidad_real, cantidad_plan) * precio_unitario), 0) as valor_real
from v_tarea
group by plan_id, proyecto, inicio, entregado, cerrado;

-- Tiempo 1: el supervisor entrega el plan de las 2 semanas.
create function crear_plan(p_proyecto text, p_inicio date, p_tareas jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_id bigint;
  v_filas int;
begin
  if extract(isodow from p_inicio) <> 1 then
    raise exception 'El plan tiene que empezar un lunes';
  end if;
  if coalesce(jsonb_array_length(p_tareas), 0) = 0 then
    raise exception 'El plan no tiene rubros';
  end if;
  if exists (select 1 from plan where proyecto = p_proyecto and inicio = p_inicio) then
    raise exception 'Ya hay un plan del % que empieza el %', p_proyecto, to_char(p_inicio, 'DD-MM-YYYY');
  end if;

  insert into plan (proyecto, inicio) values (p_proyecto, p_inicio) returning id into v_id;

  insert into tarea (plan_id, rubro_id, cantidad_plan, secuencia_ok, recursos_ok, anticipacion_ok,
                     restriccion, restriccion_liberada)
  select v_id, r.id, x.cantidad, coalesce(x.secuencia, false), coalesce(x.recursos, false),
         coalesce(x.anticipacion, false), nullif(trim(x.restriccion), ''),
         coalesce(x.liberada, false) and nullif(trim(x.restriccion), '') is not null
  from jsonb_to_recordset(p_tareas) as x(rubro int, cantidad numeric, secuencia boolean, recursos boolean,
                                         anticipacion boolean, restriccion text, liberada boolean)
  join rubro r on r.id = x.rubro and r.proyecto = p_proyecto;

  get diagnostics v_filas = row_count;
  if v_filas <> jsonb_array_length(p_tareas) then
    raise exception 'Hay rubros que no son del proyecto %', p_proyecto;
  end if;
  return v_id;
end $$;

-- Tiempo 2: a las 2 semanas se anota lo ejecutado y la causa de lo que no se cumplió.
create function cerrar_plan(p_plan bigint, p_tareas jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from plan where id = p_plan and not cerrado) then
    raise exception 'El plan no existe o ya está cerrado';
  end if;

  update tarea t
  set cantidad_real = x.real,
      causa = case when x.real < t.cantidad_plan then nullif(x.causa, '') end,
      dias_atraso = case when x.real < t.cantidad_plan then greatest(coalesce(x.dias, 0), 0) else 0 end
  from jsonb_to_recordset(p_tareas) as x(id bigint, real numeric, causa text, dias int)
  where t.id = x.id and t.plan_id = p_plan;

  if exists (select 1 from tarea
             where plan_id = p_plan
               and (cantidad_real is null or (cantidad_real < cantidad_plan and causa is null))) then
    raise exception 'Falta la cantidad ejecutada, o la causa de un rubro que no se cumplió';
  end if;

  update plan set cerrado = true where id = p_plan;
end $$;

-- La página solo lee las tablas; para escribir usa las dos funciones de arriba.
alter table proyecto enable row level security;
alter table rubro enable row level security;
alter table causa enable row level security;
alter table plan enable row level security;
alter table tarea enable row level security;
create policy lectura on proyecto for select to anon, authenticated using (true);
create policy lectura on rubro for select to anon, authenticated using (true);
create policy lectura on causa for select to anon, authenticated using (true);
create policy lectura on plan for select to anon, authenticated using (true);
create policy lectura on tarea for select to anon, authenticated using (true);
grant usage on schema public to anon, authenticated;
grant select on proyecto, rubro, causa, plan, tarea, v_tarea, v_plan to anon, authenticated;
revoke execute on function crear_plan(text, date, jsonb), cerrar_plan(bigint, jsonb) from public;
grant execute on function crear_plan(text, date, jsonb), cerrar_plan(bigint, jsonb) to anon, authenticated;

-- Datos ilustrativos -----------------------------------------------------------------------

insert into proyecto (codigo, nombre, supervisor, estado) values
  ('1213', 'Truck Shop Area', 'Supervisor A', 'En ejecución'),
  ('1421', 'Laundry Relocation', 'Supervisor B', 'En ejecución'),
  ('1461', 'Water Catchment Phase 2', 'Supervisor C', 'En ejecución'),
  ('1810', 'Rom Pad Expansion Fase III', 'Supervisor D', 'En ejecución'),
  ('1815', 'Rom Pad Drainage Phase 2', 'Supervisor E', 'En cierre');

insert into causa (codigo, nombre, detalle, tipo) values
  ('MAT', 'Material', 'No llegó o se pidió tarde', 'evitable'),
  ('CUA', 'Cuadrilla', 'Incompleta o sin inducción', 'evitable'),
  ('EQU', 'Equipo', 'Dañado o sin reservar', 'evitable'),
  ('CLI', 'Clima', 'Lluvia en hormigón o excavación', 'externa'),
  ('LUG', 'LUG', 'Frente sin liberar, permiso o inspección', 'externa'),
  ('DIS', 'Diseño', 'Consulta (RFI) sin respuesta', 'externa');

insert into rubro (proyecto, item, descripcion, unidad, cantidad_contrato, precio_unitario, rendimiento_dia, inicio, fin) values
  ('1213', '21', 'Hormigón f''c=240 kg/cm² en losa', 'm³', 180, 168.40, 15, '2026-10-05', '2026-11-13'),
  ('1213', '47', 'Acero estructural', 'kg', 10000, 4.85, 400, '2026-09-28', '2026-11-27'),
  ('1213', '62', 'Contenedores', 'u', 8, 9850.00, 0.5, '2026-10-12', '2026-11-20'),
  ('1213', '69', 'Puertas metálicas', 'u', 6, 1240.00, 1, '2026-11-02', '2026-11-27'),
  ('1213', '85', 'Pintura epóxica en piso', 'm²', 1200, 18.60, 120, '2026-11-09', '2026-12-11'),
  ('1421', '05', 'Desmontaje de equipos de lavandería', 'glb', 1, 3200.00, 0.2, '2026-10-21', '2026-11-06'),
  ('1421', '08', 'Picado y retiro de piso existente', 'm²', 320, 11.40, 40, '2026-10-26', '2026-11-13'),
  ('1421', '14', 'Instalaciones sanitarias PVC 110 mm', 'm', 180, 21.90, 25, '2026-11-09', '2026-12-04'),
  ('1421', '22', 'Mampostería de bloque e=15 cm', 'm²', 410, 24.70, 30, '2026-11-16', '2026-12-18'),
  ('1421', '30', 'Tablero eléctrico de distribución', 'u', 2, 4650.00, 0.5, '2026-11-23', '2026-12-18'),
  ('1461', '12', 'Excavación a máquina en suelo', 'm³', 2400, 4.20, 250, '2026-10-01', '2026-11-10'),
  ('1461', '18', 'Tubería HDPE 315 mm', 'm', 860, 62.30, 60, '2026-10-05', '2026-11-27'),
  ('1461', '25', 'Hormigón ciclópeo en captación', 'm³', 140, 112.80, 12, '2026-10-19', '2026-11-20'),
  ('1461', '31', 'Rejilla metálica de captación', 'u', 4, 1850.00, 1, '2026-11-09', '2026-11-27'),
  ('1461', '40', 'Relleno compactado con mejoramiento', 'm³', 1500, 9.75, 180, '2026-10-12', '2026-12-04'),
  ('1810', '03', 'Desbroce y limpieza', 'm²', 18000, 0.85, 2500, '2026-09-07', '2026-10-16'),
  ('1810', '07', 'Excavación de plataforma', 'm³', 22000, 3.90, 1200, '2026-09-21', '2026-11-27'),
  ('1810', '11', 'Conformación y compactación de plataforma', 'm²', 15000, 2.60, 900, '2026-10-12', '2026-12-11'),
  ('1810', '16', 'Geomembrana HDPE 1,5 mm', 'm²', 12000, 7.80, 800, '2026-11-02', '2026-12-18'),
  ('1810', '24', 'Cuneta de hormigón f''c=210 kg/cm²', 'm', 950, 38.50, 50, '2026-11-09', '2026-12-18');

insert into plan (proyecto, inicio, entregado, cerrado) values
  ('1213', '2026-10-05', '2026-10-01', true),
  ('1213', '2026-10-19', '2026-10-15', true),
  ('1213', '2026-11-02', '2026-10-29', true),
  ('1421', '2026-11-02', '2026-10-31', true),
  ('1461', '2026-10-05', '2026-10-01', true),
  ('1461', '2026-10-19', '2026-10-16', true),
  ('1461', '2026-11-02', '2026-10-30', false),
  ('1810', '2026-10-05', '2026-10-05', true),
  ('1810', '2026-10-19', '2026-10-19', true),
  ('1810', '2026-11-02', '2026-11-02', false);

insert into tarea (plan_id, rubro_id, cantidad_plan, secuencia_ok, recursos_ok, anticipacion_ok,
                   restriccion, restriccion_liberada, cantidad_real, causa, dias_atraso)
select p.id, r.id, x.cantidad_plan, x.secuencia_ok, x.recursos_ok, x.anticipacion_ok,
       x.restriccion, x.liberada, x.cantidad_real, x.causa, x.dias
from (values
  ('1213', '2026-10-05', '47', 3000, true, true, true, null, false, 3000, null, 0),
  ('1213', '2026-10-05', '21', 120, true, true, false, 'Hormigonera sin reservar', true, 95, 'EQU', 1),
  ('1213', '2026-10-05', '62', 2, true, true, true, null, false, 2, null, 0),
  ('1213', '2026-10-19', '47', 3200, true, true, true, null, false, 3200, null, 0),
  ('1213', '2026-10-19', '21', 60, true, true, true, null, false, 60, null, 0),
  ('1213', '2026-10-19', '62', 3, true, true, true, 'Grúa para izaje', true, 3, null, 0),
  ('1213', '2026-11-02', '47', 3000, true, true, true, null, false, 3000, null, 0),
  ('1213', '2026-11-02', '21', 25, true, true, true, null, false, 25, null, 0),
  ('1213', '2026-11-02', '62', 3, true, true, true, null, false, 3, null, 0),
  ('1213', '2026-11-02', '69', 4, true, true, true, null, false, 4, null, 0),
  ('1213', '2026-11-02', '85', 400, true, true, true, 'Inspección de superficie', true, 400, null, 0),
  ('1421', '2026-11-02', '05', 1, true, true, true, null, false, 1, null, 0),
  ('1421', '2026-11-02', '08', 250, true, true, true, null, false, 250, null, 0),
  ('1421', '2026-11-02', '14', 60, false, false, false, 'Inducción del personal nuevo', false, 30, 'CUA', 2),
  ('1461', '2026-10-05', '12', 1500, true, true, true, null, false, 1500, null, 0),
  ('1461', '2026-10-05', '18', 300, true, true, true, null, false, 260, 'CLI', 1),
  ('1461', '2026-10-05', '40', 500, true, true, true, null, false, 500, null, 0),
  ('1461', '2026-10-19', '12', 900, true, true, true, null, false, 900, null, 0),
  ('1461', '2026-10-19', '18', 400, true, true, true, null, false, 400, null, 0),
  ('1461', '2026-10-19', '25', 60, true, true, false, 'Inspección de LUG del encofrado', false, 40, 'LUG', 2),
  ('1461', '2026-10-19', '40', 600, true, true, true, null, false, 600, null, 0),
  ('1461', '2026-11-02', '18', 160, true, true, true, null, false, null, null, 0),
  ('1461', '2026-11-02', '25', 80, true, true, true, null, false, null, null, 0),
  ('1461', '2026-11-02', '31', 2, true, true, false, 'Rejillas en fabricación', true, null, null, 0),
  ('1461', '2026-11-02', '40', 400, true, true, true, null, false, null, null, 0),
  ('1810', '2026-10-05', '03', 8000, true, true, false, null, false, 8000, null, 0),
  ('1810', '2026-10-05', '07', 14000, true, true, true, 'Excavadora en mantenimiento', false, 9500, 'EQU', 2),
  ('1810', '2026-10-05', '11', 4000, false, false, false, 'Frente sin liberar por LUG', false, 0, 'LUG', 3),
  ('1810', '2026-10-19', '03', 6000, true, true, true, null, false, 6000, null, 0),
  ('1810', '2026-10-19', '07', 9000, true, false, true, null, false, 7200, 'CLI', 2),
  ('1810', '2026-10-19', '11', 5000, true, true, true, null, false, 5000, null, 0),
  ('1810', '2026-10-19', '16', 3000, false, true, false, 'Geomembrana sin pedir', false, 0, 'MAT', 3),
  ('1810', '2026-11-02', '07', 8000, true, true, true, null, false, null, null, 0),
  ('1810', '2026-11-02', '11', 6000, true, true, true, null, false, null, null, 0),
  ('1810', '2026-11-02', '16', 4000, true, true, false, 'Geomembrana en tránsito', false, null, null, 0),
  ('1810', '2026-11-02', '24', 300, false, false, true, 'Permiso de trabajo de LUG', false, null, null, 0)
) as x(proyecto, inicio, item, cantidad_plan, secuencia_ok, recursos_ok, anticipacion_ok,
       restriccion, liberada, cantidad_real, causa, dias)
join plan p on p.proyecto = x.proyecto and p.inicio = x.inicio::date
join rubro r on r.proyecto = x.proyecto and r.item = x.item;
