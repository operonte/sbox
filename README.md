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

## Requisitos

- Flutter 3.44+ (Dart 3.12+)
- Linux: GTK3, `wl-clipboard` (lectura de portapapeles en Wayland)
- Android: SDK + un dispositivo con depuración USB para desarrollo

## Desarrollo

```bash
# Caja de escritorio (Pop!_OS / Linux)
cd app && flutter run -d linux

# Android (con un dispositivo conectado)
cd app && flutter run -d android

# APK de prueba (sideload)
cd app && flutter build apk --debug
```

- [x] Esqueleto del monorepo (app + sbox_core)
- [x] Caja flotante de escritorio (frameless, translúcida, always-on-top)
- [x] Descubrimiento por LAN (mDNS) + canal WebSocket P2P
- [x] Emparejamiento con código de 6 dígitos
- [x] Transferencia de texto y archivos
- [x] Drag & drop y lectura de portapapeles en escritorio (incluyendo soporte nativo GTK para imágenes)
- [x] Widget interactivo y servicio en primer plano (Android)

