# 🛡️ Server Security Init

> Script interactivo de inicialización y hardening para servidores Linux  
> Compatible con **Debian 11/12** y **AlmaLinux 8/9**

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/tu-usuario/server-init/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Distros](https://img.shields.io/badge/distros-Debian%20%7C%20Ubuntu%20%7C%20AlmaLinux%20%7C%20Rocky%20%7C%20RHEL-orange.svg)](#compatibilidad)

---

## Instalación rápida

> **Requisito:** ejecutar como `root` o con `sudo -i` previo.

### Con curl
```bash
bash <(curl -sSL https://raw.githubusercontent.com/tu-usuario/server-init/main/server_init.sh)
```

### Con wget
```bash
bash <(wget -qO- https://raw.githubusercontent.com/tu-usuario/server-init/main/server_init.sh)
```

### Descarga local (recomendado para revisar antes de ejecutar)
```bash
curl -sSL https://raw.githubusercontent.com/tu-usuario/server-init/main/server_init.sh \
     -o server_init.sh
less server_init.sh           # revisar antes de ejecutar
chmod +x server_init.sh
sudo bash server_init.sh
```

---

## 🔄 Auto-actualización

```bash
sudo bash server_init.sh --update
```

Compara la versión local con la de GitHub. Si hay una más nueva, descarga el nuevo script y guarda un backup automático (`server_init.sh.bak.<versión>`).

---

## 🗂️ Estructura del repositorio

```
server-init/
├── server_init.sh   ← Script principal
├── README.md        ← Esta documentación
└── LICENSE
```

---

## Índice

1. [Descripción general](#descripción-general)
2. [Requisitos](#requisitos)
3. [Compatibilidad](#compatibilidad)
4. [Opciones de línea de comandos](#opciones-de-línea-de-comandos)
5. [Módulos](#módulos)
6. [Archivos modificados](#archivos-modificados)
7. [Logs](#logs)
8. [Checklist post-instalación](#checklist-post-instalación)
9. [Referencia rápida de valores por defecto](#referencia-rápida-de-valores-por-defecto)
10. [FAQ](#faq)
11. [Licencia](#licencia)

---

## Descripción general

`server_init.sh` es un script Bash interactivo que guía al administrador por la configuración inicial y el bastionado *(hardening)* completo de un servidor Linux recién desplegado.

Cada módulo es **opcional e independiente**: responde `n` a cualquier pregunta para omitirlo.

```
┌────────────────────────────────────────────────────────────────────┐
│  Módulo  1  →  Idioma, zona horaria, teclado, hostname             │
│  Módulo  2  →  Actualización + herramientas base                   │
│  Módulo  3  →  Usuarios, sudo, claves SSH                          │
│  Módulo  4  →  Puerto, cifrado y opciones SSH                      │
│  Módulo  5  →  UFW (Debian) / firewalld (AlmaLinux)                │
│  Módulo  6  →  Fail2ban — bloqueo de fuerza bruta                  │
│  Módulo  7  →  Sysctl, auditd, servicios, límites                  │
│  Módulo  8  →  NTP / Chrony — sincronización de tiempo             │
│  Módulo  9  →  PAM — contraseñas, faillock, expiración             │
│  Módulo 10  →  AppArmor (Debian) / SELinux (AlmaLinux)             │
│  Módulo 11  →  Blacklist de módulos del kernel                     │
│  Módulo 12  →  Hardening de sudoers                                │
│  Módulo 13  →  Deshabilitar Ctrl+Alt+Del                           │
│  Módulo 14  →  AIDE — integridad de ficheros                       │
│  Módulo 15  →  rkhunter — detección de rootkits                    │
│  Módulo 16  →  Alertas por email (msmtp)                           │
│  Módulo 17  →  Swap — creación y configuración                     │
│  Módulo 18  →  Lynis — auditoría de seguridad                      │
└────────────────────────────────────────────────────────────────────┘
```

---

## Requisitos

| Requisito           | Detalle                                              |
|---------------------|------------------------------------------------------|
| Sistema operativo   | Debian 11/12 · AlmaLinux 8/9 (y compatibles RHEL)   |
| Privilegios         | **root** (o `sudo -i` previo)                        |
| Conexión a internet | Necesaria para instalar paquetes y para `--update`   |
| Shell               | Bash 4+                                              |
| Dependencias        | `curl` o `wget` (para `--update`)                    |

---

## Compatibilidad

El script detecta automáticamente la distribución al arrancar (`/etc/os-release`) y ramifica todo el comportamiento en dos familias: **Debian** y **RHEL**. Dentro de cada familia, las distros compatibles comparten gestor de paquetes y herramientas de sistema, por lo que el soporte es prácticamente completo.

### Soporte nativo (desarrollado y probado)

| Distribución       | Versiones   | Familia   | Gestor  |
|--------------------|-------------|-----------|---------|
| Debian             | 11 / 12     | Debian    | `apt`   |
| AlmaLinux          | 8 / 9       | RHEL      | `dnf`   |

### Compatible (misma familia, no probado explícitamente)

| Distribución       | Versiones        | Notas                                              |
|--------------------|------------------|----------------------------------------------------|
| Ubuntu             | 22.04 / 24.04    | Misma base que Debian; AppArmor activo por defecto |
| Rocky Linux        | 8 / 9            | Drop-in de AlmaLinux; comportamiento idéntico      |
| RHEL               | 8 / 9            | Fuente original de AlmaLinux; funciona sin cambios |
| CentOS Stream      | 8 / 9            | Ligeras diferencias de paquetes, funcional         |
| Oracle Linux       | 8 / 9            | Compatible RHEL; sin diferencias relevantes        |

### No soportado

| Distribución       | Motivo                                                      |
|--------------------|-------------------------------------------------------------|
| openSUSE / SLES    | Familia distinta (`zypper`), requeriría rama adicional      |
| Arch Linux         | Rolling release, sin versiones estables fijas               |
| Alpine Linux       | `ash`/`musl libc`, comandos y rutas incompatibles           |
| Fedora             | Versiones cambiantes; más adecuado para escritorio          |

> **Nota sobre versiones antiguas:** Debian 10 y CentOS 7 pueden funcionar parcialmente, pero algunos módulos dependen de `pam_faillock` y `chrony` que no están disponibles o tienen nombre distinto en esas versiones.

---

## Opciones de línea de comandos

```
Uso: bash server_init.sh [OPCIÓN]

  (sin opciones)   Ejecuta el asistente de configuración completo
  --update,  -u   Actualiza el script desde GitHub
  --version, -v   Muestra la versión instalada
  --help,    -h   Muestra la ayuda
```

---

## Módulos

### Módulo 1 — Configuración del sistema

Muestra el valor actual de cada parámetro y pregunta si es correcto. Solo modifica lo que el usuario rechace.

| Parámetro    | Descripción                       | Ejemplo            |
|--------------|-----------------------------------|--------------------|
| Zona horaria | Identificador IANA tz             | `Europe/Madrid`    |
| Locale       | Idioma y codificación             | `es_ES.UTF-8`      |
| Teclado      | Keymap del sistema                | `es`               |
| Hostname     | Nombre del servidor en la red     | `web-prod-01`      |

---

### Módulo 2 — Actualización del sistema

- Actualiza todos los paquetes instalados.
- Instala utilidades base: `curl`, `wget`, `vim`, `net-tools`.
- Opcionalmente activa actualizaciones de seguridad automáticas:
  - **Debian/Ubuntu**: `unattended-upgrades`
  - **AlmaLinux/RHEL**: `dnf-automatic`

---

### Módulo 3 — Gestión de usuarios

- Crea un usuario administrador con acceso `sudo`/`wheel`.
- Permite instalar una clave pública SSH para ese usuario.
- Bloquea (opcionalmente) el login directo de `root`.
- Permite cambiar la contraseña de `root`.

> 🔒 Crea siempre el usuario admin **antes** de bloquear root.

---

### Módulo 4 — Hardening SSH

Reemplaza `/etc/ssh/sshd_config` con una configuración endurecida (backup automático previo).

| Parámetro                | Defecto | Descripción                                    |
|--------------------------|:-------:|------------------------------------------------|
| Puerto SSH               | `2222`  | Evita scanners automáticos en el puerto 22     |
| `PermitRootLogin`        | `no`    | Bloquea login directo de root                  |
| `PasswordAuthentication` | `no`    | Fuerza uso de claves SSH                       |
| `MaxAuthTries`           | `3`     | Reintentos antes de desconectar                |
| `MaxSessions`            | `3`     | Sesiones SSH concurrentes máximas              |
| `LoginGraceTime`         | `30` s  | Tiempo para autenticarse                       |
| `ClientAliveInterval`    | `300` s | Keepalive al cliente                           |

**Suite de cifrado hardened:**
```
KexAlgorithms : curve25519-sha256, diffie-hellman-group14-sha256
Ciphers       : chacha20-poly1305, aes256-gcm, aes128-gcm
MACs          : hmac-sha2-512-etm, hmac-sha2-256-etm
```

---

### Módulo 5 — Firewall

| Distribución      | Herramienta | Política base               |
|-------------------|-------------|-----------------------------|
| Debian/Ubuntu     | UFW         | `deny incoming` / `allow outgoing` |
| AlmaLinux/RHEL    | firewalld   | Zona `public` por defecto   |

Abre el puerto SSH personalizado, HTTP/HTTPS (opcionales) y puertos adicionales que el usuario indique.

---

### Módulo 6 — Fail2ban

| Parámetro  | Defecto   | Descripción                           |
|------------|:---------:|---------------------------------------|
| `bantime`  | `3600` s  | Duración del baneo                    |
| `findtime` | `600` s   | Ventana de conteo de intentos         |
| `maxretry` | `5`       | Intentos antes de banear              |

Jails activas: `[sshd]` (estándar) y `[sshd-ddos]` (anti-volumétrico).

```bash
fail2ban-client status sshd         # IPs baneadas
fail2ban-client unban <IP>          # desbanear
```

---

### Módulo 7 — Hardening adicional

- **sysctl**: ASLR, SYN cookies, rp_filter, bloqueo de ICMP broadcast, restricción de dmesg/kptr.
- **limits.conf**: `nofile` y `nproc` a 65 535 para todos los usuarios.
- **Servicios**: deshabilita `avahi-daemon`, `cups`, `bluetooth`, `rpcbind`.
- **Permisos**: restringe `at`, `crontab`, `su`.
- **auditd**: instala y activa el demonio de auditoría del SO.
- **IPv6**: opción de deshabilitarlo vía sysctl.

---

### Módulo 8 — NTP / Chrony

Instala y configura `chrony` para sincronización de tiempo precisa.

| Parámetro        | Defecto         |
|------------------|-----------------|
| Servidor NTP     | `pool.ntp.org`  |

Habilita `timedatectl set-ntp true` y añade pools secundarios `0-2.pool.ntp.org`.

---

### Módulo 9 — PAM — Política de contraseñas

#### Complejidad (pam_pwquality)

| Parámetro        | Defecto |
|------------------|:-------:|
| Longitud mínima  | `12`    |
| Mayúsculas       | `1`     |
| Minúsculas       | `1`     |
| Dígitos          | `1`     |
| Caracteres esp.  | `1`     |
| Máx. repetidos   | `3`     |

#### Bloqueo por intentos fallidos (pam_faillock)

| Parámetro      | Defecto  |
|----------------|:--------:|
| `deny`         | `5`      |
| `unlock_time`  | `900` s  |

#### Expiración de contraseñas (chage + login.defs)

| Parámetro        | Defecto |
|------------------|:-------:|
| PASS_MAX_DAYS    | `90`    |
| PASS_MIN_DAYS    | `1`     |
| PASS_WARN_AGE    | `14`    |

---

### Módulo 10 — AppArmor / SELinux

| Distribución   | MAC         | Acción                                              |
|----------------|-------------|-----------------------------------------------------|
| Debian/Ubuntu  | AppArmor    | Instala, habilita, opcionalmente pone perfil `enforce` |
| AlmaLinux/RHEL | SELinux     | Verifica estado, ofrece pasar a `Enforcing`         |

---

### Módulo 11 — Blacklist de módulos del kernel

Escribe `/etc/modprobe.d/blacklist-hardening.conf`. El usuario elige qué módulos bloquear:

| Módulo         | Motivo                                          |
|----------------|-------------------------------------------------|
| `usb-storage`  | Riesgo de exfiltración de datos vía USB         |
| `firewire-core`| Acceso DMA directo a memoria                    |
| `cramfs`       | Sistema de archivos raramente necesario         |
| `freevxfs`     | Sistema de archivos raramente necesario         |
| `jffs2`        | Sistema de archivos raramente necesario         |
| `hfs`/`hfsplus`| Sistemas de archivos macOS                     |
| `squashfs`     | Raramente necesario en servidores               |
| `udf`          | Sistema de archivos DVD                         |
| `dccp`         | Protocolo raramente usado                       |
| `sctp`         | Protocolo raramente usado                       |
| `rds`          | Protocolo raramente usado                       |
| `tipc`         | Protocolo raramente usado                       |

---

### Módulo 12 — Hardening de sudoers

Escribe `/etc/sudoers.d/hardening` con opciones configurables:

| Opción                     | Efecto                                              |
|----------------------------|-----------------------------------------------------|
| `timestamp_timeout`        | Tiempo (min) antes de volver a pedir contraseña     |
| `logfile`                  | Registra todos los comandos sudo                    |
| `log_input, log_output`    | Graba entrada/salida de sesiones sudo               |
| `requiretty`               | Requiere TTY (bloquea ejecución no interactiva)     |

---

### Módulo 13 — Deshabilitar Ctrl+Alt+Del

```bash
systemctl mask ctrl-alt-del.target
systemctl daemon-reload
```

Evita que un usuario con acceso físico reinicie el servidor accidentalmente.

---

### Módulo 14 — AIDE (File Integrity Monitoring)

Instala `aide`, inicializa la base de datos de integridad y configura un cron diario.

| Parámetro           | Defecto              |
|---------------------|----------------------|
| Hora de comprobación| `3:00`               |
| Log de resultados   | `/var/log/aide-check.log` |
| Email de alertas    | Opcional             |

```bash
aide --check          # comprobación manual
aide --update         # actualizar base de datos tras cambios legítimos
```

---

### Módulo 15 — rkhunter

Instala `rkhunter` (y opcionalmente `chkrootkit`), actualiza firmas, genera baseline y configura cron semanal.

| Parámetro     | Defecto |
|---------------|:-------:|
| Día de escaneo| `0` (Dom) |
| Hora          | `2:00`  |

```bash
rkhunter --check --skip-keypress    # escaneo manual
rkhunter --update                   # actualizar firmas
```

---

### Módulo 16 — Alertas por email

Instala y configura `msmtp` como MTA ligero con relay SMTP.

| Parámetro   | Descripción                   |
|-------------|-------------------------------|
| SMTP host   | Servidor de correo saliente   |
| SMTP port   | Puerto (defecto: `587`)       |
| Integración | Fail2ban y login SSH          |

- Opción de alerta en cada login SSH exitoso.
- Integración con `destemail` de Fail2ban.

> ⚠️ Verifica las credenciales con: `echo 'Test' | mail -s 'Test' tu@email.com`

---

### Módulo 17 — Swap

Detecta si existe swap; ofrece crear un swapfile si no hay.

| Parámetro   | Defecto                                   |
|-------------|-------------------------------------------|
| Ruta        | `/swapfile`                               |
| Tamaño      | RAM × 1 (≤2 GB RAM) / 4 GB (≤8 GB RAM) / 8 GB (>8 GB) |
| Swappiness  | `10` (óptimo para servidor)               |

Añade la entrada a `/etc/fstab` y aplica `vm.swappiness` vía sysctl.

---

### Módulo 18 — Lynis

Instala `lynis`, actualiza firmas y ejecuta una auditoría completa del sistema.

```bash
lynis audit system     # auditoría manual posterior
```

El informe se guarda en `/var/log/lynis-report-<fecha>.log`.  
El *hardening index* (puntuación de seguridad 0–100) se muestra al finalizar.

---

## Archivos modificados

| Archivo                                  | Módulo | Descripción                                |
|------------------------------------------|:------:|--------------------------------------------|
| `/etc/ssh/sshd_config`                   | 4      | Config. SSH (backup automático)            |
| `/etc/issue.net`                         | 4      | Banner de advertencia SSH                  |
| `/etc/fail2ban/jail.local`               | 6      | Jails de Fail2ban                          |
| `/etc/sysctl.d/99-hardening.conf`        | 7, 17  | Parámetros de kernel + swappiness          |
| `/etc/security/limits.conf`              | 7      | Límites de recursos                        |
| `/etc/hosts`                             | 1      | Actualización de hostname                  |
| `/etc/locale.gen` (Debian)               | 1      | Activación del locale                      |
| `/etc/chrony.conf`                       | 8      | Config. NTP/Chrony                         |
| `/etc/security/pwquality.conf`           | 9      | Complejidad de contraseñas                 |
| `/etc/security/faillock.conf`            | 9      | Bloqueo por intentos fallidos              |
| `/etc/login.defs`                        | 9      | Expiración de contraseñas                  |
| `/etc/modprobe.d/blacklist-hardening.conf`| 11    | Módulos del kernel bloqueados              |
| `/etc/sudoers.d/hardening`               | 12     | Opciones de sudo                           |
| `/etc/msmtprc`                           | 16     | Config. relay SMTP                         |
| `/etc/profile.d/ssh-login-alert.sh`      | 16     | Alerta de login SSH por email              |
| `/swapfile` (o ruta elegida)             | 17     | Fichero de swap                            |
| `/etc/cron.d/aide-check`                 | 14     | Cron de comprobación AIDE                  |
| `/etc/cron.d/rkhunter-check`             | 15     | Cron de escaneo rkhunter                   |

---

## Logs

| Log                              | Descripción                         |
|----------------------------------|-------------------------------------|
| `/var/log/server_init.log`       | Log principal del script            |
| `/var/log/aide-check.log`        | Resultados de comprobaciones AIDE   |
| `/var/log/rkhunter-check.log`    | Resultados de escaneos rkhunter     |
| `/var/log/sudo.log`              | Comandos ejecutados con sudo        |
| `/var/log/msmtp.log`             | Log del relay de correo             |
| `/var/log/lynis-report-<fecha>.log` | Informe de auditoría Lynis       |

---

## Checklist post-instalación

- [ ] Abre una **nueva sesión SSH** al nuevo puerto antes de cerrar la actual.
- [ ] Verifica que puedes `sudo su` con el usuario administrador creado.
- [ ] Comprueba el estado del firewall (`ufw status` / `firewall-cmd --list-all`).
- [ ] Verifica Fail2ban: `fail2ban-client status`
- [ ] Comprueba la sincronización de tiempo: `timedatectl status`
- [ ] Revisa el estado de AppArmor/SELinux: `aa-status` / `getenforce`
- [ ] Ejecuta comprobación manual de AIDE: `aide --check`
- [ ] Ejecuta escaneo manual de rkhunter: `rkhunter --check --skip-keypress`
- [ ] Revisa el log completo: `cat /var/log/server_init.log`
- [ ] Consulta el informe de Lynis: `cat /var/log/lynis-report-*.log`

---

## Referencia rápida de valores por defecto

| Parámetro                    | Defecto          | Recomendación producción     |
|------------------------------|:----------------:|------------------------------|
| Puerto SSH                   | `2222`           | Cualquier puerto alto >1024  |
| Login root SSH               | `no`             | `no`                         |
| Autenticación por contraseña | `no`             | `no` (usar claves)           |
| MaxAuthTries                 | `3`              | `3`                          |
| Fail2ban bantime             | `3600` s (1 h)   | `86400` s (24 h) en prod     |
| Fail2ban maxretry            | `5`              | `3`                          |
| Longitud mínima contraseña   | `12`             | `16` en producción           |
| Expiración contraseña        | `90` días        | `60` días en producción      |
| Sudo timeout                 | `5` min          | `0` (siempre pide pwd)       |
| Swappiness                   | `10`             | `5-10` en servidores         |

---

## FAQ

**¿Puedo ejecutar el script más de una vez?**  
Sí. Los módulos son mayoritariamente idempotentes. El script hace backup automático de `sshd_config` antes de sobreescribir. Revisa posibles duplicados en `limits.conf` si lo ejecutas varias veces.

**¿Qué pasa si pierdo acceso SSH?**  
Conéctate por consola (KVM, VNC, panel del proveedor). Prueba siempre la nueva conexión **antes** de cerrar la sesión actual.

**¿Cómo desbanear una IP en Fail2ban?**
```bash
fail2ban-client unban <IP>
fail2ban-client set sshd unbanip <IP>
```

**¿Cómo ver los módulos de kernel bloqueados?**
```bash
cat /etc/modprobe.d/blacklist-hardening.conf
lsmod | grep usb_storage    # verificar que no está cargado
```

**¿Cómo actualizar la base de datos de AIDE tras cambios legítimos?**
```bash
aide --update
mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
```

**¿Cómo mejorar el hardening index de Lynis?**
```bash
lynis audit system              # ejecutar auditoría
lynis show details <TEST-ID>    # detalle de un test concreto
```

---

## Contribuir

1. Haz un fork del repositorio.
2. Crea una rama: `git checkout -b feature/mi-mejora`
3. Commit: `git commit -m 'Añade soporte para X'`
4. Push: `git push origin feature/mi-mejora`
5. Abre un Pull Request.

---

## Licencia

MIT License — libre para uso, modificación y distribución.  
Se agradece mantener la atribución al proyecto original.

---

*`server_init.sh` v1.0.0 — [https://github.com/tu-usuario/server-init](https://github.com/tu-usuario/server-init)*
