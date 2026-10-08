#!/usr/bin/env bash
# Обнаружение роутера Beeline SmartBox TURBO+ на проводном порту.
# Использование: ./discover.sh [интерфейс]   (по умолчанию enp5s0)
set -u

IF="${1:-enp5s0}"
HOST_IP="192.168.1.2/24"
ROUTER_IP="192.168.1.1"

# LAN MAC роутера. Реальное значение удобно держать в файле device.local
# (он в .gitignore и в репозиторий не попадает). Здесь — только заглушка.
cd "$(dirname "$0")" || exit 1
[ -f ./device.local ] && . ./device.local
ROUTER_MAC="${ROUTER_MAC:-AA:BB:CC:DD:EE:FF}"

echo "=============================================="
echo " Интерфейс : $IF"
echo " Роутер    : $ROUTER_IP  (MAC $ROUTER_MAC)"
echo "=============================================="

echo
echo "== 1. Состояние линка =="
carrier="$(cat /sys/class/net/$IF/carrier 2>/dev/null || echo 0)"
if [ "$carrier" != "1" ]; then
    echo "!! Нет линка на $IF (carrier=$carrier)."
    echo "   Проверьте: кабель в LAN-порту роутера (жёлтый), роутер включён,"
    echo "   кабель исправен. Порт: $IF"
    exit 1
fi
echo "Линк есть."
sudo -n ethtool "$IF" 2>/dev/null | grep -iE "speed|duplex|link detected" | sed 's/^/   /'

echo
echo "== 2. Поднимаю $IF на $HOST_IP (без шлюза по умолчанию) =="
sudo -n ip link set "$IF" up
sudo -n ip addr flush dev "$IF" scope global 2>/dev/null || true
sudo -n ip addr add "$HOST_IP" dev "$IF"
sleep 1
ip -brief addr show "$IF" | sed 's/^/   /'

echo
echo "== 3. ARP-скан подсети 192.168.1.0/24 =="
sudo -n arp-scan -I "$IF" --retry=3 --timeout=500 192.168.1.0/24 2>/dev/null \
    | grep -vE "^Starting|^Interface|^Ending|^$" | sed 's/^/   /' || true

echo
echo "== 4. Проверка доступности $ROUTER_IP =="
if ping -c 2 -W 2 -I "$IF" "$ROUTER_IP" >/dev/null 2>&1; then
    echo "   ICMP: отвечает"
else
    echo "   ICMP: молчит (может быть закрыт — это нормально для OpenWrt/стока)"
fi

echo
echo "== 5. Сканирование портов =="
sudo -n nmap -e "$IF" -Pn -n --open \
     -p 22,23,53,80,443,7681,8080,8443,9000,5000 \
     "$ROUTER_IP" 2>/dev/null | grep -vE "^Starting|^Nmap done|^$" | sed 's/^/   /'

echo
echo "== 6. Определение прошивки =="
hdr_http="$(curl -s -m 4 -o /dev/null -D - "http://$ROUTER_IP/" 2>/dev/null | tr -d '\r' | grep -i '^server:' || true)"
hdr_https="$(curl -sk -m 4 -o /dev/null -D - "https://$ROUTER_IP/" 2>/dev/null | tr -d '\r' | grep -i '^server:' || true)"
echo "   HTTP  Server: ${hdr_http:-нет ответа}"
echo "   HTTPS Server: ${hdr_https:-нет ответа}"

title="$(curl -s -m 4 "http://$ROUTER_IP/" 2>/dev/null | tr -d '\n' | grep -oiE '<title>[^<]*</title>' | head -1 || true)"
echo "   HTML title  : ${title:-нет}"

if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=4 \
       "root@$ROUTER_IP" true 2>/dev/null; then
    echo "   >>> SSH root без пароля работает -> это OpenWrt"
else
    echo "   SSH root без пароля: нет"
fi

echo
echo "== Итог =="
echo "Если открыт 80 и title/Server похожи на Beeline -> стоковая прошивка."
echo "Если SSH root пускает без пароля            -> OpenWrt."
