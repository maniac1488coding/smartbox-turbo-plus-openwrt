#!/usr/bin/env bash
#
# Синхронизация ВТОРОГО слота прошивки (Kernel 2 / mtd5) с текущим ядром OpenWrt.
#
# ЗАЧЕМ ЭТО НУЖНО
# Роутер имеет два слота загрузки. Мы положили OpenWrt в оба, чтобы загрузчик
# Sercomm не мог уйти на стоковую прошивку — теперь оба слота грузят OpenWrt.
# Но команда sysupgrade обновляет ТОЛЬКО нулевой слот (mtd4). После обновления
# прошивки второй слот остаётся со старым ядром. Пока версии совпадают — всё
# нормально; после обновления второй слот надо обновить этим скриптом.
#
# Если не обновить: роутер работает как обычно (грузится слот 0), но если
# загрузчик когда-нибудь переключится на слот 1 — загрузится старое ядро
# со свежей корневой ФС. Это НЕ кирпич и не сток, но Wi-Fi-модули могут
# не совпасть. Поэтому после каждого sysupgrade запускайте этот скрипт.
#
# ЗАПУСКАТЬ НА ЭТОМ ПК, роутер подключён кабелем к сетевому порту.
#
set -eu
cd "$(dirname "$0")"

ROUTER=192.168.1.1
R=./rsh.sh
TMPK=$(mktemp /tmp/mtd4-current.XXXXXX.bin)

echo "=============================================================="
echo " Синхронизация второго слота прошивки (mtd5) с текущим ядром"
echo "=============================================================="
echo

echo "== 1. Проверяю роутер =="
if ! $R 'grep -q OpenWrt /etc/openwrt_release' 2>/dev/null; then
    echo "   !! Не похоже, что роутер на OpenWrt и доступен по SSH."
    exit 1
fi
$R '. /etc/openwrt_release; echo "   $DISTRIB_DESCRIPTION"'

echo
echo "== 2. Сравниваю ядра в слотах =="
$R 'printf "   слот 0 (mtd4): "; dd if=/dev/mtd4 bs=1 skip=$((0x100+32)) count=28 2>/dev/null; echo'
$R 'printf "   слот 1 (mtd5): "; dd if=/dev/mtd5 bs=1 skip=$((0x100+32)) count=28 2>/dev/null; echo'

echo
echo "== 3. Считываю текущее ядро из mtd4 =="
$R 'cat /dev/mtd4' > "$TMPK"
echo "   получено $(stat -c%s "$TMPK") байт"

echo
echo "== 4. Собираю образ для второго слота =="
python3 make_slot1_image.py "$TMPK"

echo
echo "== 5. Загружаю модуль, снимающий защиту с mtd5 =="
KO=""
for c in mtd-rw.ko tools/mtd-rw/mtd-rw.ko; do
    [ -f "$c" ] && { KO="$c"; break; }
done
if [ -z "$KO" ]; then
    echo "   !! не найден mtd-rw.ko (ожидается tools/mtd-rw/mtd-rw.ko)."
    echo "      Если сменилась версия ядра — пересоберите: tools/mtd-rw/build.sh"
    exit 1
fi
$R 'cat > /tmp/mtd-rw.ko' < "$KO"
if $R 'lsmod | grep -q mtd_rw'; then
    echo "   модуль уже загружен"
else
    $R 'insmod /tmp/mtd-rw.ko i_want_a_brick=1'
    echo "   загружен"
fi
$R 'printf "   mtd5 flags = "; cat /sys/class/mtd/mtd5/flags'

echo
echo "== 6. Записываю во второй слот =="
$R 'cat > /tmp/slot1.bin' < slot1_openwrt_kernel.bin
LOCAL_MD5=$(md5sum slot1_openwrt_kernel.bin | cut -d' ' -f1)
REMOTE_MD5=$($R 'md5sum /tmp/slot1.bin' | cut -d' ' -f1)
[ "$LOCAL_MD5" = "$REMOTE_MD5" ] || { echo "   !! файл на роутере повреждён"; exit 1; }
$R 'mtd write /tmp/slot1.bin /dev/mtd5'

echo
echo "== 7. Проверка =="
GOT=$($R 'head -c 2857878 /dev/mtd5 | md5sum' | cut -d' ' -f1)
echo "   md5 записанного : $GOT"
echo "   md5 ожидался    : $LOCAL_MD5"
if [ "$GOT" = "$LOCAL_MD5" ]; then
    echo "   ✓ второй слот обновлён и совпадает"
else
    echo "   !! РАСХОЖДЕНИЕ — второй слот записан неверно"
    exit 1
fi

$R 'printf "   слот 1 (mtd5): "; dd if=/dev/mtd5 bs=1 skip=$((0x100+32)) count=28 2>/dev/null; echo'
rm -f "$TMPK"
echo
echo "Готово. Оба слота грузят одну и ту же версию OpenWrt."
