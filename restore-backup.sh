#!/usr/bin/env bash
#
# Аварийное восстановление разделов NAND SmartBox TURBO+ из бэкапа.
#
# Бэкап лежит в ./backup/mtdN.bin (снят 2025 года с рабочего роутера).
# ВНИМАНИЕ: восстановление раздела перезаписывает flash. Использовать только
# когда действительно нужно, и только нужный раздел.
#
# Использование:
#   ./restore-backup.sh list              # что есть в бэкапе
#   ./restore-backup.sh show 3            # текущее состояние раздела mtd3
#   ./restore-backup.sh restore 3         # dry-run (ничего не пишет)
#   ./restore-backup.sh restore 3 --yes   # реально записать
#
set -u

cd "$(dirname "$0")" || exit 1
BACKUP=backup
ROUTER=192.168.1.1

declare -A NAME=(
  [0]="u-boot" [1]="dynamic partition map" [2]="Factory" [3]="Boot Flag"
  [4]="kernel" [5]="Kernel 2" [6]="File System 1" [7]="File System 2"
  [8]="Configuration/log" [9]="application tmp buffer (Ftool)" [10]="ubi"
)

rsh() {
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 \
        root@"$ROUTER" "$@"
}

cmd="${1:-}"
n="${2:-}"

case "$cmd" in
  list)
    echo "Разделы в бэкапе:"
    for i in $(seq 0 10); do
        f="$BACKUP/mtd$i.bin"
        [ -f "$f" ] || continue
        printf "  mtd%-2s %-32s %12s байт\n" "$i" "${NAME[$i]}" "$(stat -c%s "$f")"
    done
    ;;
  show)
    [ -n "$n" ] || { echo "укажите номер раздела"; exit 1; }
    echo "== Локальный бэкап mtd$n (${NAME[$n]}) =="
    hexdump -Cn 32 "$BACKUP/mtd$n.bin"
    echo "== Сейчас на роутере mtd$n =="
    rsh "hexdump -Cn 32 /dev/mtd$n"
    ;;
  restore)
    [ -n "$n" ] || { echo "укажите номер раздела"; exit 1; }
    f="$BACKUP/mtd$n.bin"
    [ -f "$f" ] || { echo "нет файла $f"; exit 1; }
    pname="${NAME[$n]}"
    size=$(stat -c%s "$f")
    echo "Раздел : mtd$n  ($pname)"
    echo "Файл   : $f  ($size байт)"
    echo "Цель   : root@$ROUTER"
    if [ "${3:-}" != "--yes" ]; then
        echo
        echo ">>> DRY-RUN. Ничего не записано."
        echo ">>> Для реальной записи повторите с флагом --yes"
        exit 0
    fi
    echo
    echo ">>> Записываю. НЕ ОТКЛЮЧАЙТЕ ПИТАНИЕ."
    rsh "mtd -e '$pname' write - '$pname'" < "$f"
    rc=$?
    echo ">>> exit=$rc"
    echo ">>> Проверка (должно совпасть с бэкапом):"
    rsh "hexdump -Cn 32 /dev/mtd$n"
    echo ">>> Локально:"
    hexdump -Cn 32 "$f"
    ;;
  *)
    sed -n '2,14p' "$0"
    ;;
esac
