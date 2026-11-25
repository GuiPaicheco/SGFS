\set ON_ERROR_STOP on
BEGIN;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL statement_timeout = '15s';

DO $guard$
BEGIN
  IF current_database() <> 'sgfs_ensaio_20261124_104635'
     OR inet_server_addr() IS DISTINCT FROM inet '127.0.0.1'
     OR inet_server_port() IS DISTINCT FROM 55432
     OR to_regclass('local_ensaio.periodos') IS NULL THEN
    RAISE EXCEPTION 'Execute somente no PostgreSQL local de ensaio do SGFS.';
  END IF;
END;
$guard$;

DO $test$
DECLARE
  unit_id uuid;
  profile_id uuid;
  session_id uuid := gen_random_uuid();
  grant_id uuid;
  other_grant uuid;
  entry_id uuid;
  request_id uuid := gen_random_uuid();
  leave_id uuid;
  day date := date '2098-11-18';
  result jsonb;
  retry jsonb;
  operator_name text;
BEGIN
  SELECT c.id, a.profile_id INTO STRICT unit_id, profile_id
  FROM private.rh_unit_accounts a
  JOIN public.cnes_units c ON c.id = a.cnes_unit_id
  WHERE c.code = '2126486' AND a.enabled AND a.profile_id IS NOT NULL;

  INSERT INTO auth.sessions(id, user_id, created_at, updated_at, not_after)
  VALUES (session_id, profile_id, now(), now(), now() + interval '10 minutes');

  result := public.rh_session_state(profile_id, session_id);
  IF jsonb_array_length(result->'operators') = 0 THEN
    RAISE EXCEPTION 'DAPS sem operadores disponíveis';
  END IF;
  grant_id := (result->'operators'->0->>'id')::uuid;
  SELECT g.id INTO STRICT other_grant
  FROM private.rh_operator_grants g
  WHERE g.cnes_unit_id <> unit_id AND g.active LIMIT 1;

  BEGIN
    PERFORM public.rh_select_operator(profile_id, session_id, other_grant);
    RAISE EXCEPTION 'Operador de outra unidade foi aceito';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'RH_OPERATOR_OUT_OF_UNIT' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.rh_create_occurrence(profile_id, session_id, gen_random_uuid(),
      request_id, 'folga', day, day, 'Ensaio local SGFS', '');
    RAISE EXCEPTION 'Lançamento aceito antes de selecionar operador';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'RH_OPERATOR_REQUIRED' THEN RAISE; END IF;
  END;

  result := public.rh_select_operator(profile_id, session_id, grant_id);
  operator_name := result->'operator'->>'name';
  IF (result->'operator'->>'id')::uuid IS DISTINCT FROM grant_id OR operator_name IS NULL THEN
    RAISE EXCEPTION 'Operador selecionado não retornou na sessão';
  END IF;

  result := public.rh_launch_employees(profile_id, session_id, 0, '');
  SELECT (e->>'entry_id')::uuid INTO STRICT entry_id
  FROM jsonb_array_elements(result->'employees') e
  WHERE (e->>'binding_confirmed')::boolean LIMIT 1;

  result := public.rh_create_occurrence(profile_id, session_id, entry_id,
    request_id, 'folga', day, day, 'Ensaio local SGFS', '');
  leave_id := (result->>'id')::uuid;

  retry := public.rh_create_occurrence(profile_id, session_id, entry_id,
    request_id, 'folga', day, day, 'Ensaio local SGFS', '');
  IF (retry->>'id')::uuid IS DISTINCT FROM leave_id OR
     (retry->>'already_applied')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Reenvio idêntico não reutilizou o lançamento';
  END IF;

  BEGIN
    PERFORM public.rh_create_occurrence(profile_id, session_id, entry_id,
      gen_random_uuid(), 'folga', day, day, 'Ensaio local SGFS', '');
    RAISE EXCEPTION 'Lançamento sobreposto foi aceito';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'RH_LEAVE_OVERLAP' THEN RAISE; END IF;
  END;

  IF NOT EXISTS (SELECT FROM local_ensaio.periodos p
    WHERE p.id = leave_id AND p.unidade = unit_id AND p.tipo = 'folga'
      AND p.inicio = day AND p.fim = day) THEN
    RAISE EXCEPTION 'Lançamento ausente do calendário de ensaio';
  END IF;

  IF NOT EXISTS (SELECT FROM public.audit_events a
    WHERE a.entity_id = leave_id AND a.action = 'rh_occurrence_created'
      AND a.actor_id = profile_id AND a.context_cnes_unit_id = unit_id
      AND a.new_value->>'operator_grant_id' = grant_id::text
      AND a.new_value->>'operator_name' = operator_name) THEN
    RAISE EXCEPTION 'Lançamento ausente no histórico com operador confirmado';
  END IF;

  RAISE NOTICE 'OK: seleção, isolamento, lançamento, reenvio, sobreposição, calendário e auditoria.';
END;
$test$;

ROLLBACK;

DO $verify$
BEGIN
  IF EXISTS (SELECT FROM public.audit_events WHERE reason = 'Ensaio local SGFS') THEN
    RAISE EXCEPTION 'O lançamento de teste ficou persistido';
  END IF;
END;
$verify$;
