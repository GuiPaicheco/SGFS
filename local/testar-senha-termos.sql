\set ON_ERROR_STOP on
BEGIN;
DO $guard$
BEGIN
 IF current_database()<>'sgfs_integrado' OR inet_server_addr() IS DISTINCT FROM inet '127.0.0.1'
 OR inet_server_port() IS DISTINCT FROM 55432 THEN
  RAISE EXCEPTION 'Execute somente no banco integrado local.';
 END IF;
END
$guard$;
CREATE TEMP TABLE sgfs_pilot_identity ON COMMIT DROP AS
SELECT a.profile_id rh, a.cnes_unit_id unit_id, p.id admin,
       gen_random_uuid() AS old_session,gen_random_uuid() AS next_session,gen_random_uuid() AS competing_session
FROM private.rh_unit_accounts a JOIN public.cnes_units c ON c.id=a.cnes_unit_id
CROSS JOIN LATERAL (SELECT id FROM public.profiles WHERE 'administrador'=ANY(roles) AND disabled_at IS NULL LIMIT 1) p
WHERE c.code='2126486';
GRANT SELECT ON sgfs_pilot_identity TO service_role;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at)
SELECT old_session,rh,now(),now() FROM sgfs_pilot_identity;

SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SELECT set_config('request.headers',json_build_object('x-sgf-role','administrador','x-sgf-actor',admin)::text,true) FROM sgfs_pilot_identity \gset
DO $test$
DECLARE fixture record; hash text;
BEGIN
 SELECT * INTO STRICT fixture FROM sgfs_pilot_identity;
 BEGIN
  PERFORM public.rh_reset_provisional_password(fixture.admin,fixture.unit_id,'123456');
  RAISE EXCEPTION 'Senha compartilhada aceita';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'RH_PASSWORD_INVALID' THEN RAISE; END IF; END;
 PERFORM public.rh_reset_provisional_password(fixture.admin,fixture.unit_id,'Ensaio-Temporario-91');
 IF EXISTS(SELECT 1 FROM auth.sessions WHERE id=fixture.old_session) THEN RAISE EXCEPTION 'Sessão antiga ativa'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=fixture.rh AND must_change_password) THEN RAISE EXCEPTION 'Troca não sinalizada'; END IF;
 IF public.rh_account_context(fixture.rh) IS NOT NULL THEN RAISE EXCEPTION 'Conta pendente recebeu escopo'; END IF;
 SELECT encrypted_password INTO hash FROM auth.users WHERE id=fixture.rh;
 IF hash<>extensions.crypt('Ensaio-Temporario-91',hash) THEN RAISE EXCEPTION 'Senha inicial não gravada'; END IF;
END
$test$;
RESET ROLE;

INSERT INTO auth.sessions(id,user_id,created_at,updated_at)
SELECT next_session,rh,now(),now() FROM sgfs_pilot_identity
UNION ALL SELECT competing_session,rh,now(),now() FROM sgfs_pilot_identity;

SET LOCAL ROLE service_role;
DO $test$
DECLARE fixture record; hash text;
BEGIN
 SELECT * INTO STRICT fixture FROM sgfs_pilot_identity;
 BEGIN
  PERFORM public.rh_complete_provisional_password(fixture.rh,fixture.old_session,'Ensaio-Definitivo-83');
  RAISE EXCEPTION 'Sessão revogada alterou a senha';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'RH_NOT_ALLOWED' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.rh_complete_provisional_password(fixture.rh,fixture.next_session,'Ensaio-Temporario-91');
  RAISE EXCEPTION 'A troca aceitou a senha provisória';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'RH_PASSWORD_SAME' THEN RAISE; END IF; END;
 PERFORM public.rh_complete_provisional_password(fixture.rh,fixture.next_session,'Ensaio-Definitivo-83');
 IF EXISTS(SELECT FROM auth.sessions WHERE id=fixture.competing_session) THEN RAISE EXCEPTION 'Sessão concorrente com senha provisória permaneceu ativa'; END IF;
 SELECT encrypted_password INTO hash FROM auth.users WHERE id=fixture.rh;
 IF hash<>extensions.crypt('Ensaio-Definitivo-83',hash) OR hash=extensions.crypt('Ensaio-Temporario-91',hash) THEN RAISE EXCEPTION 'Senha final incoerente'; END IF;
 IF EXISTS(SELECT 1 FROM public.profiles WHERE id=fixture.rh AND must_change_password) THEN RAISE EXCEPTION 'Troca segue pendente'; END IF;
 IF public.rh_account_context(fixture.rh) IS NULL THEN RAISE EXCEPTION 'Conta não restaurou escopo'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.audit_events WHERE entity_id=fixture.rh AND action='rh_provisional_password_changed')
  THEN RAISE EXCEPTION 'Auditoria ausente'; END IF;
END
$test$;
RESET ROLE;

SELECT set_config('request.jwt.claims',json_build_object('role','authenticated','sub',rh,'session_id',next_session)::text,true)
FROM sgfs_pilot_identity \gset
SET LOCAL ROLE authenticated;
DO $test$
BEGIN
 IF (public.sgfs_session_requirements()->>'accepted')::boolean THEN RAISE EXCEPTION 'Aceite atribuído a nova sessão'; END IF;
 BEGIN
  PERFORM public.sgfs_session_requirements('inexistente');
  RAISE EXCEPTION 'Versão incorreta aceita';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'SGFS_TERMS_VERSION_CHANGED' THEN RAISE; END IF; END;
 IF NOT (public.sgfs_session_requirements('2026-11-24')->>'accepted')::boolean THEN RAISE EXCEPTION 'Aceite não registrado'; END IF;
 IF NOT (public.sgfs_session_requirements()->>'accepted')::boolean THEN RAISE EXCEPTION 'Aceite não persistiu'; END IF;
END
$test$;

ROLLBACK;
