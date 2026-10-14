# entware-offline: отдельный репозиторий — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Перенести сборку, проверку и публикацию офлайн-установщиков Entware из z2k в отдельный публичный репозиторий `necronicle/entware-offline`, а в z2k, d2k и keenetic-doq оставить ссылки.

**Architecture:** Четыре POSIX-sh скрипта без общего состояния: `build.sh` (сборка одной архитектуры), `smoke.sh` (установка без сети в chroot), `publish.sh` (решение «выпускать ли» и создание датированного релиза), `tests/test_build.sh` и `tests/test_publish.sh` (на поддельном зеркале и поддельном `gh`). Workflow GitHub Actions склеивает их. Три чужих репозитория получают по одному коммиту в README.

**Tech Stack:** POSIX sh, awk, curl, tar, gzip, shellcheck, GitHub Actions, `gh`, qemu-user-static (только в CI), git worktree для z2k.

**Spec:** `docs/superpowers/specs/2026-10-14-entware-offline-repo-design.md`

## Global Constraints

- Все скрипты — POSIX sh (`#!/bin/sh`), без bashизмов; проверка `shellcheck -s sh`.
- Каталог локального фида внутри архива: `/opt/var/entware-offline`. Слово «z2k» в скриптах и в правке `bin/install` не встречается.
- Имена файлов релиза не меняются: `<arch>-installer.tar.gz`, `<arch>-installer.manifest`, `<arch>-installer.install.diff`, `ALL.manifest`; `<arch>` ∈ `aarch64`, `mipsel`, `mips`.
- Тег релиза: дата UTC `YYYY-MM-DD`; при занятом теге `YYYY-MM-DD-2`, `-3`, … Релиз помечается Latest.
- Постоянные ссылки: `https://github.com/necronicle/entware-offline/releases/latest/download/<arch>-installer.tar.gz`.
- Коммиты и тексты по-русски. Коммиты заканчиваются строкой `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Локальный чекаут `/Library/Zapret2/z2k` не трогать (чужие правки, отстал на 47 коммитов): работа в worktree от `origin/z2k-staging`. Локальный чекаут `/Library/Zapret2/d2k` не трогать (ветка `classify-core`, которой нет на origin): клон во временный каталог.
- В z2k перед пушем — `sh scripts/ci_local.sh` целиком (правило из памяти: полный CI на финальном дереве).
- Старый релиз `entware-offline` в z2k не удалять.

## Review Focus

1. Второй запуск публикации в один день после смены состава (тег даты занят) должен дать тег `-2`, а не упасть. Тест в задаче 3.
2. Первая публикация в пустом репозитории (нет ни одного релиза, `gh release download` без тега падает) должна создать релиз, а не выйти с «не изменилось». Тест в задаче 3.
3. Состав не изменился — скрипт выходит с кодом 0 и не создаёт релиз, иначе понедельничный запуск плодит пустые релизы. Тест в задаче 3.
4. Относительный каталог вывода (так его передаёт workflow) у `build.sh` обязан работать. Тест в задаче 1 (перенесён из z2k).
5. `smoke.sh` на машине без qemu/binfmt не может быть проверен локально; в CI он падает понятно (`установщик завершился успешно` FAIL с логом). Локальная проверка задачи 2 — `shellcheck` и `sh -n`, живая — только в CI (задача 5).

---

### Task 1: build.sh и tests/test_build.sh

**Files:**
- Create: `build.sh`
- Create: `tests/test_build.sh`
- Create: `.gitignore`

**Interfaces:**
- Produces: `sh build.sh <aarch64|mipsel|mips> <каталог-вывода>`; переменная `ENTWARE_BASE` (по умолчанию `https://bin.entware.net`) для поддельного зеркала. Кладёт в каталог вывода `<arch>-installer.tar.gz`, `<arch>-installer.manifest`, `<arch>-installer.install.diff`. Архив содержит фид в `var/entware-offline/{entware,keendev}` и `var/entware-offline/MANIFEST`.

- [ ] **Step 1: Взять тест из z2k и переписать пути**

```bash
cd /Library/Zapret2/entware-offline
mkdir -p tests
git -C /Library/Zapret2/z2k show origin/z2k-staging:tests/test_entware_offline_build.sh > tests/test_build.sh
sed -i '' \
  -e 's#^\# tests/test_entware_offline_build.sh — сборщик офлайн-установщика Entware#\# tests/test_build.sh — сборщик офлайн-установщика Entware#' \
  -e 's#^\# (scripts/entware_offline_build.sh) на поддельном зеркале#\# (build.sh) на поддельном зеркале#' \
  -e 's#\.github/workflows/entware-offline\.yml#.github/workflows/build.yml#' \
  -e 's#BUILD="\$ROOT/scripts/entware_offline_build.sh"#BUILD="$ROOT/build.sh"#' \
  -e 's#var/z2k-offline#var/entware-offline#g' \
  -e 's#/opt/var/z2k-offline#/opt/var/entware-offline#g' \
  tests/test_build.sh
grep -n 'z2k' tests/test_build.sh && echo "ОСТАЛОСЬ z2k — поправить руками" || echo "чисто"
```

Ожидание: `чисто`. Если grep что-то нашёл, убрать вручную: в тесте слово z2k допустимо только в пути `/Library/Zapret2/z2k` (его там нет).

- [ ] **Step 2: Запустить тест, убедиться, что он падает**

Run: `sh tests/test_build.sh | tail -3`
Expected: `sh: .../build.sh: No such file` в логах, `FAILED:` больше нуля (сборка rc ≠ 0).

- [ ] **Step 3: Взять сборщик из z2k и переписать**

```bash
cd /Library/Zapret2/entware-offline
git -C /Library/Zapret2/z2k show origin/z2k-staging:scripts/entware_offline_build.sh > build.sh
sed -i '' \
  -e 's#^\# scripts/entware_offline_build.sh — офлайн-установщик Entware для Keenetic.#\# build.sh — офлайн-установщик Entware для Keenetic.#' \
  -e 's#^\# curl не запустить установку z2k: busybox wget в Entware не умеет https), со#\# curl с роутера не скачать ничего по https: busybox wget в Entware его не умеет), со#' \
  -e 's#^\# Использование: sh scripts/entware_offline_build.sh #\# Использование: sh build.sh #' \
  -e 's#^OFF=/opt/var/z2k-offline$#OFF=/opt/var/entware-offline#' \
  -e 's#print "\# z2k офлайн: вернуть обычный сервер пакетов, убрать локальный фид и его списки"#print "\# Офлайн-установщик: вернуть обычный сервер пакетов, убрать локальный фид и его списки"#' \
  build.sh
chmod 755 build.sh
grep -n 'z2k' build.sh && echo "ОСТАЛОСЬ z2k" || echo "чисто"
```

Ожидание: `чисто`. Шапка файла после правки должна начинаться так:

```sh
#!/bin/sh
# build.sh — офлайн-установщик Entware для Keenetic.
#
# Зачем. Официальный установщик (bin.entware.net/<feed>/installer/*-installer.tar.gz)
```

и содержать `OFF=/opt/var/entware-offline`.

- [ ] **Step 4: Прогнать тест и shellcheck**

Run: `sh tests/test_build.sh | tail -3 && shellcheck -s sh build.sh tests/test_build.sh && echo SHELLCHECK OK`
Expected: `PASSED: 39` (как в z2k: 39 проверок), `FAILED: 0`, `SHELLCHECK OK`. Если PASSED иное, но FAILED 0 — нормально, число проверок не менялось, просто сверить с z2k: `sh /path/to/z2k-worktree/tests/test_entware_offline_build.sh | tail -2`.

- [ ] **Step 5: .gitignore и коммит**

```bash
cd /Library/Zapret2/entware-offline
printf 'out/\n' > .gitignore
git add build.sh tests/test_build.sh .gitignore
git commit -m "build: сборщик офлайн-установщика (перенесено из z2k@90eb5fdf)

Каталог фида в архиве — /opt/var/entware-offline, упоминаний z2k нет.
Тест на поддельном зеркале перенесён как есть.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: smoke.sh

**Files:**
- Create: `smoke.sh`

**Interfaces:**
- Produces: `sudo sh smoke.sh <...-installer.tar.gz>`; код 0 — установка без сети прошла, иначе 1 с построчным отчётом `ok/FAIL`.

- [ ] **Step 1: Взять из z2k и переписать путь фида**

```bash
cd /Library/Zapret2/entware-offline
git -C /Library/Zapret2/z2k show origin/z2k-staging:scripts/entware_offline_smoke.sh > smoke.sh
sed -i '' \
  -e 's#^\# scripts/entware_offline_smoke.sh — ставит собранный#\# smoke.sh — ставит собранный#' \
  -e 's#^\# Использование: sudo sh scripts/entware_offline_smoke.sh #\# Использование: sudo sh smoke.sh #' \
  -e 's#\$root/opt/var/z2k-offline#$root/opt/var/entware-offline#' \
  smoke.sh
chmod 755 smoke.sh
grep -n 'z2k' smoke.sh && echo "ОСТАЛОСЬ z2k" || echo "чисто"
```

Ожидание: `чисто`; строка проверки стала `check "локальный фид удалён" "no" "$([ -e "$root/opt/var/entware-offline" ] && echo yes || echo no)"`.

- [ ] **Step 2: Синтаксис и shellcheck**

Run: `sh -n smoke.sh && shellcheck -s sh smoke.sh && echo OK`
Expected: `OK`. Живая проверка (chroot + unshare) возможна только на Linux под root — она в CI, задача 5.

- [ ] **Step 3: Коммит**

```bash
git add smoke.sh
git commit -m "smoke: установка архива без сети в chroot (перенесено из z2k@90eb5fdf)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: publish.sh и tests/test_publish.sh

**Files:**
- Create: `publish.sh`
- Create: `tests/test_publish.sh`

**Interfaces:**
- Consumes: каталог вывода с `aarch64-installer.*`, `mipsel-installer.*`, `mips-installer.*` от `build.sh`.
- Produces: `sh publish.sh <каталог-вывода>`; нужны `gh` в PATH, `GITHUB_REPOSITORY=owner/repo`, `GH_TOKEN`. Пишет `<каталог>/ALL.manifest` и `<каталог>/notes.md`. Код 0 и строка `состав пакетов не изменился — выпуск не нужен`, если Latest-релиз содержит такой же `ALL.manifest`; иначе создаёт релиз с тегом даты и печатает `выпущен <тег>`.

- [ ] **Step 1: Написать тест с поддельным gh**

Файл `tests/test_publish.sh`:

```sh
#!/bin/sh
# tests/test_publish.sh — publish.sh на поддельном gh, без сети.
#
# Что пинится:
#   - нет ни одного релиза → релиз создаётся с тегом сегодняшней даты UTC;
#   - ALL.manifest совпал с Latest → выхода без релиза, код 0;
#   - состав изменился, тег даты занят → тег с суффиксом -2;
#   - в релиз уходят 10 файлов: 3 архива, 3 манифеста, 3 diff, ALL.manifest;
#   - в заметках есть SHA256 всех трёх архивов и версии busybox/opkg/dropbear/curl.
# POSIX sh.
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[PASS] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want=[$2] got=[$3])"; fi; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SB=$(mktemp -d) || exit 1
trap 'rm -rf "$SB"' EXIT
export GITHUB_REPOSITORY=necronicle/entware-offline GH_FAKE="$SB/gh" PATH="$SB/bin:$PATH"
TODAY=$(date -u +%Y-%m-%d)

# Поддельный gh: релизы — каталоги $GH_FAKE/releases/<тег>, Latest — файл $GH_FAKE/latest.
mkdir -p "$SB/bin" "$GH_FAKE/releases"
cat > "$SB/bin/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "$GH_FAKE/log"
[ "$1" = release ] || { echo "fake gh: $*" >&2; exit 2; }
case "$2" in
    view) [ -d "$GH_FAKE/releases/$3" ] ;;
    download)
        # gh release download -R repo -p ALL.manifest -D dir — без тега берёт Latest.
        [ -s "$GH_FAKE/latest" ] || exit 1
        tag=$(cat "$GH_FAKE/latest"); dir=""; pat=""
        while [ $# -gt 0 ]; do case "$1" in -D) dir=$2; shift ;; -p) pat=$2; shift ;; esac; shift; done
        [ -f "$GH_FAKE/releases/$tag/$pat" ] || exit 1
        cp "$GH_FAKE/releases/$tag/$pat" "$dir/" ;;
    create)
        tag=$3; shift 3; mkdir -p "$GH_FAKE/releases/$tag"
        while [ $# -gt 0 ]; do
            case "$1" in
                --notes-file) cp "$2" "$GH_FAKE/releases/$tag/.notes"; shift ;;
                --latest) echo "$tag" > "$GH_FAKE/latest" ;;
                -R|--target|--title) shift ;;
                -*) ;;
                *) cp "$1" "$GH_FAKE/releases/$tag/" ;;
            esac; shift
        done ;;
    *) echo "fake gh: $*" >&2; exit 2 ;;
esac
EOF
chmod 755 "$SB/bin/gh"

# Каталог сборки: манифесты с версиями и архивы-заглушки.
mk_out() { # $1 — версия busybox (меняет состав)
    rm -rf "$SB/out"; mkdir -p "$SB/out"
    for a in aarch64 mipsel mips; do
        printf 'source\thttps://bin.entware.net/x/installer/%s-installer.tar.gz\ninstaller_sha256\t0\nbusybox\t%s\tentware\t0\ncurl\t8.0\tentware\t0\ndropbear\t2024\tentware\t0\topkg\t1\tentware\t0\n' "$a" "$1" > "$SB/out/$a-installer.manifest"
        printf 'tgz %s %s\n' "$a" "$1" > "$SB/out/$a-installer.tar.gz"
        printf -- '--- a/bin/install\n+++ b/bin/install\n' > "$SB/out/$a-installer.install.diff"
    done
}
run() { sh "$ROOT/publish.sh" "$SB/out" > "$SB/pub.log" 2>&1; }

# --- 1. пустой репозиторий → первый релиз -------------------------------------
mk_out 1.37.0-6
run; rc=$?
eq "первый выпуск: rc 0" "0" "$rc"
eq "первый выпуск: тег — дата" "yes" "$([ -d "$GH_FAKE/releases/$TODAY" ] && echo yes || echo no)"
eq "первый выпуск: помечен Latest" "$TODAY" "$(cat "$GH_FAKE/latest" 2>/dev/null)"
eq "первый выпуск: 10 файлов" "10" "$(find "$GH_FAKE/releases/$TODAY" -type f ! -name '.notes' | wc -l | tr -d ' ')"
eq "первый выпуск: ALL.manifest в релизе" "yes" "$([ -f "$GH_FAKE/releases/$TODAY/ALL.manifest" ] && echo yes || echo no)"
eq "первый выпуск: сказано" "1" "$(grep -c "выпущен $TODAY" "$SB/pub.log")"
N="$GH_FAKE/releases/$TODAY/.notes"
eq "заметки: три суммы" "3" "$(grep -c -- '-installer.tar.gz$' "$N")"
eq "заметки: версия busybox" "1" "$(grep -c 'busybox 1.37.0-6' "$N")"
eq "заметки: ссылка latest/download" "1" "$(grep -c 'releases/latest/download/aarch64-installer.tar.gz' "$N")"

# --- 2. состав не изменился → релиза нет ---------------------------------------
mk_out 1.37.0-6
run; rc=$?
eq "без изменений: rc 0" "0" "$rc"
eq "без изменений: сказано" "1" "$(grep -c 'состав пакетов не изменился' "$SB/pub.log")"
eq "без изменений: новых релизов нет" "1" "$(ls "$GH_FAKE/releases" | wc -l | tr -d ' ')"

# --- 3. состав изменился, тег даты занят → суффикс -2 --------------------------
mk_out 1.37.0-7
run; rc=$?
eq "второй за день: rc 0" "0" "$rc"
eq "второй за день: тег -2" "yes" "$([ -d "$GH_FAKE/releases/$TODAY-2" ] && echo yes || echo no)"
eq "второй за день: Latest сдвинут" "$TODAY-2" "$(cat "$GH_FAKE/latest")"
eq "второй за день: старый релиз цел" "yes" "$([ -f "$GH_FAKE/releases/$TODAY/ALL.manifest" ] && echo yes || echo no)"

# --- 4. ещё раз изменился → -3 --------------------------------------------------
mk_out 1.37.0-8
run; rc=$?
eq "третий за день: тег -3" "yes" "$([ -d "$GH_FAKE/releases/$TODAY-3" ] && echo yes || echo no)"

printf '\nPASSED: %d\nFAILED: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Запустить, убедиться, что падает**

Run: `sh tests/test_publish.sh | tail -3`
Expected: `FAILED:` больше нуля (`publish.sh` нет).

- [ ] **Step 3: Написать publish.sh**

```sh
#!/bin/sh
# publish.sh — выпустить релиз с офлайн-установщиками, если состав пакетов изменился.
#
# Как решается, нужен ли выпуск: три манифеста склеиваются в ALL.manifest и
# сравниваются с ALL.manifest релиза, помеченного Latest. Совпали — выпуск не
# нужен. Иначе создаётся релиз с тегом сегодняшней даты UTC (занят — с
# суффиксом -2, -3, …), помечается Latest; старые релизы остаются: откат на
# прошлую сборку — просто скачать её.
#
# Использование: sh publish.sh <каталог с результатами build.sh для трёх архитектур>
# Нужны: gh в PATH, GH_TOKEN, GITHUB_REPOSITORY=owner/repo.
set -eu
out="${1:?каталог сборки}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY=owner/repo}"
today=$(date -u +%Y-%m-%d)

for a in aarch64 mipsel mips; do
    for s in tar.gz manifest install.diff; do
        [ -s "$out/$a-installer.$s" ] || { echo "нет $out/$a-installer.$s" >&2; exit 1; }
    done
done
cat "$out/aarch64-installer.manifest" "$out/mipsel-installer.manifest" "$out/mips-installer.manifest" > "$out/ALL.manifest"

prev=$(mktemp -d)
trap 'rm -rf "$prev"' EXIT
# gh release download без тега берёт Latest; в пустом репозитории падает — тогда выпускаем.
if gh release download -R "$repo" -p ALL.manifest -D "$prev" >/dev/null 2>&1 \
   && cmp -s "$prev/ALL.manifest" "$out/ALL.manifest"; then
    echo "состав пакетов не изменился — выпуск не нужен"
    exit 0
fi

tag=$today; n=1
while gh release view "$tag" -R "$repo" >/dev/null 2>&1; do
    n=$((n + 1)); tag="$today-$n"
done

ver() { awk -F'\t' -v p="$1" '$1 == p { print $2; exit }' "$out/aarch64-installer.manifest"; }
{
    echo "Офлайн-установщики Entware для Keenetic. Собраны $today из официального установщика и пакетов bin.entware.net, каждый пакет сверен по SHA256 из официального индекса и установлен без сети в проверочной среде."
    echo
    echo "Ставятся так же, как официальный установщик: архив своей архитектуры кладётся в папку install на USB-накопителе. Инструкция — в README."
    echo
    echo "| Архитектура | Файл |"
    echo "|---|---|"
    echo "| ARM64 (aarch64) | [aarch64-installer.tar.gz](https://github.com/$repo/releases/latest/download/aarch64-installer.tar.gz) |"
    echo "| MIPSel | [mipsel-installer.tar.gz](https://github.com/$repo/releases/latest/download/mipsel-installer.tar.gz) |"
    echo "| MIPS | [mips-installer.tar.gz](https://github.com/$repo/releases/latest/download/mips-installer.tar.gz) |"
    echo
    echo "Внутри: busybox $(ver busybox), opkg $(ver opkg), dropbear $(ver dropbear), curl $(ver curl). Полный состав — файлы *.manifest, правка официального скрипта установки — *.install.diff."
    echo
    echo "SHA256:"
    echo '```'
    (cd "$out" && { command -v sha256sum >/dev/null 2>&1 && sha256sum ./*-installer.tar.gz || shasum -a 256 ./*-installer.tar.gz; })
    echo '```'
} > "$out/notes.md"

gh release create "$tag" -R "$repo" --target main --latest \
    --title "Entware офлайн $tag" --notes-file "$out/notes.md" \
    "$out"/aarch64-installer.tar.gz "$out"/mipsel-installer.tar.gz "$out"/mips-installer.tar.gz \
    "$out"/aarch64-installer.manifest "$out"/mipsel-installer.manifest "$out"/mips-installer.manifest \
    "$out"/aarch64-installer.install.diff "$out"/mipsel-installer.install.diff "$out"/mips-installer.install.diff \
    "$out"/ALL.manifest
echo "выпущен $tag"
```

`chmod 755 publish.sh`.

- [ ] **Step 4: Прогнать тесты и shellcheck**

Run: `sh tests/test_publish.sh | tail -3 && shellcheck -s sh publish.sh tests/test_publish.sh && echo OK`
Expected: `PASSED: 17`, `FAILED: 0`, `OK`. Если shellcheck ругается на `ls | wc -l` в тесте (SC2012) — заменить на `find "$GH_FAKE/releases" -mindepth 1 -maxdepth 1 -type d | wc -l`.

- [ ] **Step 5: Коммит**

```bash
git add publish.sh tests/test_publish.sh
git commit -m "publish: датированные релизы, выпуск только при смене состава

Тег — дата UTC, при занятом теге суффикс -2, -3. Релиз помечается Latest,
ссылки в README идут через releases/latest/download. Тест на поддельном gh.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: workflow, README, LICENSE

**Files:**
- Create: `.github/workflows/build.yml`
- Create: `README.md`
- Create: `LICENSE`

**Interfaces:**
- Consumes: `build.sh`, `smoke.sh`, `publish.sh`, оба теста.

- [ ] **Step 1: Workflow**

Файл `.github/workflows/build.yml`:

```yaml
name: build
# Офлайн-установщики Entware для Keenetic (aarch64, mipsel, mips).
#
# На pull request и push в main: тесты, shellcheck, сборка трёх архитектур и
# установка каждой без сети в chroot через qemu. Публикации нет.
# По понедельникам и по ручному запуску на main: то же плюс выпуск релиза,
# если состав пакетов изменился (publish.sh).
on:
  pull_request:
  push:
    branches: [main]
  schedule:
    # Понедельник 03:23 UTC — минута не :00, чтобы не толкаться в толпе cron'ов.
    - cron: "23 3 * * 1"
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: false
jobs:
  build:
    name: tests, build, offline install, publish
    runs-on: ubuntu-latest
    timeout-minutes: 40
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: shellcheck
        run: shellcheck -s sh build.sh smoke.sh publish.sh tests/*.sh
      - name: tests
        run: |
          set -eu
          sh tests/test_build.sh
          sh tests/test_publish.sh
      - name: qemu for the offline install check
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y -qq qemu-user-static
      - name: build
        run: |
          set -eu
          mkdir -p out
          for a in aarch64 mipsel mips; do sh build.sh "$a" out; done
          ls -l out
      - name: offline install (no network)
        run: |
          set -eu
          for f in out/*-installer.tar.gz; do sudo sh smoke.sh "$f"; done
      - name: publish when the package set changed
        if: github.ref == 'refs/heads/main' && (github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')
        env:
          GH_TOKEN: ${{ github.token }}
        run: sh publish.sh out
```

Проверка: `python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/build.yml"))' && echo YAML OK` (если нет PyYAML — `ruby -ryaml -e 'YAML.load_file(".github/workflows/build.yml")' && echo YAML OK`).

- [ ] **Step 2: LICENSE**

```bash
git -C /Library/Zapret2/z2k show origin/z2k-staging:LICENSE > LICENSE
head -3 LICENSE
```

Ожидание: `MIT License`, `Copyright (c) 2026 Necronicle`.

- [ ] **Step 3: README**

Файл `README.md`:

````markdown
# Офлайн-установщики Entware для Keenetic

Официальный установщик Entware, в который заранее положены его базовые пакеты
и `curl`. Сеть при установке не нужна.

## Зачем

У части провайдеров сервер пакетов Entware (`bin.entware.net`) обрывает
загрузку на первых десятках килобайт. Официальный установщик во время
установки сам качает с него базовые пакеты, поэтому на таких линиях установка
Entware обрывается на шаге «[2/5] Загрузка и установка основных пакетов».

Здесь берётся официальный установщик и в него кладутся его же базовые пакеты
плюс `curl` и `ca-bundle`. Каждый пакет сверяется по SHA256 с официальным
индексом Entware. Архивы собираются автоматически раз в неделю, и каждый перед
публикацией устанавливается без сети в проверочной среде. Не встал — не
публикуется.

Используется проектами [z2k](https://github.com/necronicle/z2k),
[d2k](https://github.com/necronicle/d2k) и
[keenetic-doq](https://github.com/necronicle/keenetic-doq), подходит для любой
установки Entware на Keenetic.

## Скачать

Архив для архитектуры своей модели (какая у вас — скажет
[официальная инструкция Keenetic](https://help.keenetic.com/hc/ru/articles/360021214160),
выберите на сайте свою модель):

| Архитектура | Файл |
|---|---|
| ARM64 (aarch64) | [aarch64-installer.tar.gz](https://github.com/necronicle/entware-offline/releases/latest/download/aarch64-installer.tar.gz) |
| MIPSel | [mipsel-installer.tar.gz](https://github.com/necronicle/entware-offline/releases/latest/download/mipsel-installer.tar.gz) |
| MIPS | [mips-installer.tar.gz](https://github.com/necronicle/entware-offline/releases/latest/download/mips-installer.tar.gz) |

Ссылки всегда ведут на последнюю сборку. Прошлые сборки и контрольные суммы —
на [странице релизов](https://github.com/necronicle/entware-offline/releases).

## Установить

Так же, как официальный установщик:

1. Подготовьте USB-накопитель по официальной инструкции (раздел ext4, папка `install`).
2. Положите скачанный архив в папку `install` на накопителе. Имя файла менять не нужно.
3. В настройках роутера выберите накопитель в компоненте OPKG и дождитесь установки.

После установки `opkg` смотрит на обычный `bin.entware.net`, как после
официального установщика. Ключи SSH создаются на самом роутере во время
установки, в архиве их нет.

## Что внутри

Официальный установщик без изменений плюс локальный репозиторий пакетов в
`/opt/var/entware-offline`. В установщике меняются ровно две вещи, обе видны в
файле `*.install.diff` релиза:

- `etc/opkg.conf` — репозитории указывают на локальную папку; оригинал лежит рядом;
- `bin/install` — в список пакетов дописаны `curl` и `ca-bundle`, а перед последним
  шагом возвращается обычный `opkg.conf` и удаляется локальный репозиторий.

Полный список пакетов с версиями — в файле `*.manifest` релиза.

Чужие «офлайн-архивы» Entware, которые ходят по форумам, здесь не раздаются:
внутри них лежат готовые ключи хоста dropbear, одинаковые у всех, кто
поставил такой архив, и сторонние модули загрузчика.

## Проверить

Контрольные суммы архивов напечатаны в заметках релиза. Сверить:

```sh
sha256sum aarch64-installer.tar.gz
```

## Собрать самому

Нужны `curl`, `tar`, `gzip`, `awk`, `sha256sum` или `shasum`.

```sh
sh build.sh aarch64 out      # aarch64 | mipsel | mips
```

В `out/` появятся архив, манифест и diff правки установщика. Переменная
`ENTWARE_BASE` подменяет сервер пакетов (так работает тест на поддельном зеркале).

Проверить установку без сети (Linux, root; для чужой архитектуры нужен
`qemu-user-static` с binfmt):

```sh
sudo sh smoke.sh out/aarch64-installer.tar.gz
```

Тесты без сети: `sh tests/test_build.sh` и `sh tests/test_publish.sh`.

## Лицензия

MIT.
````

- [ ] **Step 4: Проверить ссылки README локально (только форма)**

Run: `grep -o 'https://[^) ]*' README.md | sort -u`
Expected: все ссылки на `github.com/necronicle/...` и `help.keenetic.com`; ссылки `latest/download` ровно три, по одной на архитектуру. Живая проверка (200) — в задаче 5 после первого релиза.

- [ ] **Step 5: Коммит**

```bash
git add .github/workflows/build.yml README.md LICENSE
git commit -m "ci+docs: workflow сборки и публикации, README, MIT

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Репозиторий на GitHub, первый зелёный CI, первый релиз

**Files:** нет новых; сетевые действия.

- [ ] **Step 1: Создать репозиторий и запушить**

```bash
cd /Library/Zapret2/entware-offline
gh repo create necronicle/entware-offline --public --source=. --remote=origin \
  --description "Офлайн-установщики Entware для Keenetic: официальный установщик с пакетами внутри, сеть при установке не нужна" \
  --push
gh repo edit necronicle/entware-offline --enable-wiki=false --enable-projects=false
```

Expected: репозиторий создан, `main` запушен, push запустил workflow `build`.

- [ ] **Step 2: Дождаться зелёного CI на push**

```bash
gh run list -R necronicle/entware-offline --workflow build --limit 1
gh run watch -R necronicle/entware-offline "$(gh run list -R necronicle/entware-offline --workflow build --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
```

Expected: `completed success`. Если упал — `gh run view <id> --log-failed`, починить, коммит, пуш, повторить. Типичные места: shellcheck (новые предупреждения на ubuntu-версии), smoke под qemu (обязательно смотреть `install.log` в выводе).

- [ ] **Step 3: Первый релиз ручным запуском**

```bash
gh workflow run build.yml -R necronicle/entware-offline --ref main
sleep 30
gh run watch -R necronicle/entware-offline "$(gh run list -R necronicle/entware-offline --workflow build --event workflow_dispatch --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
gh release list -R necronicle/entware-offline
```

Expected: один релиз с тегом сегодняшней даты, помечен Latest.

- [ ] **Step 4: Ссылки и суммы**

```bash
for a in aarch64 mipsel mips; do
  printf '%s ' "$a"; curl -sIL -o /dev/null -w '%{http_code}\n' "https://github.com/necronicle/entware-offline/releases/latest/download/$a-installer.tar.gz"
done
gh release view -R necronicle/entware-offline --json body -q .body | sed -n '/SHA256/,$p'
gh release view entware-offline -R necronicle/z2k --json body -q .body | sed -n '/SHA256/,$p'
```

Expected: три `200`. Суммы совпадают с релизом z2k, если состав не менялся с 11.10; если нет — сравнить `ALL.manifest` обоих релизов (`gh release download ... -p ALL.manifest`) и убедиться, что разница только в версиях пакетов.

---

### Task 6: z2k — убрать перенесённое, ссылка в README

**Files:**
- Worktree: `/Library/Zapret2/.worktrees/z2k-entware-move` от `origin/z2k-staging`, ветка `chore/entware-offline-moved`
- Delete: `scripts/entware_offline_build.sh`, `scripts/entware_offline_smoke.sh`, `tests/test_entware_offline_build.sh`, `.github/workflows/entware-offline.yml`
- Modify: `README.md` (раздел «#### Если Entware не устанавливается», строки 138–149 в origin/z2k-staging)

- [ ] **Step 1: Worktree**

```bash
cd /Library/Zapret2/z2k && git fetch -q origin
git worktree add -b chore/entware-offline-moved /Library/Zapret2/.worktrees/z2k-entware-move origin/z2k-staging
cd /Library/Zapret2/.worktrees/z2k-entware-move && git log --oneline -1
```

Expected: `90eb5fdf release: p-86.20 ...` (или новее, если staging сдвинулся — тогда проверить, что четыре файла и раздел README на месте: `git grep -n "Если Entware не устанавливается" -- README.md`).

- [ ] **Step 2: Удалить файлы и заменить раздел README**

```bash
cd /Library/Zapret2/.worktrees/z2k-entware-move
git rm -q scripts/entware_offline_build.sh scripts/entware_offline_smoke.sh tests/test_entware_offline_build.sh .github/workflows/entware-offline.yml
```

В `README.md` раздел от строки `#### Если Entware не устанавливается` до строки `Состав пакетов и контрольные суммы — на [странице релиза](https://github.com/necronicle/z2k/releases/tag/entware-offline).` включительно заменить на:

```markdown
#### Если Entware не устанавливается

Официальный установщик Entware во время установки сам качает пакеты с того же `bin.entware.net`, поэтому на таких линиях установка обрывается. Для этого случая есть офлайн-установщики: официальный установщик с пакетами внутри, сеть при установке не нужна. Архивы для всех архитектур, инструкция и контрольные суммы — в репозитории [entware-offline](https://github.com/necronicle/entware-offline).
```

Сделать это awk'ом, чтобы не промахнуться по строкам:

```bash
awk '
  /^#### Если Entware не устанавливается$/ { skip=1
    print; print ""
    print "Официальный установщик Entware во время установки сам качает пакеты с того же `bin.entware.net`, поэтому на таких линиях установка обрывается. Для этого случая есть офлайн-установщики: официальный установщик с пакетами внутри, сеть при установке не нужна. Архивы для всех архитектур, инструкция и контрольные суммы — в репозитории [entware-offline](https://github.com/necronicle/entware-offline)."
    next }
  skip && /^Состав пакетов и контрольные суммы/ { skip=0; next }
  skip { next }
  { print }' README.md > README.md.new && mv README.md.new README.md
git diff --stat
grep -n "entware-offline\|entware_offline" -r . --include='*.sh' --include='*.yml' --include='*.md' | grep -v '^./README.md' 
```

Expected: `git diff --stat` — 5 файлов (4 удалены, README изменён); последний grep пустой (упоминаний в коде не осталось). Если grep что-то нашёл (например, в `tests/run_all.sh` или `CONTRIBUTING.md`), убрать и это.

- [ ] **Step 3: Полный локальный CI**

Run: `cd /Library/Zapret2/.worktrees/z2k-entware-move && sh scripts/ci_local.sh 2>&1 | tail -15`
Expected: итог зелёный, в списке пропусков нет ничего нового. Падение из-за удалённого теста (если он где-то перечислен явно) — чинить в этом же коммите.

- [ ] **Step 4: Коммит и пуш в z2k-staging**

```bash
cd /Library/Zapret2/.worktrees/z2k-entware-move
git add -A
git commit -m "chore(entware): офлайн-установщики переехали в necronicle/entware-offline

Сборщик, проверка без сети, тест и workflow удалены — живут в отдельном
репозитории, релизы там. В README остался абзац со ссылкой. Шим z2k_opkg и
обход через зеркало узла не затронуты.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git fetch -q origin && git rebase origin/z2k-staging
git push origin HEAD:z2k-staging
gh run list -R necronicle/z2k --branch z2k-staging --limit 2
```

Expected: push прошёл fast-forward; CI z2k на staging запустился. Дождаться зелёного: `gh run watch -R necronicle/z2k <id> --exit-status`.

- [ ] **Step 5: Пометить старый релиз z2k как переехавший**

```bash
cd /Library/Zapret2/.worktrees/z2k-entware-move
gh release view entware-offline -R necronicle/z2k --json body -q .body > /tmp/old-notes.md
{ printf '**Переехало: свежие сборки — в репозитории [entware-offline](https://github.com/necronicle/entware-offline), ссылки ниже устареют.**\n\n'; cat /tmp/old-notes.md; } > /tmp/new-notes.md
gh release edit entware-offline -R necronicle/z2k --notes-file /tmp/new-notes.md
gh release view entware-offline -R necronicle/z2k --json body -q .body | head -2
```

Expected: первая строка заметок — «Переехало…». Файлы релиза не трогаются.

- [ ] **Step 6: Убрать worktree**

```bash
cd /Library/Zapret2/z2k && git worktree remove /Library/Zapret2/.worktrees/z2k-entware-move && git branch -D chore/entware-offline-moved
```

---

### Task 7: d2k и keenetic-doq — ссылка в README

**Files:**
- Клоны во временном каталоге сессии: `$SCRATCH/d2k`, `$SCRATCH/keenetic-doq` (`SCRATCH=/private/tmp/claude-501/-Library-Zapret2/21c999e8-6db7-4e46-927d-286128ce02e8/scratchpad`)
- Modify: `d2k/README.md` — после строки `Инструкция Entware написана для ARM64-модели. На сайте выберите свою модель.` (раздел «Что нужно → Keenetic»)
- Modify: `keenetic-doq/README.md` — после абзаца `На Keenetic busybox-wget собран без TLS … есть в busybox.` (раздел «Требования»)

- [ ] **Step 1: d2k**

```bash
SCRATCH=/private/tmp/claude-501/-Library-Zapret2/21c999e8-6db7-4e46-927d-286128ce02e8/scratchpad
cd "$SCRATCH" && gh repo clone necronicle/d2k d2k -- -q --depth 1 && cd d2k
awk '
  { print }
  /^Инструкция Entware написана для ARM64-модели\. На сайте выберите свою модель\.$/ {
    print ""
    print "Если Entware не устанавливается (сервер пакетов `bin.entware.net` обрывает"
    print "загрузку), возьмите офлайн-установщик из репозитория"
    print "[entware-offline](https://github.com/necronicle/entware-offline): официальный"
    print "установщик с пакетами внутри, сеть при установке не нужна."
  }' README.md > README.md.new && mv README.md.new README.md
git diff --stat
```

Expected: `README.md | 5 +` (ровно одно место, после строки про ARM64-модель). Если `git diff --stat` пуст — строка-якорь изменилась, найти раздел «### Keenetic» под «## Что нужно» и вставить абзац в его конец вручную.

```bash
git add README.md
git commit -q -m "docs: ссылка на офлайн-установщик Entware

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -q origin HEAD:main && git log --oneline -1
```

- [ ] **Step 2: keenetic-doq**

```bash
SCRATCH=/private/tmp/claude-501/-Library-Zapret2/21c999e8-6db7-4e46-927d-286128ce02e8/scratchpad
cd "$SCRATCH" && gh repo clone necronicle/keenetic-doq keenetic-doq -- -q --depth 1 && cd keenetic-doq
awk '
  { print }
  /^нужен `curl`\. Всё остальное для doqd и его скриптов есть в busybox\.$/ {
    print ""
    print "Если Entware не устанавливается (сервер пакетов `bin.entware.net` обрывает"
    print "загрузку), возьмите офлайн-установщик из репозитория"
    print "[entware-offline](https://github.com/necronicle/entware-offline): официальный"
    print "установщик с пакетами внутри и с `curl`, сеть при установке не нужна."
  }' README.md > README.md.new && mv README.md.new README.md
git diff --stat
```

Expected: `README.md | 5 +`. Если пусто — якорь изменился, вставить абзац в конец раздела «## Требования» перед «### Архитектуры» вручную.

```bash
git add README.md
git commit -q -m "docs: ссылка на офлайн-установщик Entware

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -q origin HEAD:main && git log --oneline -1
```

- [ ] **Step 3: Проверить, что ссылки читаются с GitHub**

```bash
for r in d2k keenetic-doq; do printf '%s: ' "$r"; gh api repos/necronicle/$r/readme -q .content | base64 -d | grep -c 'necronicle/entware-offline'; done
```

Expected: по `1` на каждый.

- [ ] **Step 4: Убрать клоны**

```bash
rm -rf "$SCRATCH/d2k" "$SCRATCH/keenetic-doq"
```

---

### Task 8: Память

**Files:**
- Modify: `/Users/mark/.claude/projects/-Library-Zapret2/memory/project_entware_via_vps_offline_2026_10_11.md` — в конец добавить абзац о переезде.
- Modify: `/Users/mark/.claude/projects/-Library-Zapret2/memory/MEMORY.md` — строку про Entware дополнить «переехало в necronicle/entware-offline 14.10; хвост: удалить релиз entware-offline в z2k после следующего релиза z2k».

- [ ] **Step 1: Дописать память**

В конец `project_entware_via_vps_offline_2026_10_11.md`:

```markdown
**Переезд 14.10.2026 (решение Марка):** сборщик, smoke, тест и workflow живут в
`necronicle/entware-offline` (локально /Library/Zapret2/entware-offline). Релизы там
датированные (тег YYYY-MM-DD, Latest), ссылки `releases/latest/download/<arch>-installer.tar.gz`.
Фид в архиве — `/opt/var/entware-offline`. В z2k удалено в z2k-staging коммитом
«chore(entware): офлайн-установщики переехали…», README ссылается на новый репо; d2k и
keenetic-doq получили абзац в README (main).
**ХВОСТ:** старый релиз `entware-offline` в z2k помечен «переехало», но не удалён: на него
ссылается README главной ветки z2k до следующего релиза z2k. После него —
`gh release delete entware-offline -R necronicle/z2k --cleanup-tag --yes`.
```

В `MEMORY.md` заменить строку `- [Entware через узел + офлайн-установщики (11.10)](project_entware_via_vps_offline_2026_10_11.md) — ...` на:

```markdown
- [Entware через узел + офлайн-установщики (11.10, переезд 14.10)](project_entware_via_vps_offline_2026_10_11.md) — установщики живут в necronicle/entware-offline (датированные релизы, latest/download); z2k-staging почищен; ХВОСТ: удалить релиз entware-offline в z2k после следующего релиза z2k
```

Записать через Write/Edit и проверить `grep -c 'entware-offline' MEMORY.md` = 1.
