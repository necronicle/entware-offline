#!/bin/sh
# tests/test_build.sh — сборщик офлайн-установщика Entware
# (build.sh) на поддельном зеркале file://, без сети.
#
# Что пинится:
#   - пакеты берутся из списка самого официального скрипта плюс curl и ca-bundle,
#     с замыканием по зависимостям: версии в скобках отбрасываются, из «a | b»
#     берётся первая, виртуальные имена разворачиваются через Provides;
#   - пакет, который есть и в keenetic-фиде, берётся оттуда (как arch ..._kn 200);
#   - лишнее в архив не попадает;
#   - SHA256 каждого пакета сверяется: подмена — отказ сборки;
#   - пропавшая зависимость и незнакомый скрипт установки — отказ, а не тихий архив;
#   - opkg.conf указывает на локальный фид, оригинал лежит рядом, скрипт установки
#     возвращает его перед последним шагом и убирает фид.
# Живая проверка — установка архива без сети — в .github/workflows/build.yml.
# POSIX sh.
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[PASS] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want=[$2] got=[$3])"; fi; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build.sh"
command -v curl >/dev/null 2>&1 || { echo "нет curl — пропуск"; printf '\nPASSED: 0\nFAILED: 0\n'; exit 0; }
SB=$(mktemp -d) || exit 1
trap 'rm -rf "$SB"' EXIT
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

M="$SB/mirror/aarch64-k3.10"
# Установщик-заглушка: та же форма, что у официального bin/install.
mk_installer() { # $1 — строка списка пакетов ("" — без строки «for ipk in»)
    rm -rf "$SB/inst"; mkdir -p "$SB/inst/bin" "$SB/inst/etc" "$M/installer"
    {
        echo "logger -t installer '[2/5] Загрузка и установка основных пакетов...'"
        [ -n "$1" ] && echo "for ipk in $1"
        echo " do"
        echo "  opkg install \$ipk"
        echo "done"
        echo "logger -t installer '[5/5] Установка завершена!'"
        echo "rm \"\$0\""
    } > "$SB/inst/bin/install"
    printf 'src/gz entware http://bin.entware.net/aarch64-k3.10\nsrc/gz keendev http://bin.entware.net/aarch64-k3.10/keenetic\ndest root /\n' > "$SB/inst/etc/opkg.conf"
    (cd "$SB/inst" && tar czf "$M/installer/aarch64-installer.tar.gz" .)
}
mk() { # фид имя версия зависимости provides
    d="$M"; [ "$1" = keendev ] && d="$M/keenetic"
    mkdir -p "$d"
    f="$2_$3_aarch64-3.10.ipk"
    printf 'ipk %s %s %s\n' "$1" "$2" "$3" > "$d/$f"
    {
        echo "Package: $2"; echo "Version: $3"
        [ -n "$4" ] && echo "Depends: $4"
        [ -n "$5" ] && echo "Provides: $5"
        echo "Filename: $f"; echo "SHA256sum: $(sha "$d/$f")"; echo
    } >> "$d/Packages"
}
mk_feed() {
    rm -rf "$M"; mkdir -p "$M/keenetic"
    mk entware alpha 1.0 "gamma (>= 2), libc" ""
    mk entware beta 1.0 "libvirt" ""
    mk entware gamma 2.0 "" ""
    mk entware libc 2.27 "" ""
    mk entware delta 1.0 "" "libvirt"
    mk entware curl 8.0 "libcurl" ""
    mk entware libcurl 8.0 "zlib | zlib-ng" ""
    mk entware zlib 1.3 "" ""
    mk entware zlib-ng 2.0 "" ""
    mk entware ca-bundle 1 "" ""
    mk entware unused 1 "" ""
    mk entware kpkg 1.0 "" ""
    mk keendev kpkg 1.0-kn "" ""
}
seal() { gzip -9nf "$M/Packages" "$M/keenetic/Packages"; }
build() { rm -rf "$SB/out"; ENTWARE_BASE="file://$SB/mirror" sh "$BUILD" aarch64 "$SB/out" >"$SB/build.log" 2>&1; }

# --- 1. обычная сборка --------------------------------------------------------
mk_feed; mk_installer "alpha beta kpkg"; seal
build; rc=$?
eq "сборка: rc 0" "0" "$rc"
[ "$rc" = 0 ] || cat "$SB/build.log"
T="$SB/out/aarch64-installer.tar.gz"
tar tzf "$T" 2>/dev/null | sed 's#^\./##' > "$SB/list"
has() { grep -qx "var/entware-offline/$1" "$SB/list" && echo yes || echo no; }
for p in alpha_1.0 beta_1.0 gamma_2.0 libc_2.27 delta_1.0 curl_8.0 libcurl_8.0 zlib_1.3 ca-bundle_1; do
    eq "в архиве $p" "yes" "$(has "entware/${p}_aarch64-3.10.ipk")"
done
eq "версия в скобках не мешает: gamma взят" "yes" "$(has entware/gamma_2.0_aarch64-3.10.ipk)"
eq "виртуальное имя через Provides: delta взят" "yes" "$(has entware/delta_1.0_aarch64-3.10.ipk)"
eq "из «zlib | zlib-ng» взят только первый" "no" "$(has entware/zlib-ng_2.0_aarch64-3.10.ipk)"
eq "ненужный пакет не попал" "no" "$(has entware/unused_1_aarch64-3.10.ipk)"
eq "kpkg взят из keenetic-фида" "yes" "$(has keendev/kpkg_1.0-kn_aarch64-3.10.ipk)"
eq "kpkg из основного фида не взят" "no" "$(has entware/kpkg_1.0_aarch64-3.10.ipk)"

mkdir -p "$SB/x"; tar xzf "$T" -C "$SB/x"
eq "манифест: 10 пакетов" "10" "$(grep -cvE '^(source|installer_sha256)' "$SB/x/var/entware-offline/MANIFEST")"
eq "локальный индекс: только взятые пакеты" "0" "$(gzip -dc "$SB/x/var/entware-offline/entware/Packages.gz" | grep -c '^Package: unused')"
eq "opkg.conf: основной фид — локальный" "1" "$(grep -c '^src/gz entware file:///opt/var/entware-offline/entware$' "$SB/x/etc/opkg.conf")"
eq "opkg.conf: keenetic-фид — локальный" "1" "$(grep -c '^src/gz keendev file:///opt/var/entware-offline/keendev$' "$SB/x/etc/opkg.conf")"
eq "оригинальный opkg.conf лежит рядом без изменений" "yes" "$(cmp -s "$SB/x/etc/opkg.conf.online" "$SB/inst/etc/opkg.conf" && echo yes || echo no)"
eq "в список пакетов дописаны curl и ca-bundle" "1" "$(grep -c '^for ipk in alpha beta kpkg curl ca-bundle$' "$SB/x/bin/install")"
_restore=$(grep -n 'mv -f /opt/etc/opkg.conf.online /opt/etc/opkg.conf' "$SB/x/bin/install" | cut -d: -f1)
_last=$(grep -n '\[5/5\]' "$SB/x/bin/install" | cut -d: -f1)
eq "opkg.conf возвращается перед последним шагом" "yes" "$([ -n "$_restore" ] && [ -n "$_last" ] && [ "$_restore" -lt "$_last" ] && echo yes || echo no)"
eq "локальный фид и его списки убираются" "1" "$(grep -c '^rm -rf /opt/var/entware-offline /opt/var/opkg-lists$' "$SB/x/bin/install")"
eq "ключей SSH в архиве нет" "0" "$(grep -c 'dropbear_.*_host_key' "$SB/list")"

# --- 1б. относительный каталог вывода (так его передаёт workflow) -------------
rm -rf "$SB/rel"; mkdir -p "$SB/rel"
(cd "$SB/rel" && ENTWARE_BASE="file://$SB/mirror" sh "$BUILD" aarch64 out >"$SB/build.log" 2>&1); rc=$?
eq "относительный вывод: rc 0" "0" "$rc"
eq "относительный вывод: архив на месте" "yes" "$([ -s "$SB/rel/out/aarch64-installer.tar.gz" ] && echo yes || echo no)"

# --- 2. подменённый пакет — отказ ----------------------------------------------
mk_feed; mk_installer "alpha beta kpkg"; printf 'подмена\n' > "$M/gamma_2.0_aarch64-3.10.ipk"; seal
build; rc=$?
eq "подмена пакета: сборка падает" "1" "$([ "$rc" != 0 ] && echo 1 || echo 0)"
eq "подмена пакета: названа причина" "1" "$(grep -c 'SHA256 не сошлась: gamma' "$SB/build.log")"
eq "подмена пакета: архива нет" "no" "$([ -e "$SB/out/aarch64-installer.tar.gz" ] && echo yes || echo no)"

# --- 3. пропавшая зависимость — отказ ------------------------------------------
mk_feed; mk entware broken 1 "nosuch" ""; mk_installer "alpha broken"; seal
build; rc=$?
eq "нет зависимости: сборка падает" "1" "$([ "$rc" != 0 ] && echo 1 || echo 0)"
eq "нет зависимости: названа" "1" "$(grep -c 'nosuch' "$SB/build.log")"

# --- 4. незнакомый скрипт установки — отказ ------------------------------------
mk_feed; mk_installer ""; seal
build; rc=$?
eq "нет строки «for ipk in»: сборка падает" "1" "$([ "$rc" != 0 ] && echo 1 || echo 0)"

printf '\nPASSED: %d\nFAILED: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
