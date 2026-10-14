#!/bin/sh
# tests/test_publish.sh — publish.sh на поддельном gh, без сети.
#
# Что пинится:
#   - нет ни одного релиза → релиз создаётся с тегом сегодняшней даты UTC;
#   - ALL.manifest совпал с Latest → выход без релиза, код 0;
#   - состав изменился, тег даты занят → тег с суффиксом -2, потом -3;
#   - в релиз уходят 10 файлов: 3 архива, 3 манифеста, 3 diff, ALL.manifest;
#   - в заметках есть SHA256 всех трёх архивов, версия busybox и ссылки на файлы ЭТОГО релиза;
#   - в ALL.manifest входит sha256 сборщика (BUILD_SH): правка build.sh = новый релиз.
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
# Сборщик для строки recipe в ALL.manifest — копия, которую тест меняет в п. 5.
cp "$ROOT/build.sh" "$SB/build.sh"; export BUILD_SH="$SB/build.sh"

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
nrel() { find "$GH_FAKE/releases" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '; }

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
eq "заметки: ссылки — на файлы этого релиза, не latest" "3" "$(grep -c "releases/download/$TODAY/" "$N")"
eq "заметки: ссылок на latest нет" "0" "$(grep -c 'releases/latest' "$N")"

# --- 2. состав не изменился → релиза нет ---------------------------------------
mk_out 1.37.0-6
run; rc=$?
eq "без изменений: rc 0" "0" "$rc"
eq "без изменений: сказано" "1" "$(grep -c 'состав пакетов не изменился' "$SB/pub.log")"
eq "без изменений: новых релизов нет" "1" "$(nrel)"

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

# --- 5. состав тот же, изменился сборщик → новый релиз ---------------------------
eq "ALL.manifest: есть строка recipe" "1" "$(grep -c '^recipe	' "$GH_FAKE/releases/$TODAY-3/ALL.manifest")"
printf '# правка сборщика\n' >> "$BUILD_SH"
run; rc=$?
eq "смена сборщика: rc 0" "0" "$rc"
eq "смена сборщика: тег -4" "yes" "$([ -d "$GH_FAKE/releases/$TODAY-4" ] && echo yes || echo no)"
eq "смена сборщика: recipe в манифесте другой" "yes" "$(cmp -s "$GH_FAKE/releases/$TODAY-3/ALL.manifest" "$GH_FAKE/releases/$TODAY-4/ALL.manifest" && echo no || echo yes)"

printf '\nPASSED: %d\nFAILED: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
