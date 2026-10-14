#!/bin/sh
# publish.sh — выпустить релиз с офлайн-установщиками, если состав пакетов изменился.
#
# Как решается, нужен ли выпуск: три манифеста плюс sha256 самого сборщика
# (строка recipe — иначе правка build.sh никогда не доехала бы до людей, пока
# Entware не сменит состав) склеиваются в ALL.manifest и сравниваются с
# ALL.manifest релиза, помеченного Latest. Совпали — выпуск не нужен. Иначе создаётся релиз с тегом сегодняшней даты UTC (занят — с
# суффиксом -2, -3, …), помечается Latest; старые релизы остаются: откат на
# прошлую сборку — просто скачать её.
#
# Использование: sh publish.sh <каталог с результатами build.sh для трёх архитектур>
# Нужны: gh в PATH, GH_TOKEN, GITHUB_REPOSITORY=owner/repo. BUILD_SH — путь к
# сборщику для строки recipe (по умолчанию build.sh рядом с этим скриптом).
set -eu
out="${1:?каталог сборки}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY=owner/repo}"
BUILD_SH="${BUILD_SH:-$(dirname "$0")/build.sh}"
today=$(date -u +%Y-%m-%d)
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

for a in aarch64 mipsel mips; do
    for s in tar.gz manifest install.diff; do
        [ -s "$out/$a-installer.$s" ] || { echo "нет $out/$a-installer.$s" >&2; exit 1; }
    done
done
[ -s "$BUILD_SH" ] || { echo "нет сборщика $BUILD_SH" >&2; exit 1; }
{
    cat "$out/aarch64-installer.manifest" "$out/mipsel-installer.manifest" "$out/mips-installer.manifest"
    printf 'recipe\t%s\n' "$(sha "$BUILD_SH")"
} > "$out/ALL.manifest"

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
    echo "| ARM64 (aarch64) | [aarch64-installer.tar.gz](https://github.com/$repo/releases/download/$tag/aarch64-installer.tar.gz) |"
    echo "| MIPSel | [mipsel-installer.tar.gz](https://github.com/$repo/releases/download/$tag/mipsel-installer.tar.gz) |"
    echo "| MIPS | [mips-installer.tar.gz](https://github.com/$repo/releases/download/$tag/mips-installer.tar.gz) |"
    echo
    echo "Внутри: busybox $(ver busybox), opkg $(ver opkg), dropbear $(ver dropbear), curl $(ver curl). Полный состав — файлы *.manifest, правка официального скрипта установки — *.install.diff."
    echo
    echo "SHA256:"
    echo '```'
    (cd "$out" && for f in ./*-installer.tar.gz; do printf '%s  %s\n' "$(sha "$f")" "$f"; done)
    echo '```'
} > "$out/notes.md"

gh release create "$tag" -R "$repo" --target main --latest \
    --title "Entware офлайн $tag" --notes-file "$out/notes.md" \
    "$out"/aarch64-installer.tar.gz "$out"/mipsel-installer.tar.gz "$out"/mips-installer.tar.gz \
    "$out"/aarch64-installer.manifest "$out"/mipsel-installer.manifest "$out"/mips-installer.manifest \
    "$out"/aarch64-installer.install.diff "$out"/mipsel-installer.install.diff "$out"/mips-installer.install.diff \
    "$out"/ALL.manifest
echo "выпущен $tag"
