CREATE OR REPLACE FUNCTION public.rh_calendar_window(target_profile uuid, target_session uuid, target_cnes uuid, range_start date, range_end date, page_index integer DEFAULT 0, search_text text DEFAULT ''::text, filter_json jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET statement_timeout TO '8s'
AS $function$
declare selection jsonb;context jsonb;unit_id uuid;employees jsonb;bond_ids uuid[];rows_count integer;last_day date;result jsonb;ids uuid[];extra jsonb;records jsonb;facets jsonb;conflicts jsonb;conflict_bonds uuid[];page_size integer;
begin
 if (select auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'RH_NOT_ALLOWED';end if;
 if range_start is null or range_start not between date '1900-01-01' and date '2100-12-31' or range_end is null or range_end<range_start or range_end >= (range_start+interval '1 year')::date
  or page_index is null or page_index not between 0 and (case when filter_json ? 'page_size' then 10000 else 100 end) or search_text is null or length(search_text)>120 then raise exception 'RH_INPUT_INVALID';end if;

 if filter_json is null or jsonb_typeof(filter_json)<>'object' or octet_length(filter_json::text)>32000 then raise exception 'RH_INPUT_INVALID';end if;
 if filter_json ? 'page_size' and (jsonb_typeof(filter_json->'page_size')<>'number' or filter_json->>'page_size' not in ('10','20','30','50','80','130')) then raise exception 'RH_INPUT_INVALID';end if;
 page_size:=coalesce((filter_json->>'page_size')::integer,50);
 filter_json:=filter_json-'page_size';
 if exists(select 1 from jsonb_each(filter_json) kv where kv.key not in ('full_name','position','cbo','team','review','type','status','conflict_criteria','conflict_only')
 or case when kv.key='conflict_only' then jsonb_typeof(kv.value)<>'boolean'
 when kv.key in ('full_name','position','cbo','team','conflict_criteria') and jsonb_typeof(kv.value)='array' then jsonb_array_length(kv.value)>200 or exists(select 1 from jsonb_array_elements(kv.value) x where jsonb_typeof(x)<>'string' or length(x#>>'{}')>240)
 else jsonb_typeof(kv.value)<>'string' or length(kv.value#>>'{}')>120 end) then raise exception 'RH_INPUT_INVALID';end if;
 if filter_json ? 'conflict_criteria' and (jsonb_typeof(filter_json->'conflict_criteria')<>'array' or exists(select 1 from jsonb_array_elements_text(filter_json->'conflict_criteria') x where x not in ('position','cbo','team'))) then raise exception 'RH_INPUT_INVALID';end if;
 filter_json:=jsonb_build_object('position','','cbo','','team','','review','todos','type','todos','status','todos','conflict_criteria','[]'::jsonb,'conflict_only',false)||filter_json;
 if filter_json->>'review' not in ('todos','pendente','conferido') or filter_json->>'type' not in ('todos','regulamentar','premio','banco_horas','folga','dayoff','afastamento') or filter_json->>'status' not in ('todos','com_afastamento','sem_afastamento','programada','concluida','cancelada') then raise exception 'RH_INPUT_INVALID';end if;
 context:=public.rh_account_context(target_profile);
 if context is not null then
  selection:=public.rh_session_state(target_profile,target_session);
  if selection->'operator'='null'::jsonb then raise exception 'RH_OPERATOR_REQUIRED';end if;
  unit_id:=(context->>'cnes_unit_id')::uuid;
  if target_cnes is not null and target_cnes<>unit_id then raise exception 'RH_BOND_OUT_OF_UNIT';end if;
 else
  perform private.require_cnes_import_admin(target_profile);
  unit_id:=target_cnes;
  if not exists(select 1 from public.cnes_units where id=unit_id and active) then raise exception 'RH_UNIT_INVALID';end if;
  context:=(select jsonb_build_object('cnes_unit_id',id,'cnes_code',code,'cnes_name',name,'role','administrador') from public.cnes_units where id=unit_id);
 end if;

 -- Catálogos da unidade inteira, independentes dos filtros e da paginação.
 select jsonb_object_agg(key,values) into facets from (
 select key,jsonb_agg(value order by value collate "pt-BR-x-icu") values from (
 select distinct key,value from private.rh_calendar_employees(unit_id) r
 cross join lateral (values ('full_name',r.full_name),('position',r.position),('cbo',r.cbo)) v(key,value) where nullif(btrim(value),'') is not null
 union select 'team',t from private.rh_calendar_employees(unit_id) r cross join lateral unnest(private.rh_calendar_teams(r.entry_id,r.team)) t
 ) choices group by key) catalog;
 -- Cada pessoa é contada uma vez por dia; cancelados e dias não atribuídos são excluídos.
 if filter_json->'conflict_criteria'<>'[]'::jsonb then
 with roster as materialized(select r.*,b.servidor_id person_id,private.rh_calendar_teams(r.entry_id,r.team) teams from private.rh_calendar_employees(unit_id) r join public.employment_bonds b on b.id=r.bond_id),
 periods as (
 select l.bond_id,(p->>'start_date')::date first_day,coalesce((p->>'end_date')::date,date '2100-12-31') last_day,null::uuid legacy_id from private.rh_leaves l
 cross join lateral jsonb_array_elements(l.plan->'periods') p where l.cnes_unit_id=unit_id and l.status<>'cancelada'
 and (filter_json->>'type'='todos' or l.plan->>'type'=filter_json->>'type')
 and (p->>'start_date')::date<=range_end and coalesce((p->>'end_date')::date,date '2100-12-31')>=range_start
 union all select v.context_bond_id,p.start_date,p.end_date,v.id from public.vacation_requests v join public.request_periods p on p.request_id=v.id
 where v.status not in ('cancelada','rejeitada','rascunho','devolvida') and p.start_date<=range_end and p.end_date>=range_start
 and (filter_json->>'type'='todos' or v.type::text=filter_json->>'type')
 and ((v.context_cnes_unit_id=unit_id and v.status in ('programada','reprogramada','concluida')) or exists(select 1 from public.request_unit_reviews u where u.request_id=v.id and u.cnes_unit_id=unit_id and u.status='programada'))
 ), days as materialized(
 select distinct r.bond_id,r.person_id,r.full_name,r.position,r.cbo,r.teams,d::date calendar_day from periods p join roster r on r.bond_id=p.bond_id
 cross join lateral generate_series(greatest(p.first_day,range_start)::timestamp,least(p.last_day,range_end)::timestamp,interval '1 day') d
 where p.legacy_id is null or not exists(select 1 from public.request_day_responsibilities x where x.request_id=p.legacy_id)
 or exists(select 1 from public.request_day_responsibilities x where x.request_id=p.legacy_id and x.cnes_unit_id=unit_id and x.responsibility_date=d::date)
 ), pairs as (
 select a.calendar_day,a.bond_id a,b.bond_id b from days a join days b on a.calendar_day=b.calendar_day and a.bond_id<b.bond_id and a.person_id<>b.person_id
 where filter_json->'conflict_criteria'<>'[]'::jsonb
 and (not (filter_json->'conflict_criteria' ? 'position') or (nullif(btrim(a.position),'') is not null and lower(a.position)=lower(b.position)))
 and (not (filter_json->'conflict_criteria' ? 'cbo') or (nullif(btrim(a.cbo),'') is not null and a.cbo=b.cbo))
 and (not (filter_json->'conflict_criteria' ? 'team') or a.teams && b.teams)
 ), participants as (select calendar_day,a bond_id from pairs union select calendar_day,b from pairs), grouped as (
 select calendar_day,jsonb_agg(bond_id order by bond_id) bond_ids from participants group by calendar_day)
 select coalesce(jsonb_agg(jsonb_build_object('date',calendar_day,'bond_ids',g.bond_ids) order by calendar_day),'[]') into conflicts from grouped g;
 else conflicts:='[]'::jsonb;end if;
 select array_agg(distinct x::uuid) into conflict_bonds from jsonb_array_elements(conflicts) c cross join lateral jsonb_array_elements_text(c->'bond_ids') x;

 last_day:=range_end;
 select count(*) into rows_count from private.rh_calendar_employees(unit_id) r where (search_text='' or position(lower(search_text) in lower(concat_ws(' ',r.full_name,r.registration,r.position,r.cbo,r.team)))>0)
  and private.rh_calendar_row_selected(to_jsonb(r),filter_json)
  and (not (filter_json->>'conflict_only')::boolean or r.bond_id=any(coalesce(conflict_bonds,'{}'::uuid[])))
  and (filter_json->>'review'='todos' or case when filter_json->>'review'='conferido' then r.binding_confirmed else not coalesce(r.binding_confirmed,false) end)
  and private.rh_calendar_window_matches(unit_id,r.bond_id,range_start,range_end,filter_json->>'status',filter_json->>'type');
 select coalesce(jsonb_agg(to_jsonb(r) order by r.full_name collate "pt-BR-x-icu",r.row_id),'[]'),array_agg(distinct r.bond_id) filter(where r.bond_id is not null)
 into employees,bond_ids from (select * from private.rh_calendar_employees(unit_id) r where (search_text='' or position(lower(search_text) in lower(concat_ws(' ',r.full_name,r.registration,r.position,r.cbo,r.team)))>0)
  and private.rh_calendar_row_selected(to_jsonb(r),filter_json)
  and (not (filter_json->>'conflict_only')::boolean or r.bond_id=any(coalesce(conflict_bonds,'{}'::uuid[])))
  and (filter_json->>'review'='todos' or case when filter_json->>'review'='conferido' then r.binding_confirmed else not coalesce(r.binding_confirmed,false) end)
  and private.rh_calendar_window_matches(unit_id,r.bond_id,range_start,range_end,filter_json->>'status',filter_json->>'type')
  order by r.full_name collate "pt-BR-x-icu",r.row_id limit page_size offset page_index*page_size) r;
 result:=jsonb_build_object('context',context,'operator',selection->'operator','month',range_start,'range_start',range_start,'range_end',range_end,'employees',employees,'total',rows_count,
  'absences',coalesce((select jsonb_agg(to_jsonb(a) order by a.start_date,a.id,a.sequence) from (
   select v.id,v.context_bond_id bond_id,v.protocol,v.type,v.status,p.sequence,p.start_date,p.end_date,p.return_date,'legado'::text origin,
    coalesce((select jsonb_agg(d.responsibility_date order by d.responsibility_date) from public.request_day_responsibilities d
     where d.request_id=v.id and d.cnes_unit_id=unit_id and d.responsibility_date between range_start and last_day),'[]') assigned_dates,
    exists(select 1 from public.request_day_responsibilities d where d.request_id=v.id) distributed
   from public.vacation_requests v join public.request_periods p on p.request_id=v.id
   where v.context_bond_id=any(coalesce(bond_ids,'{}'::uuid[])) and (filter_json->>'type'='todos' or v.type::text=filter_json->>'type') and v.status not in ('cancelada','rejeitada','rascunho','devolvida')
    and p.start_date<=last_day and p.end_date>=range_start
    and ((v.context_cnes_unit_id=unit_id and v.status in ('programada','reprogramada','concluida'))
      or exists(select 1 from public.request_unit_reviews r where r.request_id=v.id and r.cnes_unit_id=unit_id and r.status='programada'))
   order by p.start_date,v.id,p.sequence limit 1001) a),'[]'),
  'holidays',coalesce((select jsonb_agg(jsonb_build_object('date',event_date,'name',name,'type',type) order by event_date) from public.calendar_events where active and (scope='general' or unit_id=any(unit_ids)) and event_date between range_start and last_day),'[]'));
 if jsonb_array_length(result->'absences')>1000 then raise exception 'RH_CALENDAR_LIMIT';end if;
 unit_id:=(result->'context'->>'cnes_unit_id')::uuid;
 select array_agg((r->>'bond_id')::uuid) into ids from jsonb_array_elements(result->'employees') r where r->>'bond_id' is not null;
 select coalesce(jsonb_agg(to_jsonb(q)),'[]') into extra from (
  select l.id,l.bond_id,'RH-'||upper(left(replace(l.id::text,'-',''),12)) protocol,l.plan->>'type' type,l.status,
   (p->>'sequence')::integer sequence,p->>'start_date' start_date,p->>'end_date' end_date,p->>'return_date' return_date,
   p->>'counting_mode' counting_mode,'rh'::text origin,false distributed,'[]'::jsonb assigned_dates
  from private.rh_leaves l cross join lateral jsonb_array_elements(l.plan->'periods') p
  where l.cnes_unit_id=unit_id and l.bond_id=any(coalesce(ids,'{}'::uuid[])) and l.status<>'cancelada' and (filter_json->>'type'='todos' or l.plan->>'type'=filter_json->>'type')
   and (p->>'start_date')::date<(range_end+1)::date and coalesce((p->>'end_date')::date,date '2100-12-31')>=range_start limit 1001) q;
 if jsonb_array_length(extra)+jsonb_array_length(result->'absences')>1000 then raise exception 'RH_CALENDAR_LIMIT';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id),'[]') into records from (
  select l.id,'RH-'||upper(left(replace(l.id::text,'-',''),12)) protocol,l.snapshot->>'full_name' full_name,
   l.snapshot->>'registration' registration,l.plan->>'type' type,l.status,l.created_at
  from private.rh_leaves l where l.cnes_unit_id=unit_id and l.bond_id=any(coalesce(ids,'{}'::uuid[])) and (filter_json->>'type'='todos' or l.plan->>'type'=filter_json->>'type') and (filter_json->>'status' not in ('programada','concluida','cancelada') or l.status=filter_json->>'status')
   and exists(select 1 from jsonb_array_elements(l.plan->'periods') p where (p->>'start_date')::date<(range_end+1)::date and coalesce((p->>'end_date')::date,date '2100-12-31')>=range_start)
  order by l.created_at desc,l.id limit 51) q;
 if filter_json->>'type'<>'todos' then
  result:=jsonb_set(result,'{absences}',coalesce((select jsonb_agg(a) from jsonb_array_elements(result->'absences') a where a->>'type'=filter_json->>'type'),'[]'));
  extra:=coalesce((select jsonb_agg(a) from jsonb_array_elements(extra) a where a->>'type'=filter_json->>'type'),'[]');
  records:=coalesce((select jsonb_agg(a) from jsonb_array_elements(records) a where a->>'type'=filter_json->>'type'),'[]');
 end if;
 result:=jsonb_set(result,'{employees}',coalesce((select jsonb_agg(r||jsonb_build_object('birthday_dayoff',birthday.birthday_month is not null,'birth_month_day',case when birthday.bond_id is not null then case when birthday.birthday_month is not null then lpad(birthday.birthday_month::text,2,'0')||'-'||lpad(birthday.birthday_day::text,2,'0') end else to_char(s.birth_date,'MM-DD') end) order by ord)
  from jsonb_array_elements(result->'employees') with ordinality rows(r,ord)
  left join public.employment_bonds b on b.id=(r->>'bond_id')::uuid
  left join public.servidores s on s.id=b.servidor_id left join private.rh_employee_birthdays birthday on birthday.bond_id=b.id),'[]'::jsonb));
 result:=result||jsonb_build_object('source_competence',(select competence from private.cnes_import_runs where cnes_unit_id=unit_id order by created_at desc,id desc limit 1));
 return jsonb_set(result,'{absences}',(result->'absences')||extra)||jsonb_build_object('records',case when jsonb_array_length(records)>50 then records-50 else records end,
  'records_has_more',jsonb_array_length(records)>50,'filters',filter_json,'facets',coalesce(facets,'{}'::jsonb),'conflicts',conflicts);
end $function$;

CREATE FUNCTION public.rh_record_history(target_profile uuid,target_session uuid,target_cnes uuid,target_entry uuid,target_legacy uuid,page_index integer)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $body$
DECLARE actor jsonb; unit_id uuid; bound_bond uuid; matches jsonb;
BEGIN
 IF page_index IS NULL OR page_index NOT BETWEEN 0 AND 10000 OR
    (target_entry IS NULL)=(target_legacy IS NULL) THEN RAISE EXCEPTION 'RH_INPUT_INVALID'; END IF;
 actor:=private.rh_leave_actor(target_profile,target_session,target_cnes);
 unit_id:=(actor->'context'->>'cnes_unit_id')::uuid;
 IF target_entry IS NOT NULL THEN
  SELECT b.bond_id INTO bound_bond FROM private.cnes_registry_entries e LEFT JOIN private.rh_registry_bonds b ON b.entry_id=e.id
  WHERE e.id=target_entry AND e.cnes_unit_id=unit_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'RH_BOND_OUT_OF_UNIT'; END IF;
 END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC,r.id),'[]') INTO matches FROM (
  SELECT l.id,'rh'::text AS origin,l.plan->>'type' AS type,l.status,l.created_at,
   'RH-'||upper(left(replace(l.id::text,'-',''),12)) AS protocol, NULL::jsonb AS periods,
   NULL::text AS full_name
  FROM private.rh_leaves l WHERE target_entry IS NOT NULL AND l.cnes_unit_id=unit_id
   AND (l.entry_id=target_entry OR l.bond_id=bound_bond)
  UNION ALL
  SELECT v.id,'legado',v.type::text,v.status::text,v.created_at,v.protocol::text,
   (SELECT jsonb_agg(jsonb_build_object('start_date',p.start_date,'end_date',p.end_date,'return_date',p.return_date) ORDER BY p.sequence) FROM public.request_periods p WHERE p.request_id=v.id),
   (SELECT s.full_name FROM public.servidores s WHERE s.id=v.servidor_id)
  FROM public.vacation_requests v
  WHERE ((target_entry IS NOT NULL AND v.context_bond_id=bound_bond) OR v.id=target_legacy)
   AND (v.context_cnes_unit_id=unit_id
    OR EXISTS(SELECT 1 FROM public.request_unit_reviews u WHERE u.request_id=v.id AND u.cnes_unit_id=unit_id AND u.status='programada'))
  ORDER BY created_at DESC,id LIMIT 51 OFFSET page_index*50
 ) r;
 IF target_legacy IS NOT NULL THEN
  IF jsonb_array_length(matches)=0 THEN RAISE EXCEPTION 'RH_LEAVE_NOT_FOUND'; END IF;
  RETURN matches->0;
 END IF;
 RETURN jsonb_build_object('records',CASE WHEN jsonb_array_length(matches)>50 THEN matches-50 ELSE matches END,'more',jsonb_array_length(matches)>50);
END
$body$;
REVOKE ALL ON FUNCTION public.rh_record_history(uuid,uuid,uuid,uuid,uuid,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_record_history(uuid,uuid,uuid,uuid,uuid,integer) TO service_role;


create or replace function public.finish_rh_unit(actor_id uuid,target_cnes uuid,target_auth_user uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare slot private.rh_unit_accounts%rowtype;
begin
 perform private.require_cnes_import_admin(actor_id);
 perform pg_advisory_xact_lock(hashtextextended('rh-unit:'||target_cnes::text,0));
 select * into slot from private.rh_unit_accounts where cnes_unit_id=target_cnes for update;
 if not found or slot.auth_user_id<>target_auth_user or not private.rh_auth_account_matches(actor_id,target_auth_user,slot.internal_email,target_cnes) then raise exception 'RH_ACCOUNT_CONFLICT';end if;
 if slot.profile_id is not null then return jsonb_build_object('status','already_exists');end if;
 insert into public.profiles(id,full_name,role,roles,cpf,login_identifier,must_change_password,primary_lotacao_id,institutional_cnes_unit_id,email)
 values(target_auth_user,slot.login_name,'rh',array['rh']::public.app_role[],null,'rh-'||(select code from public.cnes_units where id=target_cnes),true,slot.lotacao_id,target_cnes,slot.internal_email)
 on conflict(id) do update set full_name=excluded.full_name,role='rh',roles=excluded.roles,cpf=null,
   login_identifier=excluded.login_identifier,must_change_password=true,primary_lotacao_id=excluded.primary_lotacao_id,
   institutional_cnes_unit_id=target_cnes,email=excluded.email;
 insert into public.profile_scopes(profile_id,lotacao_id) values(target_auth_user,slot.lotacao_id) on conflict do nothing;
 update private.rh_unit_accounts set profile_id=target_auth_user,version=version+1 where cnes_unit_id=target_cnes;
 insert into public.audit_events(actor_id,actor_role,action,entity_type,entity_id,context_cnes_unit_id,new_value)
 values(actor_id,'administrador','rh_unit_provisioned','profile',target_auth_user,target_cnes,jsonb_build_object('login',slot.login_name));
 return jsonb_build_object('status','ready');
end $$;

CREATE OR REPLACE FUNCTION private.protect_institutional_profile() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $body$
BEGIN
 IF old.institutional_cnes_unit_id IS NOT NULL AND (
  new.institutional_cnes_unit_id IS DISTINCT FROM old.institutional_cnes_unit_id
  OR new.roles<>array['rh']::public.app_role[] OR new.role<>'rh' OR new.cpf IS NOT NULL
  OR (new.must_change_password IS DISTINCT FROM old.must_change_password AND current_user<>'service_role')
  OR new.login_identifier IS DISTINCT FROM old.login_identifier
  OR new.primary_lotacao_id IS DISTINCT FROM old.primary_lotacao_id
 ) THEN RAISE EXCEPTION 'RH_ACCOUNT_MANAGED_SEPARATELY'; END IF;
 RETURN new;
END
$body$;

-- O Auth hospedado não delega as tabelas de credenciais ao service_role.
-- A operação privada mantém a atualização de senha e sessões na transação do SGFS.
CREATE FUNCTION private.sgfs_set_institutional_auth_password(account_id uuid, new_password text, keep_session uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
DECLARE old_hash text;
BEGIN
 IF (SELECT auth.jwt()->>'role') IS DISTINCT FROM 'service_role' OR NOT EXISTS (
  SELECT 1 FROM private.rh_unit_accounts a JOIN public.profiles p ON p.id=a.profile_id
  WHERE p.id=account_id AND p.institutional_cnes_unit_id=a.cnes_unit_id
 ) THEN RAISE EXCEPTION 'RH_NOT_ALLOWED'; END IF;
 IF new_password IS NULL OR length(new_password)<8 OR octet_length(new_password)>72 OR new_password='123456' THEN RAISE EXCEPTION 'RH_PASSWORD_INVALID'; END IF;
 IF keep_session IS NOT NULL THEN
  IF NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.id=keep_session AND s.user_id=account_id AND (s.not_after IS NULL OR s.not_after>now())) THEN
   RAISE EXCEPTION 'RH_NOT_ALLOWED';
  END IF;
  SELECT encrypted_password INTO old_hash FROM auth.users WHERE id=account_id;
  IF old_hash IS NULL OR extensions.crypt(new_password,old_hash)=old_hash THEN RAISE EXCEPTION 'RH_PASSWORD_SAME'; END IF;
 END IF;
 UPDATE auth.users SET encrypted_password=extensions.crypt(new_password,extensions.gen_salt('bf',10)),updated_at=now() WHERE id=account_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'RH_UNIT_INVALID'; END IF;
 IF keep_session IS NOT NULL THEN
  DELETE FROM auth.sessions WHERE user_id=account_id AND id<>keep_session;
 END IF;
END
$body$;
REVOKE ALL ON FUNCTION private.sgfs_set_institutional_auth_password(uuid,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.sgfs_set_institutional_auth_password(uuid,text,uuid) TO service_role;

CREATE FUNCTION public.rh_reset_provisional_password(actor_id uuid,target_cnes uuid,initial_password text)
RETURNS void LANGUAGE plpgsql SET search_path='' AS $body$
DECLARE account uuid;
BEGIN
 IF (SELECT auth.jwt()->>'role') IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'RH_NOT_ALLOWED'; END IF;
 PERFORM private.require_cnes_import_admin(actor_id);
 IF initial_password IS NULL OR length(initial_password)<8 OR octet_length(initial_password)>72 OR initial_password='123456' THEN RAISE EXCEPTION 'RH_PASSWORD_INVALID'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('sgfs-password:'||target_cnes::text,0));
 SELECT a.profile_id INTO account FROM private.rh_unit_accounts a JOIN public.profiles p ON p.id=a.profile_id
  WHERE a.cnes_unit_id=target_cnes AND p.institutional_cnes_unit_id=target_cnes FOR UPDATE OF a,p;
 IF account IS NULL THEN RAISE EXCEPTION 'RH_UNIT_INVALID'; END IF;
 PERFORM private.sgfs_set_institutional_auth_password(account,initial_password);
 UPDATE public.profiles SET must_change_password=true WHERE id=account;
 PERFORM private.rh_revoke_auth_sessions(actor_id,target_cnes);
 INSERT INTO public.audit_events(actor_id,actor_role,action,entity_type,entity_id,context_cnes_unit_id)
 VALUES(actor_id,'administrador','rh_provisional_password_set','profile',account,target_cnes);
END
$body$;
REVOKE ALL ON FUNCTION public.rh_reset_provisional_password(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_reset_provisional_password(uuid,uuid,text) TO service_role;

CREATE FUNCTION public.rh_complete_provisional_password(actor_id uuid,session_id uuid,new_password text)
RETURNS void LANGUAGE plpgsql SET search_path='' AS $body$
DECLARE unit_id uuid;
BEGIN
 IF (SELECT auth.jwt()->>'role') IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'RH_NOT_ALLOWED'; END IF;
 IF new_password IS NULL OR length(new_password)<8 OR octet_length(new_password)>72 OR new_password='123456' THEN RAISE EXCEPTION 'RH_PASSWORD_INVALID'; END IF;
 SELECT institutional_cnes_unit_id INTO unit_id FROM public.profiles WHERE id=actor_id;
 IF unit_id IS NULL THEN RAISE EXCEPTION 'RH_NOT_ALLOWED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('sgfs-password:'||unit_id::text,0));
 IF session_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles p JOIN private.rh_unit_accounts a ON a.profile_id=p.id AND a.cnes_unit_id=p.institutional_cnes_unit_id
   WHERE p.id=actor_id AND p.institutional_cnes_unit_id=unit_id AND p.disabled_at IS NULL AND p.must_change_password AND a.enabled)
 THEN RAISE EXCEPTION 'RH_NOT_ALLOWED'; END IF;
 PERFORM private.sgfs_set_institutional_auth_password(actor_id,new_password,session_id);
 UPDATE public.profiles SET must_change_password=false WHERE id=actor_id;
 INSERT INTO public.audit_events(actor_id,actor_role,action,entity_type,entity_id,context_cnes_unit_id)
 VALUES(actor_id,'rh','rh_provisional_password_changed','profile',actor_id,unit_id);
END
$body$;
REVOKE ALL ON FUNCTION public.rh_complete_provisional_password(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rh_complete_provisional_password(uuid,uuid,text) TO service_role;


CREATE TABLE private.sgfs_terms_acceptances (
 session_id uuid NOT NULL REFERENCES auth.sessions(id) ON DELETE CASCADE,
 account_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 document_version text NOT NULL,
 accepted_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(session_id,document_version)
);
ALTER TABLE private.sgfs_terms_acceptances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.sgfs_terms_acceptances FROM PUBLIC,anon,authenticated;
-- A RPC registra somente a identidade e sessão estabelecidas pelo Auth.
CREATE FUNCTION public.sgfs_session_requirements(accept_version text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
DECLARE current_version constant text:='2026-11-24'; member uuid; session uuid; pending boolean;
BEGIN
 member:=auth.uid();
 session:=nullif(auth.jwt()->>'session_id','')::uuid;
 SELECT p.must_change_password INTO pending FROM public.profiles p JOIN auth.sessions s
  ON s.user_id=p.id AND s.id=session AND (s.not_after IS NULL OR s.not_after>now())
 WHERE p.id=member AND p.disabled_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'SGFS_SESSION_INVALID' USING ERRCODE='28000'; END IF;
 IF accept_version IS NOT NULL THEN
  IF accept_version<>current_version THEN RAISE EXCEPTION 'SGFS_TERMS_VERSION_CHANGED'; END IF;
  INSERT INTO private.sgfs_terms_acceptances(session_id,account_id,document_version) VALUES(session,member,current_version) ON CONFLICT DO NOTHING;
  IF FOUND THEN
   INSERT INTO public.audit_events(actor_id,actor_role,action,entity_type,entity_id,new_value)
   SELECT p.id,p.role,'sgfs_terms_accepted','profile',p.id,jsonb_build_object('document_version',current_version)
   FROM public.profiles p WHERE p.id=member;
  END IF;
 END IF;
 RETURN jsonb_build_object('version',current_version,'passwordPending',pending,
  'accepted',EXISTS(SELECT 1 FROM private.sgfs_terms_acceptances a WHERE a.session_id=session AND a.account_id=member AND a.document_version=current_version));
END
$body$;
REVOKE ALL ON FUNCTION public.sgfs_session_requirements(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sgfs_session_requirements(text) TO authenticated;
NOTIFY pgrst,'reload schema';
