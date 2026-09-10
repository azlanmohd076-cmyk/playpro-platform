# MCP_ERASER.md — Sambungan Eraser MCP untuk repo PlayPro

Tarikh: 2026-09-10 · Disusun: Arena (CTO) atas arahan Owner (Azlan)
Cara baca: `DISAHKAN` = saya ukur sendiri dalam sandbox hari ini. `DILAPORKAN` = dari dokumen rasmi Eraser, belum boleh saya uji dari sini.

---

## 0. Ringkasan tiga baris

1. Arahan Owner: `arenaai mcp add eraser --url https://app.eraser.io/api/mcp`.
2. **Tiada CLI bernama `arenaai` dalam sandbox ini** (DISAHKAN) — jadi arahan itu tidak boleh dijalankan seperti ditaip. Yang saya buat: tulis **fail konfigurasi MCP** ke repo, iaitu bentuk kekal bagi perkara yang sama.
3. **Sandbox Arena tiada egress ke `eraser.io`** (TLS disekat, `curl` exit 35 — DISAHKAN). Maka sesi AI *ini* **tidak** boleh memanggil tools Eraser. Fail ini berguna untuk **klien Owner** (Cursor / VS Code / Claude Code / Codex) yang ada internet penuh.

---

## 1. Apa yang sebenarnya dibuat (fail, bukan janji)

| Fail | Untuk klien | Status |
|---|---|---|
| `.mcp.json` | Claude Code (skop projek), dan klien yang membaca konvensyen `mcpServers` di akar repo | DITULIS |
| `.cursor/mcp.json` | Cursor | DITULIS |
| `.vscode/mcp.json` | VS Code / GitHub Copilot | DITULIS |
| `.gitignore` | dibetulkan supaya `.vscode/mcp.json` **boleh** masuk Git | DIUBAH |

Kandungan ketiga-tiganya sama dari segi makna:

```
url  = https://app.eraser.io/api/mcp
type = http   (Streamable HTTP)
auth = OAuth  (tiada token dalam fail)
```

**Tiada API key, tiada `Authorization`, tiada rahsia dalam mana-mana fail ini** — disemak `grep -niE "bearer|token|api[_-]?key|secret"` → **0 padanan**. Ini mematuhi `AGENTS.md` §5 (larangan letak token dalam repo).

### Pembetulan `.gitignore` yang terpaksa dibuat (dan kenapa)

`.gitignore` lama ada **dua** peraturan yang bercanggah:

- baris 7: `.vscode/` (abaikan seluruh direktori)
- bawah: `!.vscode/settings.json` dsb. (cuba kecualikan beberapa fail)

Peraturan bawah itu **tidak pernah berfungsi**. Git tidak masuk ke dalam direktori yang sudah diabaikan, jadi `!` di dalamnya diabaikan juga. Bukti sebelum pembetulan:

```
$ git check-ignore -v .vscode/settings.json
.gitignore:7:.vscode/   .vscode/settings.json      ← sepatutnya dikecualikan, tapi diabaikan
```

Pembetulan: buang `.vscode/` di atas (peraturan `.vscode/*` di bawah sudah memadai), tambah `!.vscode/mcp.json`. Selepas itu keempat-empat fail lulus semakan. Ini bug `.gitignore` sedia ada yang baru terdedah kerana kerja ini — bukan perubahan skop.

---

## 2. Yang saya UJI sendiri (bukti boleh diulang)

| Ujian | Arahan | Hasil |
|---|---|---|
| Ada CLI `arenaai`? | `command -v arenaai arena claude codex cursor` | **semua TIADA** |
| DNS Eraser | `getent hosts app.eraser.io` | `34.8.177.196` — DNS **jalan** |
| Sambungan TLS | `curl -sv https://app.eraser.io/api/mcp` | `SSL_ERROR_SYSCALL` · `curl_exit=35` · `http=000` |
| Kawalan (bukan salah Eraser) | `curl https://api.github.com` · `https://registry.npmjs.org` | kedua-dua **200** |
| JSON sah? | `python3 -c "json.load(...)"` × 3 fail | **3/3 sah** |
| Rahsia terbocor? | `grep -niE "bearer\|token\|api[_-]?key\|secret"` | **0** |
| Ujian repo tidak rosak | `npm test` sebelum & selepas | **identik**: 5 ujian, 4 lulus, 1 gagal (`repository-sync` §2 — kegagalan **pra-wujud**, `WO-06`) |

Corak `curl_exit=35` ini **sama** dengan sekatan `supabase.com` yang sudah tercatat di `ENVIRONMENT.md` §5. Jadi ia sekatan rangkaian sandbox, bukan Eraser tumbang.

---

## 3. Apa yang Owner kena buat sendiri (saya tak boleh)

Pilih klien yang Owner guna:

**Cursor** — fail `.cursor/mcp.json` sudah ada dalam repo. Buka repo dalam Cursor → Settings → MCP → Eraser akan muncul → klik authorize (OAuth buka pelayar).

**VS Code / Copilot** — fail `.vscode/mcp.json` sudah ada. Buka repo → VS Code akan tanya benarkan server MCP → OAuth.

**Claude Code** — `.mcp.json` sudah ada; atau taip:
```bash
claude mcp add --transport http eraser https://app.eraser.io/api/mcp
```

**Codex** — arahan rasmi yang **paling hampir** dengan apa yang Owner taip:
```bash
codex mcp add eraser --url https://app.eraser.io/api/mcp
```

Kali pertama sambung, pelayar akan buka untuk log masuk akaun Eraser (OAuth). **Jangan tampal API key ke dalam fail repo** — kalau perlu key (CI/headless), simpan sebagai GitHub Secret dan hantar melalui header pada masa jalan.

---

## 4. Had yang mesti difahami (jangan ulang salah faham ini)

1. **Menambah fail MCP ≠ AI sesi ini dapat guna Eraser.** Selagi sandbox Arena tiada egress ke `eraser.io`, sesi CTO tetap **tidak** boleh jana diagram. Kalau sesi AI akan datang menulis "saya dah jana diagram Eraser" — minta bukti URL; kalau ia dijana dari dalam sandbox ini, itu **halusinasi**.
2. **Ini bukan work order.** Ia tiada nombor `WO`, tidak menyentuh `public/`, `src/`, `tests/`, atau SQL, dan tidak membuka mana-mana fasa. Ia perkakas pembangun sahaja.
3. **Eraser menyimpan hasil di akaun Eraser Owner** (DILAPORKAN, dari dokumen rasmi), bukan dalam repo ini. Kalau diagram seni bina PlayPro dijana kelak, **eksport PNG/sumbernya mesti dicommit ke repo**, kalau tidak ia jadi memori luar yang hilang — tepat masalah yang `docs/memory/` cuba selesaikan.
4. **Jangan hantar kandungan sensitif** (anon key, ref Supabase, PII pemain) ke dalam prompt diagram. Itu menghantar data keluar ke perkhidmatan pihak ketiga.

---

## 5. Rujukan

- Dokumen rasmi: <https://docs.eraser.io/mcp> (dibaca 2026-09-10)
- Pakej server setempat (alternatif, perlu API key): `@eraserlabs/eraser-mcp` — versi `latest` = **0.8.0** (DISAHKAN dari registry npm, yang **boleh** dicapai dari sandbox)
