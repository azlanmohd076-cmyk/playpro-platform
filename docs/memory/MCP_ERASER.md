# MCP_ERASER.md — Sambungan Eraser MCP untuk repo PlayPro

Tarikh: 2026-09-10 · Disusun: Arena (CTO) atas arahan Owner (Azlan)
Cara baca: `DISAHKAN` = saya ukur sendiri dalam sandbox hari ini. `DILAPORKAN` = dari dokumen rasmi Eraser, belum boleh saya uji dari sini.

---

## 0. Ringkasan tiga baris

1. Arahan Owner: `arenaai mcp add eraser --url https://app.eraser.io/api/mcp`.
2. **Tiada CLI bernama `arenaai` dalam sandbox ini** (DISAHKAN) — jadi arahan itu tidak boleh dijalankan seperti ditaip. Yang saya buat: tulis **fail konfigurasi MCP** ke repo, iaitu bentuk kekal bagi perkara yang sama.
3. **Sandbox Arena tiada egress ke `eraser.io`** (`curl` exit 35 — DISAHKAN). Maka sesi AI *ini* **tidak** boleh memanggil tools Eraser. Fail ini berguna untuk **klien Owner** (Cursor / VS Code / Claude Code / Codex) yang ada internet penuh.

> **Pembetulan 2026-09-11:** Eraser **tidak** disekat secara khusus. Ukuran lanjut menunjukkan sandbox ialah **allowlist** — hanya `api.github.com` + `registry.npmjs.org` lulus; `example.com`, `google.com`, `cloudflare.com`, `rapidapi.com` semuanya **000/exit 35** juga. Butiran: `ENVIRONMENT.md` §5.1. Implikasi: **tiada** MCP server luar boleh dipanggil dari sandbox, jadi jangan buang masa menyahpepijat sambungan.

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

## 4b. Peraturan am untuk **mana-mana** MCP server yang diminta selepas ini

Lahir daripada permintaan sebenar 2026-09-11 (RapidAPI / 1xBet). Tiga semakan, ikut turutan, sebelum satu baris konfigurasi ditulis:

**Semakan 1 — kelayakan (credential).** Kalau permintaan itu datang **bersama kunci API di dalam teks**, kunci itu dianggap **sudah terdedah** dan mesti **diputar (rotate)**, tak kira sama ada ia jadi digunakan atau tidak. Ia **tidak boleh** ditulis ke fail repo — `AGENTS.md` §5, dan repo ini **public** (`"visibility":"public"`, disahkan `gh api`). Corak selamat: OAuth; kalau wajib guna kunci, `${ENV_VAR}` atau GitHub Secret, tidak pernah teks mentah.

**Semakan 2 — kena-mengena dengan blueprint.** Adakah domain server itu wujud dalam PlayPro? Cara semak: `grep -rniE "<konsep>" --include=*.md docs/`. Kalau **0 padanan**, ia bukan sambungan — ia **skop baharu**, dan skop baharu = work order + kelulusan CEO/Owner (`AGENTS.md` §4), bukan "cuba dulu".

> ⚠️ **Amaran khusus data pertaruhan / odds.** PlayPro ialah platform **akar umbi** yang menyimpan `date_of_birth` dan mengira kategori umur seperti **B18** (`DECISIONS.md`:221) — bermakna **kanak-kanak bawah umur** ada dalam pangkalan data. Menyambungkan suapan odds pertaruhan kepada sistem yang sama menimbulkan tiga risiko berasingan: **(a)** perlindungan kanak-kanak dan integriti pertandingan (odds + statistik pemain bawah umur dalam satu sistem); **(b)** undang-undang Malaysia — perjudian dalam talian adalah **kesalahan** di bawah Betting Act 1953 / Common Gaming Houses Act 1953, dan MCMC menyekat laman perjudian; **(c)** reputasi — repo ini **public**, jadi sebarang commit yang menyebut integrasi pertaruhan kekal dalam sejarah awam. CTO **tidak** memberi nasihat undang-undang; yang dicatat di sini ialah **risiko yang mesti diputuskan Owner secara bertulis**, bukan diputuskan oleh AI dalam satu baris chat.

**Semakan 3 — boleh dicapai?** `curl -s -o /dev/null -m 10 -w "%{http_code}" <url>`. Ingat `ENVIRONMENT.md` §5.1: sandbox ialah **allowlist** (GitHub + npm sahaja). Jawapannya hampir pasti `000`. Konfigurasi masih boleh ditulis untuk klien Owner, tetapi **jangan** dakwa ia "diuji".

**Catatan bentuk konfigurasi:** corak `npx mcp-remote <url> --header ...` (pakej `mcp-remote`, versi `latest` = **0.8.6**, DISAHKAN dari npm) ialah jambatan **stdio → HTTP jauh** untuk klien yang tidak menyokong HTTP asli. Ia meletakkan kunci sebagai **argumen baris arahan**, yang bocor ke senarai proses (`ps aux`) dan sering ke log shell. Kalau kunci memang perlu, `env` lebih selamat daripada `--header`.

---

## 5. Rujukan

- Dokumen rasmi: <https://docs.eraser.io/mcp> (dibaca 2026-09-10)
- Pakej server setempat (alternatif, perlu API key): `@eraserlabs/eraser-mcp` — versi `latest` = **0.8.0** (DISAHKAN dari registry npm, yang **boleh** dicapai dari sandbox)
