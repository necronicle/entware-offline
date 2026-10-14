#!/bin/sh
# smoke.sh — ставит собранный офлайн-установщик Entware
# БЕЗ СЕТИ и проверяет результат. Для CI (Linux, root, qemu-user-static с binfmt).
#
# Как: архив распаковывается в /opt внутри chroot, установщик запускается так
# же, как его запускает Keenetic (/opt/bin/sh /opt/bin/install), в отдельном
# сетевом пространстве имён без интерфейсов: любая попытка сходить в сеть
# провалит установку. Подменяется только `mount` — установщик требует, чтобы
# /opt был ext*, а в chroot это не так.
#
# Использование: sudo sh smoke.sh <...-installer.tar.gz>
set -eu
tgz="${1:?архив установщика}"
root=$(mktemp -d)
# Уборка удаляет каталог, только если внутри не осталось ни одной точки
# монтирования: rm -rf по примонтированному каталогу ушёл бы в хостовую ФС.
cleanup() {
    umount "$root/proc" 2>/dev/null || true
    if grep -q " $root/" /proc/mounts 2>/dev/null; then
        echo "внутри $root остались точки монтирования — каталог не удаляю" >&2
        return 0
    fi
    rm -rf "$root"
}
trap cleanup EXIT
mkdir -p "$root/opt" "$root/tmp/shim" "$root/proc" "$root/dev" "$root/bin"
tar xzf "$tgz" -C "$root/opt"
mount -t proc proc "$root/proc"
# Хостовый /dev НЕ привязываем: только четыре устройства, нужные установщику
# (перенаправления в /dev/null, ключи SSH из /dev/urandom).
mknod -m 666 "$root/dev/null" c 1 3
mknod -m 666 "$root/dev/zero" c 1 5
mknod -m 666 "$root/dev/random" c 1 8
mknod -m 666 "$root/dev/urandom" c 1 9
cat > "$root/tmp/shim/mount" <<'EOF'
#!/opt/bin/sh
echo "/dev/sda1 on /opt type ext4 (rw,noatime)"
EOF
# logger: сообщения установщика — в вывод, а не в системный журнал.
cat > "$root/tmp/shim/logger" <<'EOF'
#!/opt/bin/sh
[ "$1" = "-t" ] && shift 2
echo "installer: $*"
EOF
chmod 755 "$root/tmp/shim/mount" "$root/tmp/shim/logger"
# /bin/sh на роутере даёт прошивка, скрипты пакетов начинаются с #!/bin/sh.
ln -s /opt/bin/sh "$root/bin/sh"

fail=0
check() { if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1 (ждали [$2], есть [$3])"; fail=1; fi; }

echo "== $(basename "$tgz"): установка без сети"
rc=0
unshare -n chroot "$root" /opt/bin/sh -c \
    'export PATH=/tmp/shim:/opt/bin:/opt/sbin; /opt/bin/sh /opt/bin/install' >"$root/tmp/install.log" 2>&1 || rc=$?
check "установщик завершился успешно" "0" "$rc"
cat "$root/tmp/install.log"

# Проверки — по файлам, без запуска opkg: он создал бы каталог списков заново.
st="$root/opt/lib/opkg/status"
for p in busybox opkg dropbear opt-ndmsv2 curl ca-bundle; do
    check "пакет $p установлен" "1" "$(grep -c "^Package: $p\$" "$st" 2>/dev/null || true)"
done
check "opkg.conf снова смотрит на bin.entware.net" "0" "$(grep -c 'file://' "$root/opt/etc/opkg.conf" 2>/dev/null || true)"
check "в opkg.conf есть bin.entware.net" "yes" "$(grep -q 'bin\.entware\.net' "$root/opt/etc/opkg.conf" && echo yes || echo no)"
check "локальный фид удалён" "no" "$([ -e "$root/opt/var/entware-offline" ] && echo yes || echo no)"
check "списков локального фида не осталось" "0" "$(find "$root/opt/var/opkg-lists" -type f 2>/dev/null | wc -l | tr -d ' ')"
check "копия opkg.conf убрана" "no" "$([ -e "$root/opt/etc/opkg.conf.online" ] && echo yes || echo no)"
check "ключ SSH ed25519 сгенерирован" "yes" "$([ -s "$root/opt/etc/dropbear/dropbear_ed25519_host_key" ] && echo yes || echo no)"
check "скрипт установки удалил себя" "no" "$([ -e "$root/opt/bin/install" ] && echo yes || echo no)"
check "curl запускается" "0" "$(chroot "$root" /opt/bin/curl --version >/dev/null 2>&1; echo $?)"
[ "$fail" = 0 ] || { echo "== $(basename "$tgz"): ПРОВАЛ"; exit 1; }
echo "== $(basename "$tgz"): офлайн-установка прошла"
