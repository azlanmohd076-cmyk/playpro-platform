# INDEX_HTML_MAP.md — Peta `public/index.html` + pelan pemecahan (WO-03)

Diukur oleh CTO (Arena) pada 2026-09-10, HEAD `23569ac`. **Semua nombor boleh dihasilkan semula** (arahan disertakan). Jangan petik nombor dari sini tanpa Arahan.

---

## 1. Hakikat fail (yang membatalkan andaian lama)

| Metrik | Nilai | Arahan sahkan |
|---|---|---|
| Saiz | **1,204,835 baita** | `wc -c < public/index.html` |
| Baris | **6,128** | `awk 'END{print NR}' public/index.html` |
| Tag `<script>` | 10 (6 daripadanya `src=` luar) | `grep -c "<script" public/index.html` |
| CSS dalam `<style>` | **71,194 B (5.9%)** | lihat §4 skrip |
| JS dalam `<script>` | **160,556 B (13.3%)** | lihat §4 skrip |
| "HTML" baki | **973,085 B (80.8%)** → **tetapi 873,460 B daripadanya = 4 gambar base64** | §2 |
| Fungsi/arrows pada indentasi-0 | 128 | `grep -cE "^(async )?function \|^const \|^let \|^var "` (anggaran) |
| Semua kemunculan `function` | 199 | `grep -o function public/index.html \| wc -l` |
| Rujukan DOM | 314 | `grep -o 'getElementById\|querySelector' public/index.html \| wc -l` |
| **Fungsi unik yang dipanggil inline `on*=`** | **71** | §4 skrip |
| Jumlah atribut `on*=` | 172 | §4 skrip |
| `addEventListener` | 10 | — |
| `window.X =` (global disengajakan) | 16 nama unik | — |
| `localStorage` | 26 · `sessionStorage` | 1 |
| Tag paling kerap | `div` 926 · `span` 215 · `option` 76 · `input` 59 · `button` 53 | — |

### Kesimpulan CTO (ini yang penting)

> **`index.html` bukan "fail kod yang besar". Ia fail HTML biasa bersaiz 331 KB yang kebetulan menggendong 873 KB gambar yang ditempel sebagai base64.**
> 72.5% isinya = 4 keping JPEG. **73% daripada sebab AI "buta" terhadap aplikasi anda ialah gambar, bukan logik.**

---

## 2. Enam baris yang menjelaskan semuanya

| Baris | Isi | Baita base64 | JPEG sebenar | Catatan |
|---|---|---|---|---|
| 1602 | `<img id="splash-bg" src="data:image/jpeg;base64,…">` | **513,088** | 384,814 B | **satu baris ini = 42.6% fail.** Latar skrin pembukaan (splash) |
| 1605 | `<img class="sp-logo-img" src="data:…">` | 120,124 | 90,091 B | logo |
| 1619 | `<img src="data:…">` (dalam modal) | 120,124 | **sama** | ⚠️ **duplikat bit-demi-bit** (md5 `da3f7d647592`) |
| 1657 | `<img class="hdr-logo-img" src="data:…">` | 120,124 | **sama** | ⚠️ **duplikat kali ke-3** |
| 4 | `<link rel="icon" href="data:image/svg+xml,…">` | kecil | — | favicon SVG inline — **tinggalkan**, tiada nilai |
| 1478 | `background:url("data:image/svg+xml,…")` | kecil | — | tekstur CSS — **tinggalkan** |

**Dua penemuan bebas nilai:**
1. **Logo yang sama disalin 3 kali** (md5 identik `da3f7d647592`) → **240,248 baita** adalah pembaziran tulen dalam satu halaman.
2. **Hanya `index.html` yang terjejas.** 17 halaman HTML lain dalam `public/` mengandungi **0** blob base64 (`grep -l 'data:image/[a-z+]*;base64,' public/*.html` → `public/index.html` sahaja). Jadi skop WO-03a = **satu fail**.

Kesan pengguna sebenar (bukan estetik): base64 dalam HTML **tidak boleh di-cache secara berasingan** — setiap kali muat halaman, 873 KB "gambar" itu dihantar semula bersama HTML. Di rangkaian 4G kampung yang anda sasarkan, itu beza antara "laju buka" dan "lama sangat, aku tutup".

---

## 3. Pelan pecahan 3 langkah (mengikut risiko, bukan mengikut keindahan)

### 🔵 `WO-03a` — Luaarkan aset (nilai terbesar, risiko paling rendah) — **BOLEH DILAKUKAN SEKARANG**

Ganti 4 nilai `src="data:image/jpeg;base64,…"` dengan **2 fail**: `public/assets/splash.jpg` (384,814 B) dan `public/assets/logo.jpg` (90,091 B, dirujuk 3×). **Tiada satu baris JS/CSS/logik pun berubah.**

**Dry-run yang sudah saya jalankan (di luar repo, `main` tidak disentuh):**

```
index.html : 1,204,835 → 331,345 baita   (-72.5%)
baris      : 6,128 → 6,128   (tidak berubah — hanya 4 atribut src bertukar)
rujukan    : src="assets/logo.jpg" ×3 · src="assets/splash.jpg" ×1
data URI base64 jpeg baki: 0 (2 SVG kecil sengaja ditinggalkan)
npm test   : ASAL  → tests 5 / pass 4 / fail 1
             PECAH → tests 5 / pass 4 / fail 1     ← IDENTIK (kegagalan sama, pra-wujud: repository-sync §2)
                 + 3 suite lain (auth 52/52 · obcomplete 34/34 · server 3/3) tidak terjejas
```

Bukti kegagalan adalah sama = guard `tests/repository-sync.test.js` membaca **badan `obComplete()`** dan salinan `js/` — **dua-dua tidak disentuh** oleh WO-03a. Itu sebabnya pengesahan ini sah.

**Prosedur tetap untuk yang melaksana (jangan improvisasi):**
1. Decode setiap `data:image/jpeg;base64,…` → fail di `public/assets/`; sahkan `md5` output == sumber (dedup 3 logo ke 1 fail).
2. Ganti **hanya** atribut `src=` dengan `assets/<nama>.jpg` (laluan relatif — `vercel.json` `outputDirectory: public`).
3. `npm test` mesti kekal **5/4/1** (jika jadi 5/3/2 → batal).
4. Buka `index.html` setempat dan sahkan 2 gambar keluar dalam tab Network (`/assets/*.jpg` 200).
5. Satu PR khas untuk ini. Tiada kerja lain dibenarkan masuk PR yang sama.

### 🟡 `WO-03b` — Modularisasi JS (lepas WO-03a + lepas CI `WO-05` wujud)

Baki JS = 160 KB / **128** fungsi tingkat-atas. Kekangan keras yang mesti dihormati:

- **71 fungsi unik dipanggil terus daripada atribut `onclick`/`onchange` dalam HTML** (172 pemanggilan).-inline handler hanya boleh nampak fungsi **global**. Jadi setiap modul baharu wajib `window.namaFungsi = namaFungsi` untuk senarai itu (senarai tepat boleh dijana: §4 arahan G1), **atau** semua inline handler dirombak kepada `addEventListener` — dan rombakan itu **bukan** kerja "sambil lalu".
- 16 `window.X =` sedia ada + 30 pemboleh ubah `var/let/const` tingkat-atas → bergantung pada **tertib pemuatan** skrip. Pecah = tetapkan tertib; jangan `type="module"` dulu (`defer`/`async` akan mengubah masa eksekusi dan `init` halaman akan pecah diam-diam).
- 26 penggunaan `localStorage` termasuk auto-seed `PLAYPRO_REGISTRY_V3` (baris ~4302) → itu **WO-02**, jangan dibincang dalam WO-03b.
- Ada **pasangan duplikat** `js/*.js` ↔ `public/js/*.js` (md5 sama hari ini) dan `src/` ≠ `public/src/` (drift). Jangan tambah salinan ketiga.

Cadangan sempadan modul (mengikut apa yang ada, bukan idealistik): `shell.js` (header/footer/nav/toast) · `public-portal.js` (baris ~2700–2900: standings/fixtures/scorers/suspensions) · `coach-assess.js` (~3600–4000: `muatFormPenilaianCoach`, `ca-*`) · `profile-dna.js` (~4200–4500: registry + bio2) · `onboarding.js` (`obComplete` ~5000–5075) · `match-observer.js` (`match_observer.html` sudah asing) — **6 modul, setiap satu PR sendiri, satu-satu.**

### ⚪ `WO-03c` — Optimum gambar (pilih sendiri)

`logo.jpg` 90 KB untuk imej header = terlebih saiz; `splash` 385 KB juga besar. Penjimatan wajar: ~300–500 KB **lagi** selepas WO-03a, tetapi ia **mengubah rupa** (kualiti/kecerahan) → keputusan Owner, bukan CTO. Format disyorkan: WebP/AVIF dengan fallback JPEG; jangan tukar logo kepada SVG tanpa anda lihat sendiri hasilnya.

---

## 4. Arahan jana semula semua nombor di atas

```bash
# saiz/baki/klasifikasi
F=public/index.html; wc -c < $F; awk 'END{print NR}' $F
# G1: senarai fungsi yang WAJIB kekal global (dipanggil inline handler)
grep -oE 'on(click|change|input|submit|blur|focus|key(up|down)|load)="[^"]*"' $F \
  | grep -oE '[A-Za-z_$][A-Za-z0-9_$]*\s*\(' | tr -d ' (' | sort -u
# G2: berapa baris & baita bagi setiap blok <style>/<script>
python3 - <<'PY'
import re
t=open('public/index.html',encoding='utf-8',errors='replace').read()
def inside(tag):
    tot=0; on=False
    for l in t.split('\n'):
        if re.search(r'<'+tag+r'\b',l) and 'src=' not in l: on=True; continue
        if '</'+tag+'>' in l: on=False; continue
        if on: tot+=len(l.encode())
    return tot
css=inside('style'); js=inside('script')
b64=sum(len(m.group(1)) for m in re.finditer(r'src="data:image/jpeg;base64,([A-Za-z0-9+/=]+)"',t))
print(f"CSS {css:,}  JS {js:,}  base64 {b64:,}  HTML tulen {len(t.encode())-css-js-b64:,}")
import hashlib,base64
for m in re.finditer(r'src="data:image/jpeg;base64,([A-Za-z0-9+/=]+)"',t):
    d=base64.b64decode(m.group(1)+'='*(-len(m.group(1))%4))
    print("baris",t[:m.start()].count('\n')+1,len(d),"B  md5",hashlib.md5(d).hexdigest()[:12])
PY
# G3: pastikan tiada halaman lain terjejas
for f in $(git ls-files 'public/*.html'); do printf "%s %s\n" "$(grep -c 'data:image/[a-z+]*;base64,' $f)" "$f"; done | grep -v "^0 "
# G4: gerbang ujian (sebelum & selepas mesti sama)
npm test
```

---

## 5. Had jujurnya (baca sebelum gembira)

1. Selepas WO-03a, `index.html` tetap **331 KB / 6,128 baris**. Itu **masih terlalu besar** untuk dibaca penuh dalam satu pusingan oleh kebanyakan alat AI. Ia jadi 3.6× lebih baik, **bukan** selesai. Sebab itu `WO-03b` tetap perlu — dan sebab itulah dokumen memori ini (55 KB) lebih penting daripada apa-apa rombakan UI.
2. Tiada satu pun nombor dalam fail ini yang membuktikan apl itu *betul* — hanya bahawa ia *besar* dan *di mana* besarnya. Logik perniagaan masih belum diuji hujung-ke-hujung (MA-01…MA-04).
3. `WO-03a` belum dilakukan. Ia **belum** mendapat kelulusan untuk masuk `main` — sesi Arena ini terikat pada satu branch kerja, maka ia mesti jadi **PR kod berasingan** selepas PR #5 digabung (atau selepas `WO-05` CI siap, itu lebih selamat). Saya sediakan prosedur supaya sesi itu jadi kerja 20 minit, bukan 20,000 token spekulasi.
