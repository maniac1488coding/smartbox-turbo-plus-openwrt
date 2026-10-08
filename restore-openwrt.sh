#!/usr/bin/env bash
#
# Возврат Beeline SmartBox TURBO+ из стоковой прошивки обратно в OpenWrt.
#
# ВАЖНО: этот скрипт НИЧЕГО НЕ ПРОШИВАЕТ. OpenWrt лежит в нулевом слоте
# (mtd4 + UBI) и при откате на сток никуда не девается. Достаточно вернуть
# один байт в разделе "Boot Flag" (mtd3): '1' -> '0' (Sercomm1 -> Sercomm0)
# и перезагрузить роутер.
#
# ЗАЧЕМ: когда загрузчик Sercomm после трёх неудачных загрузок переключает
# Boot Flag на Sercomm1, роутер грузит стоковую Beeline. Перепрошивать образ
# и заново настраивать НЕ нужно — только вот этот байт.
#
# Использование:
#   1. Стоковый роутер подключить LAN-кабелем к ПК.
#   2. В веб-интерфейсе стока (http://192.168.1.1) включить SSH:
#      - v1.x: Дополнительные настройки -> Прочее -> Управление доступом ->
#              Users Root Select -> SSH Admin - Enable LAN -> Save/Apply
#      - v2.x: Настройка -> Удалённое управление -> ADD (SSH, порт 22) ->
#              Save/Apply
#   3. Запустить:  ./restore-openwrt.sh
#
set -u

ROUTER=192.168.1.1

# Серийный номер с наклейки — он же пароль SSH стоковой прошивки (SuperUser/SD...).
# Реальное значение держите в файле device.local (он в .gitignore).
cd "$(dirname "$0")" || exit 1
[ -f ./device.local ] && . ./device.local
SERIAL="${SERIAL:-SD00000000000}"
# Для OpenWrt (root без пароля) и для стока (пароль) нужны разные наборы опций.
SSH_PLAIN=(-o BatchMode=yes -o StrictHostKeyChecking=no
           -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)
SSH_PASS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=8 -o PubkeyAuthentication=no
          -o PreferredAuthentications=password)

echo "=============================================================="
echo " Возврат SmartBox TURBO+ из стока в OpenWrt (без перепрошивки)"
echo "=============================================================="
echo

echo "== 1. Кто отвечает на $ROUTER =="
if ssh "${SSH_PLAIN[@]}" root@"$ROUTER" \
       'grep -q OpenWrt /etc/openwrt_release' 2>/dev/null; then
    echo "   Это уже OpenWrt. Ничего делать не нужно."
    echo -n "   Boot Flag: "; ssh "${SSH_PLAIN[@]}" root@"$ROUTER" \
        'hexdump -Cn 8 /dev/mtd3'
    exit 0
fi

if curl -s -m 5 -o /dev/null "http://$ROUTER/"; then
    echo "   Веб-интерфейс отвечает — похоже на стоковую Beeline."
else
    echo "   !! $ROUTER не отвечает ни по SSH, ни по HTTP."
    echo "      Проверьте: кабель в LAN-порту, IP ПК в 192.168.1.0/24."
    exit 1
fi

echo
echo "== 2. Пробую зайти по SSH под учёткой стока =="
RUN=""
for user in SuperUser root admin; do
    for pass in "$SERIAL" "admin"; do
        if sshpass -p "$pass" ssh "${SSH_PASS[@]}" "$user@$ROUTER" true 2>/dev/null; then
            echo "   Подошло: $user / $pass"
            RUN="$user:$pass"
            break 2
        fi
    done
done

if [ -z "$RUN" ]; then
    echo "   !! Не удалось войти по SSH."
    echo
    echo "   Включите SSH в веб-интерфейсе стока (см. шаг 2 в комментарии"
    echo "   в начале файла), затем запустите скрипт снова."
    echo
    echo "   Либо сделайте это вручную в веб-интерфейсе/консоли стока:"
    echo "     v1.x:  printf 0 | dd bs=1 seek=7 count=1 of=/dev/mtdblock3"
    echo "     v2.x:  bootflag_utility -s 0"
    echo "   затем перезагрузить роутер."
    exit 1
fi

USER="${RUN%%:*}"; PASS="${RUN##*:}"

echo
echo "== 3. Что сейчас в Boot Flag =="
sshpass -p "$PASS" ssh "${SSH_PASS[@]}" "$USER@$ROUTER" \
    'hexdump -Cn 8 /dev/mtdblock3' 2>/dev/null

echo
echo "== 4. Переключаю Slot Flag на Sercomm0 (слот с OpenWrt) =="
# У стока это CLI-оболочка: сначала входим в shell, потом выполняем команды.
sshpass -p "$PASS" ssh "${SSH_PASS[@]}" -T "$USER@$ROUTER" >/dev/null 2>&1 <<'REMOTE'
sh
printf 0 | dd bs=1 seek=7 count=1 of=/dev/mtdblock3
hexdump -Cn 8 /dev/mtdblock3
REMOTE
echo "   Готово."
echo
echo "== 5. Перезагружаю роутер =="
echo "   Роутер вернётся в OpenWrt со всеми настройками."
echo "   (Если сток успел что-то записать в разделы конфигурации —"
echo "    настройки OpenWrt можно восстановить из бэкапа, см. README.)"
sshpass -p "$PASS" ssh "${SSH_PASS[@]}" -T "$USER@$ROUTER" >/dev/null 2>&1 <<'REMOTE'
sh
reboot
REMOTE
echo "   Команда отправлена."
