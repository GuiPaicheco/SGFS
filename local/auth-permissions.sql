-- Execute como administrador do banco integrado, após o Auth e as migrações.
BEGIN;

GRANT USAGE ON SCHEMA auth, extensions TO service_role;
GRANT SELECT (id, encrypted_password), UPDATE (encrypted_password, updated_at)
  ON auth.users TO service_role;
GRANT SELECT (id, user_id, not_after), DELETE ON auth.sessions TO service_role;

DO $check$
BEGIN
  IF NOT has_column_privilege('service_role', 'auth.users', 'encrypted_password', 'UPDATE')
     OR NOT has_column_privilege('service_role', 'auth.users', 'updated_at', 'UPDATE')
     OR NOT has_table_privilege('service_role', 'auth.sessions', 'DELETE') THEN
    RAISE EXCEPTION 'Execute auth-permissions.sql como administrador com autoridade sobre os objetos do Auth.';
  END IF;
END
$check$;

COMMIT;
