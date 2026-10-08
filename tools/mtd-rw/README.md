# mtd-rw — модуль, снимающий защиту с MTD-разделов

`mtd-rw` временно выставляет флаг `MTD_WRITEABLE` всем MTD-разделам.

Он нужен потому, что OpenWrt помечает разделы **второго слота прошивки**
(`Kernel 2` / `mtd5` и `File System 2` / `mtd7`) как `read-only` в device tree,
и записать туда OpenWrt штатными средствами невозможно:

```
dd: error writing '/dev/mtdblock5': Operation not permitted
```

После загрузки модуля `mtd5` получает `flags=0x400` и становится доступен на запись.

## Использование

```sh
scp tools/mtd-rw/mtd-rw.ko root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'insmod /tmp/mtd-rw.ko i_want_a_brick=1'
ssh root@192.168.1.1 'cat /sys/class/mtd/mtd5/flags'    # должно стать 0x400
```

Вернуть флаги обратно: `rmmod mtd_rw`.

Имя параметра `i_want_a_brick` — авторское, и оно честное: модуль снимает защиту
со **всех** разделов, включая загрузчик `mtd0`. Запись не туда действительно
превращает устройство в кирпич. Используйте осознанно.

## Происхождение и лицензия

* Пакет: [`kernel/mtd-rw`](https://github.com/openwrt/packages/tree/openwrt-23.05/kernel/mtd-rw)
  из официального репозитория OpenWrt, ветка `openwrt-23.05`.
* Исходный код модуля: [jclehner/mtd-rw](https://github.com/jclehner/mtd-rw),
  коммит `7e8562067d6a366c8cbaa8084396c33b7e12986b`.
* Лицензия: **GPL-2.0** (полный текст — в корневом [`LICENSE`](../../LICENSE)).
  Копия исходника приложена в [`src/mtd-rw.c`](src/mtd-rw.c).

## Совместимость

Модуль ядра привязан к версии ядра (vermagic). Файл `mtd-rw.ko` здесь собран под:

```
OpenWrt 23.05.6 · ramips/mt7621 · ядро 5.15.189
vermagic: 5.15.189 SMP mod_unload MIPS32_R2 32BIT
```

Если версия ядра другая — пересоберите модуль:

```sh
./build.sh 23.05.6
```
