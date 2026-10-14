#!/bin/sh
# build.sh — офлайн-установщик Entware для Keenetic.
#
# Зачем. Официальный установщик (bin.entware.net/<feed>/installer/*-installer.tar.gz)
# после распаковки сам делает `opkg update` и качает базовые пакеты с
# bin.entware.net. У части провайдеров этот сервер обрывает загрузку по объёму —
# установка Entware умирает на шаге [2/5] (замер 11.10.2026: список пакетов
# обрывается на 31 КБ из 378 КБ).
#
# Что делает. Берёт ОФИЦИАЛЬНЫЙ установщик без изменений и кладёт в него
# локальный фид: базовые пакеты из его же списка плюс curl и ca-bundle (без
# curl с роутера не скачать ничего по https: busybox wget в Entware его не умеет), со
# всеми зависимостями. Каждый пакет сверяется с SHA256 из официального индекса.
# В установщике меняются ровно две вещи, обе видны в diff'е:
#   etc/opkg.conf  — фиды указывают на локальную папку (file://);
#   bin/install    — в список пакетов дописаны curl и ca-bundle, а перед
#                    последним шагом возвращается обычный opkg.conf и
#                    удаляются локальный фид и его списки.
# Ключи SSH установщик генерирует сам, на роутере; в архиве их нет.
#
# Использование: sh build.sh <aarch64|mipsel|mips> <каталог-вывода>
# Прокси (если bin.entware.net недоступен): переменная https_proxy для curl.
set -eu

arch="${1:?архитектура: aarch64 | mipsel | mips}"
out="${2:?каталог вывода}"
case "$arch" in
    aarch64) feed=aarch64-k3.10;  inst=aarch64-installer.tar.gz ;;
    mipsel)  feed=mipselsf-k3.4;  inst=mipsel-installer.tar.gz ;;
    mips)    feed=mipssf-k3.4;    inst=mips-installer.tar.gz ;;
    *) echo "неизвестная архитектура: $arch" >&2; exit 2 ;;
esac
BASE="${ENTWARE_BASE:-https://bin.entware.net}/$feed"
EXTRA="curl ca-bundle"
OFF=/opt/var/entware-offline

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out" "$work/root"
# Путь вывода — абсолютный: архив пакуется из каталога сборки (cd ниже).
out=$(cd "$out" && pwd)
get() { curl -fsSL --retry 3 --connect-timeout 20 -o "$1" "$2"; }

echo "== $arch: официальный установщик и индексы"
get "$work/installer.tar.gz" "$BASE/installer/$inst"
get "$work/entware.gz" "$BASE/Packages.gz"
get "$work/keendev.gz" "$BASE/keenetic/Packages.gz"
gzip -dc "$work/entware.gz" > "$work/entware.idx"
gzip -dc "$work/keendev.gz" > "$work/keendev.idx"
tar xzf "$work/installer.tar.gz" -C "$work/root"
cp "$work/root/bin/install" "$work/install.orig"
cp "$work/root/etc/opkg.conf" "$work/opkg.conf.orig"

# Базовый список берём из самого официального скрипта: строка «for ipk in ...».
# Так список не расходится с Entware, когда они его меняют.
base=$(sed -n 's/^for ipk in \(.*\)$/\1/p' "$work/root/bin/install" | head -1)
[ -n "$base" ] || { echo "в bin/install не нашлась строка «for ipk in»" >&2; exit 1; }

# Индекс: одна запись на пакет, «фид<TAB>имя<TAB>версия<TAB>файл<TAB>sha256<TAB>зависимости<TAB>provides».
# keendev (_kn) приоритетнее основного фида, как в opkg.conf (arch ..._kn 200).
idx() {
    awk -v feed="$1" '
        function flush() { if (p != "") printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", feed, p, v, f, h, d, pr; p=v=f=h=d=pr="" }
        /^Package: / { flush(); p=$2 }
        /^Version: / { v=$2 }
        /^Filename: / { f=$2 }
        /^SHA256sum: / { h=$2 }
        /^Depends: / { sub(/^Depends: /, ""); d=$0 }
        /^Provides: / { sub(/^Provides: /, ""); pr=$0 }
        END { flush() }' "$2"
}
{ idx keendev "$work/keendev.idx"; idx entware "$work/entware.idx"; } > "$work/all.tsv"

# Замыкание по зависимостям. Версии в скобках и альтернативы «a | b» (берём
# первую) отбрасываем; виртуальные имена разворачиваем через Provides.
awk -F'\t' -v want="$base $EXTRA" '
    { if (!($2 in rec)) rec[$2] = $0
      n = split($7, pv, /, */); for (i = 1; i <= n; i++) { x = pv[i]; sub(/ .*/, "", x); if (x != "" && !(x in prov)) prov[x] = $2 } }
    END {
        n = split(want, q, " "); head = 1; tail = n
        for (i = 1; i <= n; i++) seen[q[i]] = 1
        while (head <= tail) {
            name = q[head++]
            if (!(name in rec)) { if (name in prov) name = prov[name]; else { print "MISSING\t" name; continue } }
            if (name in done) continue
            done[name] = 1; print rec[name]
            split(rec[name], r, "\t"); m = split(r[6], dep, /, */)
            for (j = 1; j <= m; j++) {
                x = dep[j]; sub(/ *\|.*/, "", x); sub(/ *\(.*/, "", x); sub(/^ +/, "", x)
                if (x != "" && !(x in seen)) { seen[x] = 1; q[++tail] = x }
            }
        }
    }' "$work/all.tsv" > "$work/set.tsv"
if grep -q '^MISSING' "$work/set.tsv"; then
    echo "не найдены в индексах:" >&2; grep '^MISSING' "$work/set.tsv" >&2; exit 1
fi

echo "== $arch: $(wc -l < "$work/set.tsv" | tr -d ' ') пакетов, качаю и сверяю SHA256"
mkdir -p "$work/root${OFF#/opt}/entware" "$work/root${OFF#/opt}/keendev"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
while IFS="$(printf '\t')" read -r fd name ver file hash _deps _prov; do
    case "$fd" in keendev) url="$BASE/keenetic/$file" ;; *) url="$BASE/$file" ;; esac
    dst="$work/root${OFF#/opt}/$fd/$file"
    get "$dst" "$url"
    got=$(sha "$dst")
    [ "$got" = "$hash" ] || { echo "SHA256 не сошлась: $name $ver ($got, ждали $hash)" >&2; exit 1; }
    printf '%s\t%s\t%s\t%s\n' "$name" "$ver" "$fd" "$hash" >> "$work/manifest.tsv"
done < "$work/set.tsv"

# Урезанные индексы: только взятые пакеты, записи — дословно из официальных.
for fd in entware keendev; do
    names=$(awk -F'\t' -v f="$fd" '$1 == f { printf "%s ", $2 }' "$work/set.tsv")
    awk -v keep="$names" '
        BEGIN { n = split(keep, k, " "); for (i = 1; i <= n; i++) want[k[i]] = 1 }
        /^Package: / { on = ($2 in want) }
        on { print }' "$work/$fd.idx" > "$work/root${OFF#/opt}/$fd/Packages"
    gzip -9n < "$work/root${OFF#/opt}/$fd/Packages" > "$work/root${OFF#/opt}/$fd/Packages.gz"
done

# opkg.conf: фиды — локальные; оригинал рядом, его вернёт bin/install.
cp "$work/opkg.conf.orig" "$work/root/etc/opkg.conf.online"
sed -e "s#^src/gz entware .*#src/gz entware file://$OFF/entware#" \
    -e "s#^src/gz keendev .*#src/gz keendev file://$OFF/keendev#" \
    "$work/opkg.conf.orig" > "$work/root/etc/opkg.conf"

# bin/install: дописать curl и ca-bundle в список и вернуть сеть перед [5/5].
awk -v extra="$EXTRA" -v off="$OFF" '
    /^for ipk in / && !did_list { sub(/[ \t]*$/, ""); $0 = $0 " " extra; did_list = 1 }
    /\[5\/5\]/ && !did_restore {
        print "# Офлайн-установщик: вернуть обычный сервер пакетов, убрать локальный фид и его списки"
        print "mv -f /opt/etc/opkg.conf.online /opt/etc/opkg.conf"
        print "rm -rf " off " /opt/var/opkg-lists"
        did_restore = 1
    }
    { print }
    END { if (!did_list || !did_restore) exit 3 }' "$work/install.orig" > "$work/root/bin/install" \
    || { echo "bin/install не похож на официальный: правка не встала" >&2; exit 1; }
chmod 755 "$work/root/bin/install"

# Манифест: что внутри и откуда. Он же решает, нужен ли новый выпуск.
{
    printf 'source\t%s/installer/%s\n' "$BASE" "$inst"
    printf 'installer_sha256\t%s\n' "$(sha "$work/installer.tar.gz")"
    sort "$work/manifest.tsv"
} > "$work/root${OFF#/opt}/MANIFEST"
cp "$work/root${OFF#/opt}/MANIFEST" "$out/${inst%.tar.gz}.manifest"
diff -u "$work/install.orig" "$work/root/bin/install" > "$out/${inst%.tar.gz}.install.diff" || true

# Архив: те же пути, что у официального (распаковывается в /opt).
(cd "$work/root" && { tar --owner=0 --group=0 --sort=name -czf "$out/$inst" . 2>/dev/null \
    || tar -czf "$out/$inst" .; })
echo "== $arch: готово $out/$inst ($(wc -c < "$out/$inst" | tr -d ' ') байт)"
