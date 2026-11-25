"""Check local recovery against the capture-only SMTP server."""
import base64
import hashlib
import hmac
import json
import time
import uuid
import html
import re
import secrets
import subprocess
import os
from urllib.parse import parse_qs, urlsplit

import httpx

BASE = "http://127.0.0.1:8089/SGFS/"
MAIL = "http://127.0.0.1:19026/api/v1/"
EMAIL = "sgfs-recuperar-local@example.com"
IDENTIFIER = "sgfs-recuperar-local"
USER_ID = "29000000-0000-4000-a000-000000000005"


def sql(text):
    subprocess.run([
        os.environ["SGFS_PSQL"], "-h", "127.0.0.1", "-p", "55432",
        "-d", "sgfs_integrado", "-U", "postgres", "-w", "-Xq",
        "-v", "ON_ERROR_STOP=1",
    ], check=True, input=text, text=True)


def admin_key():
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
    data = encode(b'{"alg":"HS256","typ":"JWT"}') + b"." + encode(json.dumps({
        "role": "service_role", "iss": "sgfs", "exp": int(time.time()) + 600,
    }).encode())
    return (data + b"." + encode(hmac.new(os.environ["SGFS_TEST_JWT_SECRET"].encode(), data, hashlib.sha256).digest())).decode()


def run():
    password = secrets.token_hex(16)
    with httpx.Client(timeout=25, trust_env=False) as client:
        created = client.post(BASE + "backend/auth/v1/admin/users",
                              headers={"Authorization": "Bearer " + admin_key()}, json={
                                  "email": EMAIL, "password": password, "email_confirm": True,
                                  "user_metadata": {"full_name": "Admin de ensaio"},
                              })
        assert created.status_code in (200, 201), f"Usuário sintético HTTP {created.status_code}"
        user_id = uuid.UUID(created.json()["id"])
    try:
        sql(f"""
INSERT INTO public.profiles(id,full_name,role,roles,login_identifier,email,must_change_password)
VALUES ('{user_id}','Admin de ensaio','administrador',ARRAY['administrador'::public.app_role],
        '{IDENTIFIER}','{EMAIL}',false)
ON CONFLICT(id) DO UPDATE SET role=excluded.role,roles=excluded.roles,
    login_identifier=excluded.login_identifier,email=excluded.email,must_change_password=false;
""")
        check = subprocess.run([
            os.environ["SGFS_PSQL"], "-h", "127.0.0.1", "-p", "55432",
            "-d", "sgfs_integrado", "-U", "postgres", "-w", "-XqAt",
            "-c", f"SELECT count(*) FROM public.profiles WHERE id='{user_id}' AND login_identifier='{IDENTIFIER}'",
        ], check=True, capture_output=True, text=True)
        assert check.stdout.strip() == "1", "Identificador sintético não persistiu"
        verify_recovery(password)
    finally:
        sql(f"BEGIN; DELETE FROM public.audit_events WHERE actor_id='{user_id}'; DELETE FROM auth.users WHERE id='{user_id}'; COMMIT;")


def verify_recovery(password):

    message = None
    try:
        auth_url = BASE + "backend/functions/v1/access-auth"
        with httpx.Client(timeout=30, trust_env=False) as client:
            initial = client.post(auth_url, json={
                "action": "login", "identifier": IDENTIFIER, "password": password,
            })
            assert initial.status_code == 200, f"Login inicial do perfil sintético HTTP {initial.status_code}"
            response = client.post(auth_url, json={
                "action": "recover", "identifier": EMAIL, "redirectTo": BASE,
            })
            assert response.status_code == 200, f"Recuperação HTTP {response.status_code}: {response.json().get('error')}"
            messages = client.get(MAIL + "messages").raise_for_status().json()["messages"]
            message = next((row for row in messages if any(to["Address"] == EMAIL for to in row["To"])), None)
            assert message, "Mensagem ausente na caixa local"
            content = client.get(MAIL + "message/" + message["ID"]).raise_for_status().json()
            link = re.search(re.escape(BASE) + r'backend/auth/v1/verify\?[^"\s<>]+', html.unescape(content["HTML"]))
            assert link, "Link de recuperação incompatível com /SGFS/"
            verification = client.get(link.group())
            redirect = verification.headers.get("Location", "")
            target = urlsplit(redirect)
            assert redirect, f"Verificação HTTP {verification.status_code}, sem redirecionamento"
            assert redirect.startswith(BASE), f"Destino de recuperação HTTP {verification.status_code}: {target.scheme} {target.netloc} {target.path}"
            token = parse_qs(urlsplit(redirect).fragment).get("access_token", [None])[0]
            assert token, "Sem sessão ao verificar o link"
            new_password = secrets.token_hex(16)
            def accept(session_token):
                response = client.post(BASE + "backend/rest/v1/rpc/sgfs_session_requirements",
                    headers={"Authorization": "Bearer " + session_token},json={"accept_version":"2026-11-24"})
                assert response.is_success and response.json()["accepted"], "Aceite da sessão não registrado"
            accept(token)
            updated = client.post(auth_url, headers={"Authorization": "Bearer " + token},
                                  json={"action": "change-password", "password": new_password})
            assert updated.status_code == 200, f"Troca de senha HTTP {updated.status_code}"
            login = client.post(auth_url, json={
                "action": "login", "identifier": IDENTIFIER, "password": new_password,
            })
            assert login.status_code == 200, f"Login com nova senha HTTP {login.status_code}"
            headers = {"Authorization": "Bearer " + login.json()["access_token"], "x-sgf-role": "administrador"}
            accept(login.json()["access_token"])
            directory = client.post(BASE + "backend/functions/v1/manage-rh",
                                    headers=headers, json={"action": "directory"})
            assert directory.status_code == 200, f"Diretório de Administração HTTP {directory.status_code}"
            assert len(directory.json().get("units", [])) >= 42
            if os.getenv("SGFS_TEST_CNES") == "1":
                headers["apikey"] = "local"
                response = client.get(BASE + "api/cnes", params={"cnes": "6305245"},
                                      headers=headers, timeout=155)
                assert response.status_code == 200, f"Coleta CNES HTTP {response.status_code}"
                assert response.json()["metadados"]["completo_no_escopo_solicitado"]
                print("OK: coleta CNES real pela rota protegida local.")
        print("OK: recuperação por e-mail local, troca de senha, login e diretório da Administração.")
    finally:
        if message is not None:
            httpx.delete(MAIL + "message/" + message["ID"], trust_env=False)



if __name__ == "__main__":
    run()
