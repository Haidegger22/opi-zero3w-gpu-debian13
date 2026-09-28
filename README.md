# OPi Zero 3W — аппаратный GPU (PowerVR) на Debian 13

> Как получить **аппаратные Vulkan / OpenGL ES / OpenCL** на Orange Pi Zero 3W
> под Debian 13 (trixie). Файлы GPU-драйвера берутся из официального образа ОС
> для **Orange Pi 4 Pro** — платы с тем же SoC (Allwinner A733), где стек уже
> встроен вендором и работает.
> Проверено 06.09.2026: ядро **6.6.98-sun60iw2**, образ 1.0.2 trixie.

**Что понадобится:** Zero 3W с Debian 13 (trixie) + ~1.5 ГБ свободного места
на компьютере. Покупать OPi 4 Pro **не нужно** — файлы достаются прямо из её
образа (шаг 3).

---

## 🚀 Быстрый старт — 7 шагов

### Шаг 1. Скачай образ ОС для OPi 4 Pro (~1.4 ГБ)

Нужные GPU-файлы официально существуют **только внутри этого образа** —
на Zero 3W их нет (в этом весь смысл переноса). Прямая ссылка (Google Drive):

```
https://drive.google.com/uc?export=download&id=1tY4g8hSeAWva2CXQG4AfVeuqNLxrUQGy
```

Скачается файл `Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.7z` —
официальный образ **Debian 13 (trixie) XFCE** для 4 Pro.

> ⚠️ Google Drive упёрся в квоту («Quota exceeded»)? Подожди несколько часов
> или зайди через VPN. Альтернативные ссылки (Google Drive / Baidu) — на
> официальной странице Orange Pi 4 Pro:
> EN: `http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-4-Pro.html`
> CN: `http://www.orangepi.cn/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-4-Pro.html`

### Шаг 2. Распакуй архив

Внутри `.7z` лежат два файла (никаких вложенных папок):
сам образ `*.img` (6.85 ГиБ — готовая «флешка» с системой)
и контрольная сумма `*.img.sha`.

```bash
# Linux/macOS (Windows: 7-Zip через проводник — дальше шаги те же, но без mount — см. Шаг 3)
sudo apt install p7zip-full        # Debian/Ubuntu
7z x Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.7z

# Проверка целостности (необязательно)
sha256sum -c Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.img.sha   # → OK
```

### Шаг 3. Достань GPU-файлы из образа — БЕЗ платы 4 Pro

Образ `.img` — это один ext4-раздел со смещения **33 554 432 байта**
(первые 32 МиБ занимает загрузчик). Смонтируй его и собери архив:

```bash
sudo mkdir -p /mnt/opi4pro
sudo mount -o loop,ro,offset=33554432 \
     Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.img /mnt/opi4pro

# Собрать архив с GPU-стеком (~40 МБ)
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

sudo umount /mnt/opi4pro
```

Готово: `~/pvr-stack.tar.gz` лежит у тебя. Плата 4 Pro не понадобилась.

> 🖥️ **У тебя Windows?** Смонтировать образ не выйдет — самый простой путь:
> установить на компьютер Linux (или WSL) и выполнить шаг 3 там, либо
> воспользоваться разделом «Путь через живую плату» ниже.

> 🔧 **Есть живая OPi 4 Pro?** Тогда шаг 3 можно заменить на съём архива по SSH —
> см. раздел **«Путь через живую плату»** внизу.

### Шаг 4. Скопируй архив на Zero 3W

```bash
scp ~/pvr-stack.tar.gz orangepi@<IP-адрес-Зеро>:/tmp/
# или любым удобным способом — флешка, облако и т.п.
```

### Шаг 5. Установи на Zero 3W

```bash
sudo tar xzf /tmp/pvr-stack.tar.gz -C /
sudo ldconfig
```

> ⚠️ Почему это безопасно (не ломает GTK4): на 4 Pro PowerVR подключается
> **как ICD** — системный mesa-лоадер остаётся на месте, а `img_icd.json`
> указывает на `/lib/libVK_IMG.so`. Подробности в разделе «Как это работает».

### Шаг 6. Проверь результат

```bash
vulkaninfo --summary     # PowerVR B-Series BXM-4-64 MC1, 1.3.277
eglinfo                  # OpenGL ES renderer: PowerVR B-Series BXM-4-64
clinfo                   # OpenCL 3.0 PowerVR
glxinfo | grep renderer  # llvmpipe — НОРМА (см. «Нюансы PowerVR»)
ls /dev/dri/             # card0, card1, renderD128
```

> Аппаратный *рендерер* desktop-OpenGL (zink) включается отдельно — [`docs/OPENGL-ZINK.md`](docs/OPENGL-ZINK.md):
> `scripts/opengl-zink-verify.sh` покажет `llvmpipe` без слоя и `zink Vulkan 1.3(PowerVR …)` со слоем.

### Шаг 7. Перезагрузка

После ребута модуль ядра `pvrsrvkm` грузится сам (по modalias устройства
`1800000.gpu`). Проверь ещё раз: `vulkaninfo --summary`.

> Если после неудачных экспериментов модуль в состоянии
> `Driver already in bad state. Device open failed [511]` — перезагрузи модуль:
> ```bash
> sudo rmmod pvrsrvkm && sudo insmod /lib/modules/6.6.98-sun60iw2/extra/pvrsrvkm.ko
> # dmesg: DRM pvr 24.2.6603887 initialized, firmware rgx.fw загружен
> ```

---

## Что должно получиться (TL;DR)

| API | Статус | Детали |
|---|---|---|
| **Vulkan 1.3.277** | ✅ аппаратный | PowerVR B-Series BXM-4-64 MC1, DDK 24.2.6603887 |
| **OpenGL ES 3.2** | ✅ аппаратный | Imagination Technologies (EGL-путь) |
| **OpenCL 3.0** | ✅ аппаратный | PowerVR BXM-4-64 |
| **GLX (desktop OpenGL)** | ⚠️ llvmpipe (софт) | **это норма** для PowerVR — так же на 4 Pro |
| **Desktop-OpenGL через zink** | ✅ аппаратный (off-screen/EGL), ❌ в окне | нужен слой feature-strip → [`docs/OPENGL-ZINK.md`](docs/OPENGL-ZINK.md); окна через GLX нет (zink в окне падает) |
| GNOME Wayland | ❌ | нет `EGL_KHR_platform_wayland` у проприетарного EGL |

---

## 🔧 Путь через живую плату (если у тебя есть OPi 4 Pro)

Альтернатива шагу 3: ставим образ на реальную плату 4 Pro и снимаем архив по SSH.

### 1. Записать образ на карту

Нужна microSD от 8 ГБ (или eMMC/NVMe — но проще начать с SD).

```bash
# Найти свою карту (ОСТОРОЖНО: убедись, что это /dev/sdX, а не твой диск!)
lsblk

# Записать образ (X замени на букву своей карты, например sdb)
sudo dd if=Orangepi4pro_1.1.0_debian_trixie_desktop_xfce_linux6.6.98.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Windows/macOS: проще через **Raspberry Pi Imager** или **balenaEtcher**
(выбрать образ → выбрать карту → Write). Вставь карту в 4 Pro, подключи питание,
дождись загрузки (логин `orangepi` / `orangepi`).

### 2. Настроить SSH-доступ

Пароль может не приниматься, если sshd настроен на ключи:

```bash
# на 4 Pro (под пользователем, которым заходите по SSH):
mkdir -p ~/.ssh && echo "ssh-ed25519 AAAA... ваш-ключ" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
```

### 3. Снять GPU-стек с живой платы

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

### 4. Дальше — как в основном рецепте

Забери архив с платы (`scp`), затем выполни **Шаги 5–7** быстрого старта
(установка на Zero 3W, проверка, перезагрузка).

---

## Что реально ускоряется аппаратно

PowerVR BXM-4-64 аппаратно умеет **Vulkan, OpenGL ES (EGL-путь) и OpenCL**.
**Desktop OpenGL через GLX в окне — нет** (в приложении с окном это llvmpipe). Это не баг
установки, а свойство драйвера Imagination — на 4 Pro ровно так же.

> 🌟 **Новое (28.09.2026):** *рендерер* desktop-OpenGL тоже можно сделать аппаратным —
> через **zink** (GL поверх Vulkan) и слой **feature-strip**, который подделывает
> `geometryShader`, отсутствующий у вендорского блоба. Тогда `glxinfo -B` показывает
> `zink Vulkan 1.3(PowerVR B-Series BXM-4-64 MC1)`, GL 2.1 аппаратно. Работает для
> приложений с **off-screen/EGL**; **в окне не работает** (проверено: `glxgears` со слоем
> падает с SIGABRT, софтверный — честно рисует 167,9 FPS; у X-сервера нет DRI3/kmsro).
> Рецепт, замеры и грабли: [`docs/OPENGL-ZINK.md`](docs/OPENGL-ZINK.md),
> скрипты — `scripts/opengl-zink-{install,env,verify}.sh`.

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
  Аппаратного рендерера в окне у PowerVR по-прежнему нет; аппаратный **рендерер**
  (zink, off-screen/EGL) — [`docs/OPENGL-ZINK.md`](docs/OPENGL-ZINK.md).
- **Flutter-приложения** (FlClashX и т.п.): PVR-враппер `libEGL` из `/usr/local/lib`
  не умеет NPOT-текстуры → чёрное окно. Лечится запуском с системной mesa:
  ```bash
  env LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu LIBGL_ALWAYS_SOFTWARE=1 <app>
  ```
  (подробно: [`opi-zero3w-flclashx-debian13`](https://github.com/Haidegger22/opi-zero3w-flclashx-debian13))
- **GNOME Wayland** невозможен (нет `EGL_KHR_platform_wayland`).
  GNOME Shell на X11 рендерит через GLX → софт. Лёгкие DE (MATE/XFCE) работают отлично.

---

## Как это работает (подробности)

### Почему донор — Orange Pi 4 Pro

1. **Тот же SoC** — Allwinner A733 (как на Zero 3W)
2. **Тот же Debian 13 trixie** (ядро 6.6.98-sun60iw2)
3. GPU-стек у неё **встроен вендором и работает**

**Ключевое открытие при сравнении:** на 4 Pro **НЕТ libvulkan в `/usr/local/lib`** —
системный mesa-лоадер остаётся на месте, а PowerVR подключается **как ICD**
(через `/usr/share/vulkan/icd.d/img_icd.json`). Именно поэтому GTK4 не ломается.

### Почему это вообще понадобилось

- **Debian 11 (bullseye):** GPU собирали вручную — модуль ядра `pvrsrvkm` из
  `linux-orangepi` BSP + userspace из Radxa-образа. Рецепт:
  [`orangepi-zero3w-gpu-npu-vpu-debian11`](https://github.com/Haidegger22/orangepi-zero3w-gpu-npu-vpu-debian11).
- **Debian 13 (trixie, образ 1.0.2):** модуль ядра **уже в образе** —
  `/lib/modules/6.6.98-sun60iw2/extra/pvrsrvkm.ko`, грузится сам при старте
  (udev + modprobe по modalias устройства `1800000.gpu`). Собирать **не нужно**.
- **Чего не хватало:** только userspace — библиотеки Vulkan/GLES/OpenCL + firmware.
  Без них весь рендер уходил в **llvmpipe** (софт, рисует CPU).

### ❌ Провал Radxa-тарбола на trixie (важный урок)

Первая попытка — поставить `pvr-userspace.tar.gz` от Radxa (тот, что работал на Debian 11):

- **Сломал GTK4:** их `libvulkan.so.1` (1.3.280) в `/usr/local/lib` перебивала
  системную mesa (1.4.309). В ней нет символа `vkCreateWaylandSurfaceKHR`,
  который требует GTK4 → падали GTK4-приложения.
- На Debian 11 стоял GTK3 — символ не требовался, поэтому конфликта не было.

**Урок:** Radxa-userspace заточен под Ubuntu-образ, для которого собирался.
На trixie его системные либы конфликтуют — **не ставить как есть**.

---

## Связанные репозитории

- [`orangepi-zero3w-gpu-npu-vpu-debian11`](https://github.com/Haidegger22/orangepi-zero3w-gpu-npu-vpu-debian11)
  — сборка GPU-стека для Debian 11 (модуль + Radxa userspace)
- [`opi-zero3w-debian13-adaptation`](https://github.com/Haidegger22/opi-zero3w-debian13-adaptation)
  — адаптация репозиториев Zero 3W под Debian 13
- [`opi-zero3w-flclashx-debian13`](https://github.com/Haidegger22/opi-zero3w-flclashx-debian13)
  — FlClashX на Debian 13 (чёрное окно Flutter → фикс EGL)
- [`opi-zero-3w-disciples2`](https://github.com/Haidegger22/opi-zero-3w-disciples2)
  — Disciples II на Wine: служба RpcSs и COM-классы, звук, полный экран и разбор
  попыток аппаратного рендера ([`docs/RENDERER-EXPERIMENTS.md`](https://github.com/Haidegger22/opi-zero-3w-disciples2/blob/main/docs/RENDERER-EXPERIMENTS.md))
