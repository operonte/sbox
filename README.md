# sbox

Portapapeles universal y rápido entre **PC (Pop!_OS / Linux)** y **Android**.
Pasa texto y archivos al instante entre tus dispositivos, sin cuentas ni nube.

> **Estado:** en construcción. La UI de la caja flotante de escritorio ya funciona;
> la capa de red (descubrimiento + transferencia por LAN) es lo siguiente.

## Idea

- **Sin servidor, sin backend, sin nube.** Los dos dispositivos hablan **directo por la red local (LAN)**.
- **Sin cuentas.** Un código de 6 dígitos (decorativo/formal) confirma "esta es mi otra caja".
- **Efímero.** Solo lo último que copiaste o soltaste; nada se guarda.
- **Mismo código base en Flutter** para Android y escritorio Linux.

La caja de escritorio es una ventana pequeña, sin bordes, translúcida y *always-on-top*,
con el mismo lenguaje visual minimalista oscuro del prototipo móvil (ver [`prototipo/`](prototipo/)).

## Estructura

```
sbox/
├── prototipo/            # mockups de diseño (Figma) de referencia
├── app/                  # app Flutter única (Android + Linux desktop)
│   ├── lib/              # UI (caja flotante, emparejamiento, configuración)
│   ├── linux/            # runner GTK (frameless + transparencia)
│   └── android/          # widget 2×2 nativo (próximamente)
└── packages/
    └── sbox_core/        # lógica compartida: descubrimiento LAN + protocolo (próximamente)
```

## Requisitos del Sistema (Linux / Ubuntu / Pop!_OS)

Para compilar, ejecutar y usar `sbox` en una instalación limpia de Linux, se deben cumplir los siguientes requisitos:

### 1. Dependencias de Compilación y Ejecución
Instala las herramientas esenciales de desarrollo, las bibliotecas de GTK3 y los gestores de portapapeles (`wl-clipboard` para Wayland, `xclip` para X11):
```bash
sudo apt update
sudo apt install -y \
  clang \
  cmake \
  ninja-build \
  pkg-config \
  libgtk-3-dev \
  liblzma-dev \
  libgcrypt20-dev \
  wl-clipboard \
  xclip
```

### 2. Descubrimiento por Red Local (mDNS)
Sbox utiliza `avahi-daemon` para el descubrimiento automático de dispositivos por mDNS/DNS-SD en la red local. Asegúrate de tenerlo instalado, activo y habilitado:
```bash
sudo apt install -y avahi-daemon
sudo systemctl enable --now avahi-daemon
```

### 3. Configuración del Cortafuegos (UFW)
Si tu cortafuegos está activo, bloqueará las conexiones entrantes desde el celular. Debes abrir el puerto de comunicación de Sbox (TCP `47718`) y el puerto de descubrimiento mDNS (UDP `5353`):
```bash
sudo ufw allow 47718/tcp
sudo ufw allow 5353/udp
sudo ufw reload
```

---

## Instalación y Uso en Linux (Paso a Paso)

### Paso 1: Clonar el repositorio
```bash
git clone https://github.com/operonte/sbox.git
cd sbox
```

### Paso 2: Compilar e instalar la aplicación de escritorio
Ejecuta el script de instalación para compilar el proyecto en modo `release` e instalar el binario junto con un lanzador (`.desktop`) para que aparezca en el menú de tus aplicaciones:
```bash
./scripts/install-linux.sh
```

### Paso 3: Lanzar la aplicación
Busca **sbox** en el menú de aplicaciones de tu distribución o ejecuta directamente:
```bash
~/.local/opt/sbox/sbox
```

---

## Desarrollo y Depuración

Si quieres desarrollar o depurar el código fuente:

* **Flutter SDK:** Asegúrate de tener instalado Flutter 3.44+ (Dart 3.12+).
* **Android SDK:** Requerido si deseas compilar para el celular.

```bash
# Ejecutar la caja de escritorio (Linux) en modo debug
cd app && flutter run -d linux

# Ejecutar en el celular Android (con depuración USB activa)
cd app && flutter run -d android

# Compilar un APK de prueba (debug)
cd app && flutter build apk --debug

# Compilar el APK definitivo (release)
cd app && flutter build apk --release
```

- [x] Esqueleto del monorepo (app + sbox_core)
- [x] Caja flotante de escritorio (frameless, translúcida, always-on-top)
- [x] Descubrimiento por LAN (mDNS) + canal WebSocket P2P
- [x] Emparejamiento con código de 6 dígitos
- [x] Transferencia de texto y archivos
- [x] Drag & drop y lectura de portapapeles en escritorio (incluyendo soporte nativo GTK para imágenes)
- [x] Widget interactivo y servicio en primer plano (Android)

