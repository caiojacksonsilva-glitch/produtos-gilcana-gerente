-- Produtos Gilçana Gerente V2.0 - Configurações editáveis
begin;
create table if not exists public.gerente_parametros (
 id smallint primary key default 1 check (id=1),
 dados jsonb not null default '{}'::jsonb,
 atualizado_em timestamptz not null default now()
);
insert into public.gerente_parametros(id,dados) values(1,'{}'::jsonb) on conflict(id) do nothing;
alter table public.gerente_parametros enable row level security;

create or replace function public.gerente_obter_parametros()
returns jsonb language plpgsql security definer set search_path='' stable as $$
declare v jsonb;
begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 select dados into v from public.gerente_parametros where id=1;
 return coalesce(v,'{}'::jsonb);
end $$;
revoke all on function public.gerente_obter_parametros() from public,anon;
grant execute on function public.gerente_obter_parametros() to authenticated;

create or replace function public.gerente_salvar_parametros(p_dados jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 if p_dados is null or jsonb_typeof(p_dados)<>'object' then raise exception 'Configuração inválida.'; end if;
 insert into public.gerente_parametros(id,dados,atualizado_em) values(1,p_dados,now())
 on conflict(id) do update set dados=excluded.dados, atualizado_em=now();
end $$;
revoke all on function public.gerente_salvar_parametros(jsonb) from public,anon;
grant execute on function public.gerente_salvar_parametros(jsonb) to authenticated;
commit;
