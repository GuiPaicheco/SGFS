"""Exercise the original interface against the isolated PostgreSQL copy."""
import os
from pathlib import Path
from urllib.parse import urlsplit

from playwright.sync_api import expect, sync_playwright

SITE = "http://127.0.0.1:8089/SGFS/"
CHROME = Path(os.environ["ProgramFiles"]) / "Google/Chrome/Application/chrome.exe"
REFERENCE = "Ensaio navegador SGFS"
DAY = "2098-11-19"


def large_calendar(page):
    rows = page.locator(".rh-calendar tbody tr")
    fixture = {"total": 1241, "overlap": False}

    def simulate_calendar(route):
        payload = route.request.post_data_json
        if not payload or payload.get("action") != "calendar":
            route.continue_()
            return
        size = payload["pageSize"]
        skip = payload["page"] * size
        start = payload["start"] if payload["mode"] == "range" else payload["month"] + "-01"
        end = payload["end"] if payload["mode"] == "range" else None
        route.fulfill(json={
            "context": {"cnes_name":"Unidade de ensaio"}, "total": fixture["total"],
            "employees": [{"row_id":str(i),"bond_id":f"bond-{i}","full_name":f"Profissional fictício {i+1}"} for i in range(skip,min(fixture["total"],skip+size))],
            "range_start":start if end else None,"range_end":end,
            "holidays":[],"absences":[{"id":str(i),"bond_id":"bond-0","origin":"rh","type":kind,
                "protocol":"Ensaio "+str(i),"start_date":start,"end_date":start}
                for i,kind in enumerate(("folga","afastamento"))] if fixture["overlap"] else [],"facets":{},"conflicts":[],
        })

    page.route("**/backend/functions/v1/manage-rh", simulate_calendar)
    page.select_option("#rh-calendar-size", "10")
    expect(rows).to_have_count(10)
    for size in (20,30,50,80,130):
        page.select_option("#rh-calendar-size", str(size))
        expect(rows).to_have_count(size)
    page.select_option("#rh-calendar-size", "all")
    for amount in [*range(100,1250,50),1241]:
        sentinel=page.locator("#rh-calendar-more")
        sentinel.evaluate("(el)=>el.scrollIntoView({block:'center'})")
        try:
            page.wait_for_function("(amount)=>document.querySelectorAll('.rh-calendar tbody tr').length>=amount",arg=amount,timeout=4000)
        except Exception:
            more=sentinel.get_by_role('button',name='Carregar mais profissionais')
            if more.is_visible():
                more.click()
            try:
                page.wait_for_function("(amount)=>document.querySelectorAll('.rh-calendar tbody tr').length>=amount",arg=amount,timeout=4000)
            except Exception:
                raise AssertionError(f"Paginação {amount}: {sentinel.inner_text()}") from None
    expect(rows).to_have_count(1241)
    print("OK: 1241 profissionais exibidos.",flush=True)
    page.set_viewport_size({"width":1440,"height":900})
    for month,days in [("2025-02",28),("2024-02",29),("2026-04",30),("2026-07",31)]:
        fixture["total"]=2
        page.fill("#rh-calendar-month",month)
        page.locator("#rh-calendar-filter").evaluate("(form)=>form.requestSubmit()")
        expect(rows).to_have_count(2)
        expect(page.locator(".rh-calendar thead th.rh-day")).to_have_count(days)
        page.wait_for_function("()=>{ const el=document.querySelector('.rh-calendar-wrap'); return el.scrollWidth<=el.clientWidth+2 }",timeout=4000)
    fixture["overlap"]=True
    page.locator("#rh-calendar-filter").evaluate("(form)=>form.requestSubmit()")
    overlap=page.locator('[data-rh-day-record]').first
    overlap.press("Enter")
    choices=page.get_by_role("dialog",name="Selecione o lançamento")
    expect(choices.locator("[data-rh-choice]")).to_have_count(2)
    page.keyboard.press("Escape")
    fixture["overlap"]=False
    page.set_viewport_size({"width":390,"height":800})
    assert page.locator(".rh-calendar-wrap").evaluate("(el)=>el.scrollWidth > el.clientWidth")
    assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth")
    page.select_option("#rh-calendar-mode","range")
    page.fill("#rh-calendar-start","2026-02-01")
    page.fill("#rh-calendar-end","2026-03-31")
    page.locator("#rh-calendar-filter").evaluate("(form)=>form.requestSubmit()")
    expect(page.locator(".rh-calendar thead th.rh-day")).to_have_count(59)
    fixture["total"]=0
    page.locator("#rh-calendar-filter").evaluate("(form)=>form.requestSubmit()")
    expect(rows).to_have_count(0)
    page.select_option("#rh-calendar-mode","month")
    page.set_viewport_size({"width":1440,"height":900})
    page.unroute("**/backend/functions/v1/manage-rh",simulate_calendar)
    print("OK: paginação, 1241 linhas, calendário de 28 a 31 dias e rolagem móvel.",flush=True)


def run():
    password = os.environ["SGFS_TEST_PASSWORD"]
    blocked = []
    errors = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(executable_path=CHROME, headless=True)
        page = browser.new_page()

        def local_only(route):
            parsed = urlsplit(route.request.url)
            if parsed.netloc == "127.0.0.1:8089" and parsed.path.startswith("/SGFS"):
                route.continue_()
            else:
                blocked.append(parsed.netloc)
                route.abort()

        page.route("**/*", local_only)
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(SITE, wait_until="domcontentloaded",timeout=60000)
        page.get_by_role("button", name="Recusar").click()
        page.get_by_role("button", name="Ler termos e continuar").click()
        page.get_by_role("button", name="Aceitar e continuar").click()
        page.get_by_role("dialog", name="Novidades da versão").get_by_role("button", name="Fechar").click()
        page.locator('[data-go="login"]').first.click()
        page.select_option("#access-identifier", "DAPS")
        page.fill("#access-password", password)
        with page.expect_response(lambda response: response.url.endswith("/functions/v1/access-auth")
                                  and response.request.method == "POST") as login:
            page.locator("#login-form button[type=submit]").click()
        assert login.value.ok, f"Login HTTP {login.value.status}: {login.value.json().get('error')}"
        headers = {"Authorization": "Bearer " + login.value.json()["access_token"],
                   "x-sgf-role": "rh", "apikey": "local"}
        before = page.request.post(SITE + "backend/functions/v1/manage-rh", headers=headers, data={"action":"session"})
        assert before.status == 403, "A sessão sem aceite acessou a API do RH"
        page.get_by_role("button", name="Aceitar e continuar").click()
        operator = page.locator("#rh-operator")
        expect(operator).to_be_visible(timeout=20000)
        operator.select_option(index=1)
        page.locator("#rh-operator-form button").click()
        expect(page.locator("#rh-calendar-filter")).to_be_visible(timeout=20000)
        page.locator("#rh-calendar-size").wait_for()
        assert page.locator("#rh-calendar-size").input_value() == "10"
        assert page.locator(".rh-calendar tbody tr").count() == 10
        page.select_option("#rh-calendar-size", "20")
        expect(page.locator(".rh-calendar tbody tr")).to_have_count(20)
        page.select_option("#rh-calendar-size", "all")
        page.locator("#rh-calendar-more").scroll_into_view_if_needed()
        expect(page.locator(".rh-calendar tbody tr")).to_have_count(100, timeout=20000)
        if os.environ.get("SGFS_TEST_SCALE") == "1":
            large_calendar(page)
        page.locator('[data-go="rh-launch"]').first.click()
        expect(page.locator("#rh-launch-search")).to_be_visible(timeout=20000)
        page.locator('[data-record-entry]').first.click()
        page.get_by_role('heading', name='Registros do profissional').wait_for()
        page.locator('#rh-history-prev').wait_for()
        page.locator('#rh-history-back').click()
        page.locator('#rh-launch-search').wait_for()
        if os.environ.get("SGFS_TEST_WRITE") == "1":
            launch = page.locator('[data-occurrence-type="folga"]:enabled').first
            written_entry=launch.get_attribute("data-occurrence-entry")
            launch.click()
            expect(page.locator("#occurrence-month")).to_be_enabled(timeout=20000)
            page.fill("#occurrence-month", DAY[:7])
            page.dispatch_event("#occurrence-month", "change")
            page.locator(f'[data-folga-day="{DAY}"]').click()
            page.fill("#occurrence-reference", REFERENCE)
            page.locator("#occurrence-form button:not([type=button])").click()
            with page.expect_response(lambda response: response.url.endswith("/functions/v1/manage-rh")
                                      and "record-absence" in (response.request.post_data or "")) as saved:
                page.locator("#occurrence-save").click()
            assert saved.value.ok, f"Gravação HTTP {saved.value.status}"
            record_protocol="RH-"+saved.value.json()["id"].replace("-","")[:12].upper()
            page.locator('[data-go="rh-launch"]').first.click()
            page.locator(f'[data-record-entry="{written_entry}"]').click()
            page.get_by_text(record_protocol,exact=False).wait_for()
            page.locator('#rh-history-back').click()

        record = os.environ.get("SGFS_TEST_RECORD")
        if os.environ.get("SGFS_TEST_WRITE") == "1":
            record = saved.value.json()["id"]
        if record:
            page.locator('[data-go="rh-workspace"]').first.click()
            expect(page.locator("#rh-calendar-month")).to_be_visible(timeout=20000)
            page.fill("#rh-calendar-month", DAY[:7])
            page.locator("#rh-calendar-filter").evaluate("(form) => form.requestSubmit()")
            mark = page.locator(f'[data-rh-day-record*="{record}"]').first
            mark.wait_for(state="visible", timeout=20000)
            mark.press("Enter")
            page.get_by_role("heading",name="Registro de afastamento").wait_for()
            page.locator("#rh-detail-back").click()
            for extension in ("xlsx", "pdf"):
                with page.expect_download(timeout=30000) as exported:
                    page.locator("#rh-export-" + extension).click()
                assert exported.value.suggested_filename.endswith("." + extension)


        headers = {"Authorization": "Bearer " + login.value.json()["access_token"],
                   "x-sgf-role": "rh", "apikey": "local"}
        forbidden = page.request.get(SITE + "api/cnes?cnes=6305245", headers=headers)
        assert forbidden.status == 403, f"CNES aceitou RH: HTTP {forbidden.status}"
        if os.environ.get("SGFS_TEST_OTHER_ENTRY"):
            denied_history=page.request.post(SITE+"backend/functions/v1/manage-rh",headers=headers,data={
                "action":"record-history","entryId":os.environ["SGFS_TEST_OTHER_ENTRY"],"page":0,
            })
            assert denied_history.status==403,"Histórico de outra unidade disponível ao RH"
        scoped = page.request.post(SITE + "backend/functions/v1/manage-rh", headers=headers, data={
            "action": "calendar", "mode": "month", "month": DAY[:7], "page": 0,
            "search": "", "filters": {}, "cnes": "6305245",
        })
        assert scoped.ok and scoped.json()["context"]["cnes_code"] == "2126486", "RH acessou outra unidade"

        assert not blocked, f"Origens externas bloqueadas: {sorted(set(blocked))}"
        assert not errors, errors
        browser.close()
    print("OK: interface original, login DAPS, identificação do operador, calendário e fluxo de lançamento locais.")


if __name__ == "__main__":
    run()
