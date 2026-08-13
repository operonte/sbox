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

## Preparación (Instalación y configuración de librerías)

Para preparar una instalación limpia de Linux (Pop!_OS, Ubuntu, Debian, etc.), copia y ejecuta este bloque completo en tu terminal para instalar dependencias y configurar los puertos necesarios:

```bash
# 1. Actualizar repositorios e instalar dependencias de desarrollo, librerías GTK3 y gestores de portapapeles
sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libgcrypt20-dev wl-clipboard xclip

# 2. Instalar y activar el servicio de descubrimiento por red local (mDNS/DNS-SD)
sudo apt install -y avahi-daemon
sudo systemctl enable --now avahi-daemon

# 3. Configurar el cortafuegos (abrir puerto TCP 47718 de comunicación y puerto UDP 5353 de descubrimiento)
sudo ufw allow 47718/tcp
sudo ufw allow 5353/udp
sudo ufw reload
```

---

## Instalación y Uso en Linux (Paso a Paso)

Una vez preparado el sistema, copia y ejecuta el siguiente bloque para compilar e instalar la aplicación en el menú de tu distribución:

```bash
# 1. Clonar el repositorio y acceder a la carpeta
git clone https://github.com/operonte/sbox.git
cd sbox

# 2. Compilar en modo release e instalar en el sistema (creará el lanzador .desktop en tu menú)
./scripts/install-linux.sh

# 3. Iniciar la aplicación (también puedes buscar "sbox" en tu menú de aplicaciones de escritorio)
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

