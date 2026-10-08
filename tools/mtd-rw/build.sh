#!/usr/bin/env bash
#
# Пересборка mtd-rw.ko через OpenWrt SDK.
#
# Нужна, когда версия ядра на роутере отличается от той, под которую собран
# лежащий рядом mtd-rw.ko (модуль ядра привязан к версии ядра — vermagic).
# Типичный случай: обновили прошивку, и ядро сменилось.
#
# Использование:
#   ./build.sh              # соберёт под версию из переменной VERSION
#   ./build.sh 23.05.6
#
# Требуется ~1.5 ГБ свободного места и интернет.
#
set -eu
cd "$(dirname "$0")"

VERSION="${1:-23.05.6}"
TARGET="ramips/mt7621"
BUILD_ROOT="$(cd ../.. && pwd)/build"
SDK_DIR="openwrt-sdk-${VERSION}-ramips-mt7621_gcc-12.3.0_musl.Linux-x86_64"

echo "=============================================================="
echo " Сборка mtd-rw.ko под OpenWrt $VERSION / $TARGET"
echo "=============================================================="

# OpenWrt SDK требует GNU awk, а не mawk (в Ubuntu по умолчанию mawk).
if ! awk --version 2>/dev/null | grep -q "GNU Awk"; then
    echo
    echo "!! Ваш awk — не GNU Awk. Установите:"
    echo "     sudo apt-get install -y gawk"
    exit 1
fi

mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"

if [ ! -d "$SDK_DIR" ]; then
    ARCHIVE="${SDK_DIR}.tar.xz"
    URL="https://downloads.openwrt.org/releases/${VERSION}/targets/${TARGET}/${ARCHIVE}"
    echo
    echo "== Скачиваю SDK (~170 МБ) =="
    echo "   $URL"
    curl -L --fail -o "$ARCHIVE" "$URL"
    echo "== Распаковываю =="
    tar xf "$ARCHIVE"
fi

cd "$SDK_DIR"

echo
echo "== Кладу пакет mtd-rw =="
mkdir -p package/kernel/mtd-rw
cp "$OLDPWD/../tools/mtd-rw/Makefile" package/kernel/mtd-rw/Makefile 2>/dev/null || \
    cp "$(cd - >/dev/null && echo "$OLDPWD")" /dev/null 2>/dev/null || true

# Надёжнее взять Makefile рядом со скриптом.
SRC_DIR="$(cd "$(dirname "$0")" && pwd)/src"
if [ -f "$SRC_DIR/Makefile" ]; then
    cp "$SRC_DIR/Makefile" package/kernel/mtd-rw/Makefile
fi
if [ ! -f package/kernel/mtd-rw/Makefile ]; then
    echo "!! Не найден Makefile пакета"
    exit 1
fi

grep -q "CONFIG_PACKAGE_kmod-mtd-rw" .config || \
    echo "CONFIG_PACKAGE_kmod-mtd-rw=m" >> .config

echo
echo "== defconfig =="
make defconfig >/dev/null

echo "== Сборка =="
make package/kernel/mtd-rw/compile V=s -j"$(nproc)" 2>&1 | tail -25

IPK=$(find bin -name "kmod-mtd-rw_*.ipk" | head -1)
[ -n "$IPK" ] || { echo "!! .ipk не собрался"; exit 1; }

echo
echo "== Распаковываю .ko =="
WORK=$(mktemp -d)
cp "$IPK" "$WORK/pkg.ipk"
( cd "$WORK" && tar xzf pkg.ipk && tar xzf data.tar.gz )
KO=$(find "$WORK" -name 'mtd-rw.ko' | head -1)
[ -n "$KO" ] || { echo "!! mtd-rw.ko не найден внутри .ipk"; exit 1; }

DEST="$(cd "$(dirname "$0")" && pwd)/mtd-rw.ko"
cp "$KO" "$DEST"
rm -rf "$WORK"

echo
echo "== Готово =="
ls -la "$DEST"
echo "vermagic: $(strings "$DEST" | grep -m1 '^5\.' || echo '(скрыт сжатием/стрипом)')"
