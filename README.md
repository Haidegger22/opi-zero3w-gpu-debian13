# OPi Zero 3W — GPU-стек PowerVR на Debian 13 (перенос с OPi 4 Pro)

> Как получить **аппаратные** Vulkan / OpenGL ES / OpenCL на Orange Pi Zero 3W
> под Debian 13 (trixie), перенеся userspace-часть GPU-стека с **Orange Pi 4 Pro**
> — платы с тем же SoC, где стек уже встроен вендором и работает.
> Проверено 06.09.2026: ядро **6.6.98-sun60iw2**, образ 1.0.2 trixie.

## TL;DR — результат

| API | Статус | Детали |
|---|---|---|
| **Vulkan 1.3.277** | ✅ аппаратный | PowerVR B-Series BXM-4-64 MC1, DDK 24.2.6603887 |
| **OpenGL ES 3.2** | ✅ аппаратный | Imagination Technologies (EGL-путь) |
| **OpenCL 3.0** | ✅ аппаратный | PowerVR BXM-4-64 |
| **GLX (desktop OpenGL)** | ⚠️ llvmpipe (софт) | **это норма** для PowerVR — так же на 4 Pro |
| GNOME Wayland | ❌ | нет `EGL_KHR_platform_wayland` у проприетарного EGL |

Проверка одной командой:
```bash
vulkaninfo --summary | grep -E "deviceName|apiVersion|driverName"
# deviceName   = PowerVR B-Series BXM-4-64 MC1
# apiVersion   = 1.3.277
```

> ❓ **Откуда взять ОС донора (OPi 4 Pro)?** Всё, что нужно, — скачать
> официальный образ и достать из него GPU-файлы. Прямая ссылка и пошаговая
> инструкция — в разделе **«Шаг 0. Где взять донора»** ниже. Плату 4 Pro
> покупать не обязательно: файлы можно вытащить прямо из образа.

---

## Предыстория: почему вообще понадобилось

- **Debian 11 (bullseye):** GPU собирали вручную — модуль ядра `pvrsrvkm` из
  `linux-orangepi` BSP + userspace из Radxa-образа. Рецепт:
  [`orangepi-zero3w-gpu-npu-vpu-debian11`](https://github.com/Haidegger22/orangepi-zero3w-gpu-npu-vpu-debian11).
- **Debian 13 (trixie, образ 1.0.2):** модуль ядра **уже в образе** —
  `/lib/modules/6.6.98-sun60iw2/extra/pvrsrvkm.ko`, грузится сам при старте
  (udev + modprobe по modalias устройства `1800000.gpu`). Собирать **не нужно**.
- **Чего не хватало:** только userspace — библиотеки Vulkan/GLES/OpenCL + firmware.
  Без них весь рендер уходил в **llvmpipe** (софт, рисует CPU).

---

## ❌ Провал Radxa-тарбола на trixie (важный урок)

Первая попытка — поставить `pvr-userspace.tar.gz` от Radxa (тот, что работал на Debian 11):

- **Сломал GTK4:** их `libvulkan.so.1` (1.3.280) в `/usr/local/lib` перебивала
  системную mesa (1.4.309). В ней нет символа `vkCreateWaylandSurfaceKHR`,
  который требует GTK4 → падали GTK4-приложения.
- На Debian 11 стоял GTK3 — символ не требовался, поэтому конфликта не было.

**Урок:** Radxa-userspace заточен под Ubuntu-образ, для которого собирался.
На trixie его системные либы конфликтуют — **не ставить как есть**.

---

## ✅ Решение: донор — Orange Pi 4 Pro

**Почему 4 Pro — идеальный донор:**

1. **Тот же SoC** — Allwinner A733 (как на Zero 3W)
2. **Тот же Debian 13 trixie** (ядро 6.6.98-sun60iw2)
3. GPU-стек у неё **встроен вендором и работает**

**Ключевое открытие при сравнении:** на 4 Pro **НЕТ libvulkan в `/usr/local/lib`** —
системный mesa-лоадер остаётся на месте, а PowerVR подключается **как ICD**
(через `/usr/share/vulkan/icd.d/img_icd.json`). Именно поэтому GTK4 не ломается.

---

## 📥 Шаг 0. Где взять донора (ОС для Orange Pi 4 Pro)

> Нужные файлы GPU-стека официально существуют **только внутри образа ОС для
> Orange Pi 4 Pro** (у Zero 3W их нет — в этом весь смысл переноса).
> Сам образ сделан для платы **4 Pro**, но файлы из него подходят и Zero 3W:
> SoC одинаковый (Allwinner A733).

Есть **два пути** — выбирай по ситуации:

| Путь | Когда нужен | Что делаем |
|---|---|---|
| **А. Через живую плату** | У тебя **есть** OPi 4 Pro | Ставим на неё эту ОС, заходим по SSH и снимаем архив (шаги 1–6 ниже) |
| **Б. Без платы, из образа** | Платы **нет**, есть только Zero 3W | Скачиваем образ и вытаскиваем те же файлы прямо из него на компьютере |

Путь Б ничем не хуже: файлы внутри образа идентичны тем, что снимаются с живой
платы. Если платы нет — просто пропусти шаги 1–2 и сразу переходи к разделу
«Вариант Б» ниже.

### Ссылка на образ (общая для обоих путей)

**Прямая ссылка (Google Drive, ~1.4 ГБ):**

```
https://drive.google.com/uc?export=download&id=1tY4g8hSeAWva2CXQG4AfVeuqNLxrUQGy
```

Файл: `Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.7z` —
официальный образ **Debian 13 (trixie) XFCE**, ядро `6.6.98-sun60iw2`
(релиз 1.1.0, июль 2026).

> ⚠️ Если Google Drive упрётся в квоту («Quota exceeded») — подожди несколько
> часов или зайди через VPN. Официальная страница со всеми ссылками
> (Google Drive / Baidu):
> EN: `http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-4-Pro.html`
> CN: `http://www.orangepi.cn/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-4-Pro.html`

### Что внутри архива

В `.7z` лежат **два файла** (никаких вложенных папок):

```
Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.7z   (~1.4 ГБ, архив)
└── Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.img   (6.85 ГиБ — сам образ ОС)
└── Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.img.sha   (контрольная сумма)
```

Образ `.img` — это готовая «флешка»: внутри один раздел с системой
(загрузчик занимает первые 32 МиБ, дальше rootfs). Распаковка:

```bash
# Linux/macOS (Windows — 7-Zip из проводника, дальше см. запись на карту)
sudo apt install p7zip-full   # Debian/Ubuntu
7z x Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.7z
```

Проверка целостности (необязательно, но полезно):

```bash
sha256sum -c Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.img.sha
# ожидаемо: OK  (sha256: 257db23c…d357c)
```

### Вариант А: записать образ на плату 4 Pro

Нужна microSD от 8 ГБ (или eMMC/NVMe — но проще начать с SD).

```bash
# 1. Найти свою карту (ОСТОРОЖНО: убедись, что это /dev/sdX, а не твой диск!)
lsblk

# 2. Записать образ (X замени на букву своей карты, например sdb)
sudo dd if=Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Windows/macOS: проще через **Raspberry Pi Imager** или **balenaEtcher**
(выбрать образ → выбрать карту → Write). После записи: вставь карту в 4 Pro,
подключи питание, дождись загрузки (логин `orangepi` / `orangepi`) — и дальше
по шагам 1–6 ниже.

### Вариант Б: вытащить GPU-файлы из образа БЕЗ платы

Всё делается на обычном Linux-ПК (или прямо на Zero 3W). Образ — это один
раздел ext4, начинающийся со смещения **33 554 432 байта** (32 МиБ).

```bash
# 1. Смонтировать образ (только чтение)
sudo mkdir -p /mnt/opi4pro
sudo mount -o loop,ro,offset=33554432 \
     Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.img /mnt/opi4pro

# 2. Собрать архив с GPU-стеком (те же файлы, что снимает Шаг 2 с живой платы)
sudo tar czf ~/pvr-stack.tar.gz \
  -C /mnt/opi4pro \
  usr/lib/libVK_IMG.so* usr/lib/libsrv_um* usr/lib/libusc* usr/lib/libufwriter* \
  usr/lib/libglslcompiler* usr/lib/libPVROCL* usr/lib/libPVRScopeServices* \
  usr/lib/libsutu_display* usr/lib/libGLESv1_CM_PVR_MESA* usr/lib/libGLESv2_PVR_MESA* \
  usr/lib/libpvr_dri_support* usr/lib/libOpenCL.so* \
  usr/local/lib/libEGL.so* usr/local/lib/libgbm.so* usr/local/lib/libglapi* \
  usr/local/lib/libGLESv1_CM.so* usr/local/lib/libGLESv2.so* \
  usr/local/lib/libpvr_mesa_wsi.so* \
  usr/local/lib/dri/pvr_dri.so usr/local/lib/dri/sunxi-drm_dri.so usr/local/lib/dri/swrast_dri.so \
  usr/lib/firmware/rgx.fw.* usr/lib/firmware/rgx.sh* \
  usr/share/vulkan/icd.d/img_icd.json \
  etc/OpenCL/vendors/pvr.icd \
  etc/ld.so.conf.d/00-pvr-priority.conf

# 3. Отмонтировать
sudo umount /mnt/opi4pro
```

Архив `~/pvr-stack.tar.gz` готов (~40 МБ) — теперь переходи к **Шагу 3**
(залить на Zero 3W), шаги 1–2 пропускаются: доступ к плате и съём файлов
уже не нужны.

---

### Шаг 1. Доступ к донору

> Этот шаг нужен **только для Варианта А** (есть живая плата 4 Pro).
> Если ты вытащил файлы из образа (Вариант Б) — сразу иди к Шагу 3.

SSH-ключ на 4 Pro (пароль может не приниматься, если sshd настроен на ключи):
```bash
# на 4 Pro (под пользователем, которым заходите по SSH):
mkdir -p ~/.ssh && echo "ssh-ed25519 AAAA... ваш-ключ" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
```

### Шаг 2. Снять раскладку GPU-стека с донора

```bash
# на 4 Pro: собрать архив (~40 MB)
sudo tar czf /tmp/pvr-stack.tar.gz \
  /usr/lib/libVK_IMG.so* \
  /usr/lib/libsrv_um* /usr/lib/libusc* /usr/lib/libufwriter* \
  /usr/lib/libglslcompiler* /usr/lib/libPVROCL* /usr/lib/libPVRScopeServices* \
  /usr/lib/libsutu_display* /usr/lib/libGLESv1_CM_PVR_MESA* /usr/lib/libGLESv2_PVR_MESA* \
  /usr/lib/libpvr_dri_support* /usr/lib/libOpenCL.so* \
  /usr/local/lib/libEGL.so* /usr/local/lib/libgbm.so* /usr/local/lib/libglapi* \
  /usr/local/lib/libGLESv1_CM.so* /usr/local/lib/libGLESv2.so* \
  /usr/local/lib/libpvr_mesa_wsi.so* \
  /usr/local/lib/dri/pvr_dri.so /usr/local/lib/dri/sunxi-drm_dri.so /usr/local/lib/dri/swrast_dri.so \
  /usr/lib/firmware/rgx.fw.* /usr/lib/firmware/rgx.sh* \
  /usr/share/vulkan/icd.d/img_icd.json \
  /etc/OpenCL/vendors/pvr.icd \
  /etc/ld.so.conf.d/00-pvr-priority.conf
```

> ⚠️ Что важно в архиве: `img_icd.json` содержит **абсолютный путь**
> `library_path=/lib/libVK_IMG.so`, а `pvr.icd` → `/lib/libPVROCL.so`.

### Шаг 3. Залить и установить на Zero 3W

```bash
# скопировать архив на Zero, затем:
sudo tar xzf /tmp/pvr-stack.tar.gz -C /
sudo ldconfig
```

### Шаг 4. Если модуль в bad state

После неудачных экспериментов `pvrsrvkm` может быть в состоянии
`Driver already in bad state. Device open failed [511]`. Лечится перезагрузкой модуля:
```bash
sudo rmmod pvrsrvkm && sudo insmod /lib/modules/6.6.98-sun60iw2/extra/pvrsrvkm.ko
# dmesg: DRM pvr 24.2.6603887 initialized, firmware rgx.fw загружен
```

### Шаг 5. Проверка результата

```bash
vulkaninfo --summary     # PowerVR B-Series BXM-4-64 MC1, 1.3.277
eglinfo                  # OpenGL ES renderer: PowerVR B-Series BXM-4-64
clinfo                   # OpenCL 3.0 PowerVR
glxinfo | grep renderer  # llvmpipe — НОРМА (desktop GL не поддержан аппаратно)
ls /dev/dri/             # card0, card1, renderD128
```

### Шаг 6. Перезагрузка

После ребута модуль грузится сам (по modalias `1800000.gpu`), Vulkan снова аппаратный.
Проверка: `vulkaninfo --summary` после перезагрузки.

---

## Что реально ускоряется аппаратно

PowerVR BXM-4-64 аппаратно умеет **Vulkan, OpenGL ES (EGL-путь) и OpenCL**.
**Desktop OpenGL через GLX — нет в принципе** (всегда llvmpipe). Это не баг
установки, а свойство драйвера Imagination — на 4 Pro ровно так же.

### ✅ Аппаратно

| Программа | Как | Статус |
|---|---|---|
| **RetroArch** | `video_driver = "vulkan"` | ✅ проверено (NES/GBC, скриншоты чистые) |
| **Chromium** | запуск с `--use-angle=vulkan` | ✅ GL через Vulkan, WebGL аппаратный |
| **Vulkan-приложения** | нативно | ✅ (игры, эмуляторы с Vulkan-бэкендом) |
| **OpenCL-вычисления** | нативно | ✅ |
| **GTK4 / Flutter** | через EGL/GLES | ⚠️ нужен правильный EGL (см. ниже) |

### ⚠️ Нюансы PowerVR

- **GLX-приложения** (старый desktop OpenGL): рендер софтовый (llvmpipe).
  Пример: VCMI (Герои III) — 2D-изометрия, софта хватает с запасом.
- **Flutter-приложения** (FlClashX и т.п.): PVR-враппер `libEGL` из `/usr/local/lib`
  не умеет NPOT-текстуры → чёрное окно. Лечится запуском с системной mesa:
  ```bash
  env LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu LIBGL_ALWAYS_SOFTWARE=1 <app>
  ```
  (подробно: [`opi-zero3w-flclashx-debian13`](https://github.com/Haidegger22/opi-zero3w-flclashx-debian13))
- **GNOME Wayland** невозможен (нет `EGL_KHR_platform_wayland`).
  GNOME Shell на X11 рендерит через GLX → софт. Лёгкие DE (MATE/XFCE) работают отлично.

---

## Связанные репозитории

- [`orangepi-zero3w-gpu-npu-vpu-debian11`](https://github.com/Haidegger22/orangepi-zero3w-gpu-npu-vpu-debian11)
  — сборка GPU-стека для Debian 11 (модуль + Radxa userspace)
- [`opi-zero3w-debian13-adaptation`](https://github.com/Haidegger22/opi-zero3w-debian13-adaptation)
  — адаптация репозиториев Zero 3W под Debian 13
- [`opi-zero3w-flclashx-debian13`](https://github.com/Haidegger22/opi-zero3w-flclashx-debian13)
  — FlClashX на Debian 13 (чёрное окно Flutter → фикс EGL)
