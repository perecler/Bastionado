#!/bin/bash
# =============================================================================
#  server_init.sh — Bastionado inicial de servidores Linux
#  Soportado: Debian 11/12 · AlmaLinux 8/9 · Ubuntu 22/24 · Rocky 8/9
#
#  Uso rápido (sin clonar el repo):
#    bash <(curl -sSL https://raw.githubusercontent.com/tu-usuario/server-init/main/server_init.sh)
#    bash <(wget -qO- https://raw.githubusercontent.com/tu-usuario/server-init/main/server_init.sh)
#
#  Flags disponibles:
#    --update    descarga la última versión desde GitHub y reemplaza este fichero
#    --version   muestra la versión instalada
#    --help      muestra esta ayuda
#
#  El script es completamente interactivo: pregunta antes de tocar nada.
#  Cada módulo se puede saltar respondiendo 'n'.
# =============================================================================

set -euo pipefail

# Versión del script — se usa para comparar con GitHub en --update
VERSION="1.0.0"
REPO_USER="tu-usuario"
REPO_NAME="server-init"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/server_init.sh"
REPO_URL="https://github.com/${REPO_USER}/${REPO_NAME}"

# Códigos de escape ANSI para colorear la salida del terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # reset

# Variables que se rellenan en detect_distro() según la distro detectada
LOG_FILE="/var/log/server_init.log"
DISTRO=""
PKG_MANAGER=""
PKG_UPDATE=""
PKG_INSTALL=""

# Funciones de salida: todas escriben en pantalla y en el log simultáneamente
log()    { echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" | tee -a "$LOG_FILE"; }
ok()     { echo -e "${GREEN}  ✔  $*${NC}"; log "[OK]  $*"; }
info()   { echo -e "${CYAN}  ➜  $*${NC}"; log "[INFO] $*"; }
warn()   { echo -e "${YELLOW}  ⚠  $*${NC}"; log "[WARN] $*"; }
error()  { echo -e "${RED}  ✘  $*${NC}"; log "[ERR]  $*"; }
title()  { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════${NC}"; \
           echo -e "${BOLD}${BLUE}  $*${NC}"; \
           echo -e "${BOLD}${BLUE}══════════════════════════════════════${NC}\n"; }
section(){ echo -e "\n${BOLD}${CYAN}▶ $*${NC}\n"; }

# Pregunta sí/no con valor por defecto configurable.
# Retorna 0 para 'y' y 1 para 'n', compatible con if/&&/||
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local answer
    while true; do
        if [[ "$default" == "y" ]]; then
            read -rp "$(echo -e "${YELLOW}  [?] $prompt [Y/n]: ${NC}")" answer
            answer="${answer:-y}"
        else
            read -rp "$(echo -e "${YELLOW}  [?] $prompt [y/N]: ${NC}")" answer
            answer="${answer:-n}"
        fi
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) echo -e "${RED}  Responde 'y' o 'n'${NC}" ;;
        esac
    done
}

# Pide un valor con un defecto entre corchetes; Enter acepta el defecto
ask_value() {
    local prompt="$1"
    local default="$2"
    local value
    read -rp "$(echo -e "${YELLOW}  [?] $prompt [${default}]: ${NC}")" value
    echo "${value:-$default}"
}

# Pide una contraseña dos veces y no continúa hasta que coincidan.
# No muestra nada en pantalla mientras se escribe (-s).
ask_secret() {
    local prompt="$1"
    local value confirm
    while true; do
        read -rsp "$(echo -e "${YELLOW}  [?] $prompt: ${NC}")" value; echo
        read -rsp "$(echo -e "${YELLOW}  [?] Confirmar contraseña: ${NC}")" confirm; echo
        [[ "$value" == "$confirm" ]] && break
        error "Las contraseñas no coinciden. Inténtalo de nuevo."
    done
    echo "$value"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script debe ejecutarse como root."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Auto-actualización: descarga el script de GitHub, compara VERSION y,
# si hay una versión más nueva, guarda backup del actual y lo reemplaza.
# El backup queda en el mismo directorio con extensión .bak.<versión>
# -----------------------------------------------------------------------------
self_update() {
    title "ACTUALIZACIÓN DEL SCRIPT"
    info "Comprobando versión en GitHub..."

    local downloader=""
    if command -v curl &>/dev/null; then
        downloader="curl"
    elif command -v wget &>/dev/null; then
        downloader="wget"
    else
        error "Se necesita curl o wget para actualizar."
        exit 1
    fi

    local remote_content remote_version
    if [[ "$downloader" == "curl" ]]; then
        remote_content=$(curl -sSL --connect-timeout 10 "$RAW_URL" 2>/dev/null) || {
            error "No se pudo conectar con GitHub. URL: $RAW_URL"; exit 1
        }
    else
        remote_content=$(wget -qO- --timeout=10 "$RAW_URL" 2>/dev/null) || {
            error "No se pudo conectar con GitHub. URL: $RAW_URL"; exit 1
        }
    fi

    # Extraemos la versión de la primera línea VERSION="x.y.z" del script remoto
    remote_version=$(echo "$remote_content" | grep -m1 '^VERSION=' | cut -d'"' -f2)
    [[ -z "$remote_version" ]] && { error "No se pudo leer la versión remota."; exit 1; }

    echo -e "  Versión local  : ${YELLOW}${VERSION}${NC}"
    echo -e "  Versión remota : ${GREEN}${remote_version}${NC}\n"

    if [[ "$remote_version" == "$VERSION" ]]; then
        ok "Ya tienes la última versión (${VERSION})."; exit 0
    fi

    info "Nueva versión disponible: ${remote_version}"
    if ! ask_yes_no "¿Descargar y reemplazar el script actual?" "y"; then
        info "Actualización cancelada."; exit 0
    fi

    local script_path
    script_path="$(realpath "$0")"
    cp "$script_path" "${script_path}.bak.${VERSION}"
    ok "Backup guardado: ${script_path}.bak.${VERSION}"

    echo "$remote_content" > "$script_path"
    chmod +x "$script_path"
    ok "Script actualizado a la versión ${remote_version}."
    info "Vuelve a ejecutar: bash $script_path"
    exit 0
}

show_version() {
    echo -e "${BOLD}server_init.sh${NC} v${VERSION}"
    echo -e "Repositorio : ${CYAN}${REPO_URL}${NC}"
    echo -e "Rama        : ${BRANCH}"
    exit 0
}

# Procesa los flags de línea de comandos antes de requerir root ni tocar nada.
# --update y --version no necesitan privilegios de root.
parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --update|-u)  self_update ;;
            --version|-v) show_version ;;
            --help|-h)
                echo -e "\n${BOLD}Uso:${NC} bash server_init.sh [OPCIÓN]\n"
                echo "  (sin opciones)   Ejecuta el asistente de configuración"
                echo "  --update,  -u   Actualiza el script desde GitHub"
                echo "  --version, -v   Muestra la versión instalada"
                echo "  --help,    -h   Muestra esta ayuda"
                echo -e "\n  ${CYAN}Repo: ${REPO_URL}${NC}\n"
                exit 0
                ;;
            *)
                error "Argumento desconocido: $arg  (usa --help)"
                exit 1
                ;;
        esac
    done
}

# Lee /etc/os-release para saber qué gestor de paquetes usar.
# Si la distro no está en la lista, salimos antes de hacer nada.
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="${ID,,}"
        case "$DISTRO" in
            debian|ubuntu)
                PKG_MANAGER="apt"
                PKG_UPDATE="apt update -y && apt upgrade -y"
                PKG_INSTALL="apt install -y"
                ;;
            almalinux|rhel|centos|rocky)
                PKG_MANAGER="dnf"
                PKG_UPDATE="dnf update -y"
                PKG_INSTALL="dnf install -y"
                ;;
            *)
                error "Distribución no soportada: $DISTRO"
                exit 1
                ;;
        esac
        ok "Distribución detectada: $PRETTY_NAME"
    else
        error "No se puede detectar la distribución."
        exit 1
    fi
}

# =============================================================================
# MÓDULO 1 — Configuración regional y hostname
# =============================================================================

# Muestra el valor actual de un parámetro y pregunta si está bien.
# Si el usuario dice que no, llama al callback para cambiarlo.
# Así evitamos tocar lo que ya está configurado correctamente.
confirm_or_set() {
    local label="$1"
    local current="$2"
    local fn="$3"

    echo -e "  ${BOLD}${label}${NC} actual: ${CYAN}${current}${NC}"
    if ask_yes_no "  ¿Es correcto?" "y"; then
        ok "${label}: ${current} (sin cambios)"
    else
        "$fn"
    fi
    echo ""
}

# Valida la zona horaria contra timedatectl antes de aplicarla,
# para no dejar el sistema con una zona inválida
_set_timezone() {
    info "Zonas comunes: Europe/Madrid | America/New_York | UTC | Asia/Tokyo"
    while true; do
        TIMEZONE=$(ask_value "Nueva zona horaria" "Europe/Madrid")
        if timedatectl list-timezones 2>/dev/null | grep -qx "$TIMEZONE"; then
            timedatectl set-timezone "$TIMEZONE"
            ok "Zona horaria → ${TIMEZONE}"
            break
        else
            error "Zona horaria inválida: '${TIMEZONE}'. Inténtalo de nuevo."
        fi
    done
}

_set_locale() {
    info "Ejemplos: es_ES.UTF-8 | en_US.UTF-8 | ca_ES.UTF-8"
    LOCALE=$(ask_value "Nuevo locale" "es_ES.UTF-8")
    case "$DISTRO" in
        debian|ubuntu)
            $PKG_INSTALL locales >> "$LOG_FILE" 2>&1
            # En Debian, el locale tiene que estar descomentado en locale.gen antes de generarlo.
            # Si ya existe descomentado, no hacemos nada; si está comentado, lo descomentamos;
            # si no aparece, lo añadimos al final.
            if grep -q "^# ${LOCALE}" /etc/locale.gen 2>/dev/null; then
                sed -i "s/^# ${LOCALE}/${LOCALE}/" /etc/locale.gen
            elif ! grep -q "^${LOCALE}" /etc/locale.gen 2>/dev/null; then
                echo "${LOCALE} UTF-8" >> /etc/locale.gen
            fi
            locale-gen "$LOCALE" >> "$LOG_FILE" 2>&1
            update-locale LANG="$LOCALE"
            ;;
        almalinux|rhel|centos|rocky)
            $PKG_INSTALL glibc-langpack-es langpacks-es >> "$LOG_FILE" 2>&1 || true
            localectl set-locale LANG="$LOCALE"
            ;;
    esac
    ok "Locale → ${LOCALE}"
}

# localectl valida el keymap internamente; si falla, el nombre introducido no existe
_set_keymap() {
    info "Ejemplos: es | us | de | fr | it"
    while true; do
        KEYMAP=$(ask_value "Nuevo mapa de teclado" "es")
        if localectl set-keymap "$KEYMAP" 2>/dev/null; then
            ok "Teclado → ${KEYMAP}"
            break
        else
            error "Mapa de teclado inválido: '${KEYMAP}'. Inténtalo de nuevo."
        fi
    done
}

_set_hostname() {
    NEW_HOST=$(ask_value "Nuevo hostname" "servidor")
    hostnamectl set-hostname "$NEW_HOST"
    # Actualizamos también /etc/hosts para que el hostname resuelva en local
    # sin necesidad de DNS. Algunos servicios (como sudo) lo requieren.
    if grep -q "127.0.1.1" /etc/hosts; then
        sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${NEW_HOST}/" /etc/hosts
    else
        echo "127.0.1.1  ${NEW_HOST}" >> /etc/hosts
    fi
    ok "Hostname → ${NEW_HOST}"
}

setup_system() {
    title "1/18  CONFIGURACIÓN DEL SISTEMA"

    if ! ask_yes_no "¿Revisar/configurar idioma, zona horaria y teclado?" "y"; then
        info "Módulo de sistema omitido."; return
    fi

    echo ""

    section "Zona horaria"
    CURRENT_TZ=$(timedatectl show -p Timezone --value 2>/dev/null \
                 || cat /etc/timezone 2>/dev/null || echo "desconocida")
    confirm_or_set "Zona horaria" "$CURRENT_TZ" _set_timezone

    section "Locale / Idioma"
    CURRENT_LOCALE=$(locale 2>/dev/null | grep "^LANG=" | cut -d= -f2 | tr -d '"' || echo "desconocido")
    confirm_or_set "Locale" "$CURRENT_LOCALE" _set_locale

    section "Distribución de teclado"
    CURRENT_KEYMAP=$(localectl status 2>/dev/null \
                     | grep "VC Keymap" | awk '{print $NF}' || echo "desconocido")
    confirm_or_set "Teclado" "$CURRENT_KEYMAP" _set_keymap

    section "Hostname"
    CURRENT_HOST=$(hostname)
    confirm_or_set "Hostname" "$CURRENT_HOST" _set_hostname
}

# =============================================================================
# MÓDULO 2 — Actualización del sistema e instalación de herramientas base
# =============================================================================
update_system() {
    title "2/18  ACTUALIZACIÓN DEL SISTEMA"

    if ! ask_yes_no "¿Actualizar el sistema completo?" "y"; then
        warn "Actualización omitida. Se recomienda actualizar antes de continuar."; return
    fi

    info "Actualizando paquetes..."
    eval "$PKG_UPDATE" >> "$LOG_FILE" 2>&1 && ok "Sistema actualizado."

    # Instalamos las utilidades que usaremos más adelante en el propio script
    case "$DISTRO" in
        debian|ubuntu)
            $PKG_INSTALL curl wget vim net-tools ufw unattended-upgrades \
                         apt-listchanges >> "$LOG_FILE" 2>&1
            ;;
        almalinux|rhel|centos|rocky)
            $PKG_INSTALL curl wget vim net-tools firewalld dnf-automatic \
                         epel-release >> "$LOG_FILE" 2>&1
            ;;
    esac
    ok "Herramientas básicas instaladas."

    if ask_yes_no "¿Habilitar actualizaciones automáticas de seguridad?"; then
        case "$DISTRO" in
            debian|ubuntu)
                dpkg-reconfigure --priority=low unattended-upgrades
                ;;
            almalinux|rhel|centos|rocky)
                sed -i 's/apply_updates = no/apply_updates = yes/' \
                    /etc/dnf/automatic.conf 2>/dev/null || true
                systemctl enable --now dnf-automatic.timer >> "$LOG_FILE" 2>&1
                ;;
        esac
        ok "Actualizaciones automáticas habilitadas."
    fi
}

# =============================================================================
# MÓDULO 3 — Gestión de usuarios: nuevo admin, clave SSH, bloqueo de root
# =============================================================================
manage_users() {
    title "3/18  GESTIÓN DE USUARIOS"

    section "Usuario administrador"
    if ask_yes_no "¿Crear un nuevo usuario administrador (sudo)?" "y"; then
        ADMIN_USER=$(ask_value "Nombre de usuario" "admin")
        ADMIN_PASS=$(ask_secret "Contraseña para '$ADMIN_USER'")

        # useradd falla si el usuario ya existe; en ese caso solo actualizamos la shell
        useradd -m -s /bin/bash "$ADMIN_USER" 2>/dev/null || \
            usermod -s /bin/bash "$ADMIN_USER"
        echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd

        case "$DISTRO" in
            debian|ubuntu) usermod -aG sudo "$ADMIN_USER" ;;
            *)             usermod -aG wheel "$ADMIN_USER" ;;
        esac

        ok "Usuario '$ADMIN_USER' creado y añadido al grupo sudo/wheel."

        if ask_yes_no "¿Copiar clave SSH pública para $ADMIN_USER?"; then
            SSH_KEY=$(ask_value "Pega aquí la clave pública (ssh-rsa ...)" "")
            if [[ -n "$SSH_KEY" ]]; then
                HOME_DIR=$(eval echo "~$ADMIN_USER")
                mkdir -p "$HOME_DIR/.ssh"
                echo "$SSH_KEY" >> "$HOME_DIR/.ssh/authorized_keys"
                chmod 700 "$HOME_DIR/.ssh"
                chmod 600 "$HOME_DIR/.ssh/authorized_keys"
                chown -R "$ADMIN_USER:$ADMIN_USER" "$HOME_DIR/.ssh"
                ok "Clave SSH configurada para $ADMIN_USER."
            fi
        fi
    fi

    section "Cuenta root"
    if ask_yes_no "¿Bloquear login directo de root?" "y"; then
        passwd -l root
        ok "Login root deshabilitado."
    fi

    if ask_yes_no "¿Cambiar la contraseña de root?"; then
        ROOT_PASS=$(ask_secret "Nueva contraseña de root")
        echo "root:$ROOT_PASS" | chpasswd
        ok "Contraseña de root actualizada."
    fi
}

# =============================================================================
# MÓDULO 4 — Hardening de SSH
# Reemplaza sshd_config por completo con una config endurecida.
# Hace backup antes de tocar nada; el backup queda en /etc/ssh/
# =============================================================================
setup_ssh() {
    title "4/18  HARDENING SSH"

    if ! ask_yes_no "¿Configurar hardening de SSH?" "y"; then
        info "SSH omitido."; return
    fi

    SSH_CFG="/etc/ssh/sshd_config"
    cp "$SSH_CFG" "${SSH_CFG}.bak.$(date +%Y%m%d)"
    ok "Backup de sshd_config creado."

    section "Puerto SSH"
    SSH_PORT=$(ask_value "Puerto SSH" "2222")
    # Validamos que sea un puerto no privilegiado y dentro del rango válido
    while ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1024 || SSH_PORT > 65535 )); do
        error "Puerto inválido. Debe estar entre 1024 y 65535."
        SSH_PORT=$(ask_value "Puerto SSH" "2222")
    done

    section "Parámetros de seguridad"
    PERMIT_ROOT=$(ask_yes_no "¿Permitir login SSH de root? (no recomendado)" && echo "yes" || echo "no")
    PASS_AUTH=$(ask_yes_no "¿Permitir autenticación por contraseña? (no recomendado si usas claves)" \
                && echo "yes" || echo "no")
    MAX_AUTH=$(ask_value "Número máximo de intentos de autenticación" "3")
    MAX_SESSIONS=$(ask_value "Número máximo de sesiones simultáneas" "3")
    LOGIN_GRACE=$(ask_value "Tiempo de gracia para login (segundos)" "30")
    KEEP_ALIVE=$(ask_value "Intervalo ClientAlive (segundos)" "300")

    cat > "$SSH_CFG" <<EOF
# /etc/ssh/sshd_config — modificado por server_init.sh el $(date '+%Y-%m-%d')
# Backup del original en ${SSH_CFG}.bak.$(date +%Y%m%d)

# Puerto y protocolo
Port $SSH_PORT
Protocol 2
AddressFamily inet

# Autenticación
PermitRootLogin $PERMIT_ROOT
PasswordAuthentication $PASS_AUTH
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Límites de sesión
MaxAuthTries $MAX_AUTH
MaxSessions $MAX_SESSIONS
LoginGraceTime $LOGIN_GRACE

# Keepalive: el servidor pinga al cliente cada $KEEP_ALIVE s;
# si no responde 2 veces seguidas, cierra la sesión
ClientAliveInterval $KEEP_ALIVE
ClientAliveCountMax 2

# Seguridad adicional
X11Forwarding no
AllowTcpForwarding no
PrintLastLog yes
Banner /etc/issue.net

# Suite de cifrado: solo algoritmos modernos (NIST/RFC 8308).
# Se descartan MD5, SHA1, arcfour y DH de 1024 bits.
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

Subsystem sftp /usr/lib/openssh/sftp-server
EOF

    cat > /etc/issue.net <<'BANNER'
*******************************************************************************
      ACCESO RESTRINGIDO – Servidor privado
      Todo acceso no autorizado será registrado y denunciado.
*******************************************************************************
BANNER

    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        ok "SSH configurado en el puerto $SSH_PORT."
    else
        error "Error al reiniciar SSH. Revisa $SSH_CFG"
    fi
}

# =============================================================================
# MÓDULO 5 — Firewall
# UFW en Debian/Ubuntu, firewalld en AlmaLinux/RHEL.
# El puerto SSH se toma de setup_ssh(); si no se ejecutó antes, usa el 22.
# =============================================================================
setup_firewall() {
    title "5/18  CONFIGURACIÓN DEL FIREWALL"

    if ! ask_yes_no "¿Configurar el firewall?" "y"; then
        info "Firewall omitido."; return
    fi

    SSH_PORT="${SSH_PORT:-22}"
    OPEN_HTTP=$(ask_yes_no "¿Abrir puerto HTTP (80)?" "y" && echo true || echo false)
    OPEN_HTTPS=$(ask_yes_no "¿Abrir puerto HTTPS (443)?" "y" && echo true || echo false)

    EXTRA_PORTS=()
    while ask_yes_no "¿Añadir otro puerto personalizado?"; do
        EXTRA_PORTS+=("$(ask_value "Puerto (ej: 8080/tcp)" "8080/tcp")")
    done

    case "$DISTRO" in
        debian|ubuntu)
            $PKG_INSTALL ufw >> "$LOG_FILE" 2>&1
            ufw --force reset >> "$LOG_FILE" 2>&1  # partimos de cero para evitar reglas antiguas
            ufw default deny incoming
            ufw default allow outgoing
            ufw allow "$SSH_PORT/tcp" comment "SSH"
            [[ "$OPEN_HTTP" == "true" ]]  && ufw allow 80/tcp comment "HTTP"
            [[ "$OPEN_HTTPS" == "true" ]] && ufw allow 443/tcp comment "HTTPS"
            for p in "${EXTRA_PORTS[@]}"; do ufw allow "$p"; done
            ufw --force enable >> "$LOG_FILE" 2>&1
            ok "UFW configurado."
            ufw status verbose
            ;;
        almalinux|rhel|centos|rocky)
            systemctl enable --now firewalld >> "$LOG_FILE" 2>&1
            firewall-cmd --permanent --add-port="$SSH_PORT/tcp"
            [[ "$OPEN_HTTP" == "true" ]]  && firewall-cmd --permanent --add-service=http
            [[ "$OPEN_HTTPS" == "true" ]] && firewall-cmd --permanent --add-service=https
            for p in "${EXTRA_PORTS[@]}"; do firewall-cmd --permanent --add-port="$p"; done
            firewall-cmd --reload >> "$LOG_FILE" 2>&1
            ok "firewalld configurado."
            firewall-cmd --list-all
            ;;
    esac
}

# =============================================================================
# MÓDULO 6 — Fail2ban
# En AlmaLinux necesita EPEL; en Debian está en los repos base.
# jail.local siempre tiene prioridad sobre jail.conf, así que no tocamos jail.conf.
# =============================================================================
setup_fail2ban() {
    title "6/18  FAIL2BAN"

    if ! ask_yes_no "¿Instalar y configurar Fail2ban?" "y"; then
        info "Fail2ban omitido."; return
    fi

    case "$DISTRO" in
        debian|ubuntu) $PKG_INSTALL fail2ban >> "$LOG_FILE" 2>&1 ;;
        almalinux|rhel|centos|rocky)
            $PKG_INSTALL epel-release fail2ban >> "$LOG_FILE" 2>&1 ;;
    esac

    BAN_TIME=$(ask_value "Tiempo de baneo en segundos (ej: 3600=1h, 86400=24h)" "3600")
    FIND_TIME=$(ask_value "Ventana de tiempo para contar intentos (segundos)" "600")
    MAX_RETRY=$(ask_value "Máximo de intentos antes de banear" "5")
    SSH_PORT="${SSH_PORT:-22}"

    cat > /etc/fail2ban/jail.local <<EOF
# /etc/fail2ban/jail.local — configurado por server_init.sh el $(date '+%Y-%m-%d')
# Este fichero sobreescribe los valores de jail.conf sin modificarlo.

[DEFAULT]
bantime   = $BAN_TIME
findtime  = $FIND_TIME
maxretry  = $MAX_RETRY
banaction = iptables-multiport
backend   = systemd
ignoreip  = 127.0.0.1/8 ::1

# Jail estándar: banea tras $MAX_RETRY intentos fallidos en $FIND_TIME segundos
[sshd]
enabled  = true
port     = $SSH_PORT
logpath  = %(sshd_log)s
maxretry = $MAX_RETRY

# Jail anti-DDoS: umbral más alto pero ventana mucho más corta.
# Detecta ráfagas de autenticación aunque vengan de IPs distintas.
[sshd-ddos]
enabled  = true
port     = $SSH_PORT
filter   = sshd
logpath  = %(sshd_log)s
maxretry = 20
findtime = 120
bantime  = 7200
EOF

    systemctl enable --now fail2ban >> "$LOG_FILE" 2>&1
    systemctl restart fail2ban >> "$LOG_FILE" 2>&1
    ok "Fail2ban activo — bantime=${BAN_TIME}s | findtime=${FIND_TIME}s | maxretry=${MAX_RETRY}"
}

# =============================================================================
# MÓDULO 7 — Hardening del kernel y del sistema operativo
# =============================================================================
setup_hardening() {
    title "7/18  HARDENING ADICIONAL"

    section "Kernel — parámetros sysctl"
    if ask_yes_no "¿Aplicar hardening de kernel (sysctl)?" "y"; then
        cat > /etc/sysctl.d/99-hardening.conf <<'EOF'
# /etc/sysctl.d/99-hardening.conf — configurado por server_init.sh
# Los ficheros en sysctl.d/ se cargan en orden alfabético; el 99- garantiza
# que este tiene la última palabra sobre otros ficheros del sistema.

# SYN cookies: protección básica contra SYN flood sin necesidad de firewall
net.ipv4.tcp_syncookies = 1

# Reverse Path Filtering: descarta paquetes cuya IP de origen no es alcanzable
# por la interfaz por la que llegaron (evita spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignorar ICMP broadcast para evitar ataques Smurf
net.ipv4.icmp_echo_ignore_broadcasts = 1

# No aceptar paquetes con source routing; nadie legítimo usa esto
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# No reenviar ICMP redirects ni aceptarlos
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Loguear paquetes con IPs imposibles (martians): útil para detectar spoofing
net.ipv4.conf.all.log_martians = 1

# ASLR al máximo: randomiza la dirección base del stack, heap y librerías
kernel.randomize_va_space = 2

# Impide que usuarios sin privilegios lean el ring buffer del kernel
kernel.dmesg_restrict = 1

# Oculta las direcciones del kernel en /proc para usuarios no root
kernel.kptr_restrict = 2

# Protege contra ataques de hardlinks/symlinks en directorios con sticky bit
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
        sysctl -p /etc/sysctl.d/99-hardening.conf >> "$LOG_FILE" 2>&1
        ok "Parámetros de kernel aplicados."
    fi

    section "Límites de recursos"
    if ask_yes_no "¿Aplicar límites de recursos del sistema (limits.conf)?"; then
        cat >> /etc/security/limits.conf <<'EOF'
# Límites añadidos por server_init.sh
# 65535 descriptores de fichero es el mínimo razonable para servicios web/DB
* soft nofile 65535
* hard nofile 65535
* soft nproc  65535
* hard nproc  65535
root soft nofile 65535
root hard nofile 65535
EOF
        ok "Límites de recursos configurados."
    fi

    section "Servicios innecesarios"
    if ask_yes_no "¿Deshabilitar servicios innecesarios? (avahi, cups, bluetooth)"; then
        for svc in avahi-daemon cups bluetooth rpcbind; do
            systemctl disable --now "$svc" >> "$LOG_FILE" 2>&1 || true
        done
        ok "Servicios innecesarios deshabilitados."
    fi

    section "Acceso a comandos sensibles"
    if ask_yes_no "¿Restringir permisos de comandos sensibles?"; then
        # Quitamos el bit de ejecución para 'others' en at y crontab;
        # solo root y el grupo correspondiente podrán usarlos
        chmod o-x /usr/bin/at        2>/dev/null || true
        chmod o-x /usr/bin/crontab   2>/dev/null || true
        chmod 700 /bin/su             2>/dev/null || true
        ok "Permisos restrictivos aplicados."
    fi

    section "Auditoría con auditd"
    if ask_yes_no "¿Instalar y activar auditd?"; then
        case "$DISTRO" in
            debian|ubuntu) $PKG_INSTALL auditd audispd-plugins >> "$LOG_FILE" 2>&1 ;;
            *)             $PKG_INSTALL audit >> "$LOG_FILE" 2>&1 ;;
        esac
        systemctl enable --now auditd >> "$LOG_FILE" 2>&1
        ok "auditd activo."
    fi

    section "Deshabilitar IPv6"
    if ask_yes_no "¿Deshabilitar IPv6?"; then
        # Añadimos al mismo fichero de sysctl para que quede todo junto
        cat >> /etc/sysctl.d/99-hardening.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
        sysctl -p /etc/sysctl.d/99-hardening.conf >> "$LOG_FILE" 2>&1
        ok "IPv6 deshabilitado."
    fi
}

# =============================================================================
# MÓDULO 8 — Sincronización de tiempo con Chrony
# chrony es más preciso que ntpd y arranca más rápido tras un reinicio.
# En sistemas con systemd, timedatectl set-ntp true delega en chronyd.
# =============================================================================
setup_ntp() {
    title "8/18  SINCRONIZACIÓN DE TIEMPO (NTP/Chrony)"

    if ! ask_yes_no "¿Configurar sincronización de tiempo con chrony?" "y"; then
        info "NTP omitido."; return
    fi

    section "Estado actual"
    if command -v timedatectl &>/dev/null; then
        info "Estado actual:"
        timedatectl status 2>/dev/null | grep -E "Local time|NTP|synchronized" || true
    fi

    case "$DISTRO" in
        debian|ubuntu) $PKG_INSTALL chrony >> "$LOG_FILE" 2>&1 ;;
        almalinux|rhel|centos|rocky) $PKG_INSTALL chrony >> "$LOG_FILE" 2>&1 ;;
    esac

    NTP_SERVER=$(ask_value "Servidor NTP principal" "pool.ntp.org")

    # La ruta del fichero de configuración varía según la distro
    CHRONY_CONF="/etc/chrony.conf"
    [[ ! -f "$CHRONY_CONF" ]] && CHRONY_CONF="/etc/chrony/chrony.conf"

    cp "$CHRONY_CONF" "${CHRONY_CONF}.bak.$(date +%Y%m%d)" 2>/dev/null || true

    # Si ya hay una línea pool o server, la reemplazamos; si no, la añadimos
    if grep -qE "^(pool|server) " "$CHRONY_CONF" 2>/dev/null; then
        sed -i "s/^pool .*/pool $NTP_SERVER iburst/" "$CHRONY_CONF"
        sed -i "/^server /d" "$CHRONY_CONF"
    else
        echo "pool $NTP_SERVER iburst" >> "$CHRONY_CONF"
    fi

    # Pools secundarios como redundancia
    grep -q "pool 0.pool.ntp.org" "$CHRONY_CONF" 2>/dev/null || \
        cat >> "$CHRONY_CONF" <<'EOF'
pool 0.pool.ntp.org iburst
pool 1.pool.ntp.org iburst
pool 2.pool.ntp.org iburst
EOF

    # El servicio se llama chronyd en RHEL y chrony en Debian
    systemctl enable --now chronyd >> "$LOG_FILE" 2>&1 || \
    systemctl enable --now chrony  >> "$LOG_FILE" 2>&1 || true

    systemctl restart chronyd 2>/dev/null || systemctl restart chrony 2>/dev/null || true

    timedatectl set-ntp true 2>/dev/null || true
    ok "Chrony configurado. Servidor: ${NTP_SERVER}"
}

# =============================================================================
# MÓDULO 9 — Política de contraseñas con PAM
# pam_pwquality: complejidad mínima
# pam_faillock: bloqueo de cuenta tras N intentos fallidos (local, no SSH)
# chage/login.defs: expiración periódica de contraseñas
# =============================================================================
setup_pam() {
    title "9/18  PAM — POLÍTICA DE CONTRASEÑAS"

    if ! ask_yes_no "¿Configurar política de contraseñas con PAM?" "y"; then
        info "PAM omitido."; return
    fi

    section "Complejidad de contraseñas (pam_pwquality)"
    if ask_yes_no "¿Aplicar requisitos de complejidad de contraseñas?" "y"; then
        case "$DISTRO" in
            debian|ubuntu) $PKG_INSTALL libpam-pwquality >> "$LOG_FILE" 2>&1 ;;
            almalinux|rhel|centos|rocky) $PKG_INSTALL libpwquality >> "$LOG_FILE" 2>&1 ;;
        esac

        MIN_LEN=$(ask_value "Longitud mínima de contraseña" "12")
        MIN_UPPER=$(ask_value "Mínimo de mayúsculas" "1")
        MIN_LOWER=$(ask_value "Mínimo de minúsculas" "1")
        MIN_DIGIT=$(ask_value "Mínimo de dígitos" "1")
        MIN_SPECIAL=$(ask_value "Mínimo de caracteres especiales" "1")

        PWQUALITY_CONF="/etc/security/pwquality.conf"
        cat > "$PWQUALITY_CONF" <<EOF
# /etc/security/pwquality.conf — configurado por server_init.sh el $(date '+%Y-%m-%d')
# Los valores negativos en *credit indican el mínimo obligatorio de ese tipo de carácter
minlen  = $MIN_LEN
ucredit = -$MIN_UPPER
lcredit = -$MIN_LOWER
dcredit = -$MIN_DIGIT
ocredit = -$MIN_SPECIAL
maxrepeat = 3        # no más de 3 caracteres iguales consecutivos
gecoscheck = 1       # rechaza contraseñas que contengan el nombre del usuario
EOF
        ok "Complejidad de contraseñas configurada (min ${MIN_LEN} chars)."
    fi

    section "Bloqueo de cuenta por intentos fallidos (pam_faillock)"
    if ask_yes_no "¿Activar bloqueo de cuenta por intentos fallidos?" "y"; then
        FAIL_DENY=$(ask_value "Intentos antes de bloquear" "5")
        FAIL_UNLOCK=$(ask_value "Tiempo de bloqueo en segundos" "900")

        FAILLOCK_CONF="/etc/security/faillock.conf"
        if [[ -f "$FAILLOCK_CONF" ]]; then
            cp "$FAILLOCK_CONF" "${FAILLOCK_CONF}.bak.$(date +%Y%m%d)"
            # Descomentamos y actualizamos los valores si ya existen en el fichero
            sed -i "s/^# *deny *=.*/deny = $FAIL_DENY/" "$FAILLOCK_CONF" 2>/dev/null || true
            sed -i "s/^# *unlock_time *=.*/unlock_time = $FAIL_UNLOCK/" "$FAILLOCK_CONF" 2>/dev/null || true
            grep -q "^deny" "$FAILLOCK_CONF" || echo "deny = $FAIL_DENY" >> "$FAILLOCK_CONF"
            grep -q "^unlock_time" "$FAILLOCK_CONF" || echo "unlock_time = $FAIL_UNLOCK" >> "$FAILLOCK_CONF"
        else
            mkdir -p /etc/security
            cat > "$FAILLOCK_CONF" <<EOF
deny = $FAIL_DENY
unlock_time = $FAIL_UNLOCK
silent
audit
EOF
        fi
        ok "Bloqueo de cuenta: ${FAIL_DENY} intentos → bloqueo ${FAIL_UNLOCK}s."
    fi

    section "Expiración de contraseñas (chage)"
    if ask_yes_no "¿Configurar política de expiración de contraseñas?"; then
        MAX_DAYS=$(ask_value "Días máximos entre cambios de contraseña" "90")
        MIN_DAYS=$(ask_value "Días mínimos entre cambios" "1")
        WARN_DAYS=$(ask_value "Días de aviso antes de expiración" "14")

        # Aplicamos a usuarios existentes con UID >= 1000 (excluimos cuentas de sistema)
        while IFS=: read -r uname _ uid _; do
            if (( uid >= 1000 )); then
                chage -M "$MAX_DAYS" -m "$MIN_DAYS" -W "$WARN_DAYS" "$uname" 2>/dev/null || true
                ok "  Expiración configurada para: $uname"
            fi
        done < /etc/passwd

        # login.defs afecta a los usuarios que se creen a partir de ahora
        LODEF="/etc/login.defs"
        sed -i "s/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t$MAX_DAYS/" "$LODEF" 2>/dev/null || true
        sed -i "s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t$MIN_DAYS/" "$LODEF" 2>/dev/null || true
        sed -i "s/^PASS_WARN_AGE.*/PASS_WARN_AGE\t$WARN_DAYS/" "$LODEF" 2>/dev/null || true
        ok "Política de expiración: max=${MAX_DAYS}d / min=${MIN_DAYS}d / aviso=${WARN_DAYS}d."
    fi
}

# =============================================================================
# MÓDULO 10 — Control de acceso obligatorio (MAC)
# AppArmor en Debian/Ubuntu, SELinux en AlmaLinux/RHEL.
# Ambos funcionan como capa adicional sobre los permisos Unix clásicos.
# =============================================================================
setup_mac() {
    title "10/18  CONTROL DE ACCESO OBLIGATORIO (AppArmor / SELinux)"

    if ! ask_yes_no "¿Verificar/configurar MAC (AppArmor o SELinux)?" "y"; then
        info "MAC omitido."; return
    fi

    case "$DISTRO" in
        debian|ubuntu)
            section "AppArmor"
            $PKG_INSTALL apparmor apparmor-utils apparmor-profiles >> "$LOG_FILE" 2>&1
            if systemctl is-enabled apparmor &>/dev/null; then
                ok "AppArmor ya está habilitado."
            else
                systemctl enable --now apparmor >> "$LOG_FILE" 2>&1
                ok "AppArmor habilitado."
            fi
            info "Estado de perfiles AppArmor:"
            aa-status 2>/dev/null | head -20 || apparmor_status 2>/dev/null | head -20 || true

            if ask_yes_no "¿Poner todos los perfiles en modo enforce?"; then
                aa-enforce /etc/apparmor.d/* >> "$LOG_FILE" 2>&1 || true
                ok "Perfiles AppArmor en modo enforce."
            fi
            ;;
        almalinux|rhel|centos|rocky)
            section "SELinux"
            SELINUX_STATUS=$(getenforce 2>/dev/null || echo "desconocido")
            info "Estado actual de SELinux: ${SELINUX_STATUS}"

            if [[ "${SELINUX_STATUS,,}" == "enforcing" ]]; then
                ok "SELinux ya está en modo Enforcing."
            elif [[ "${SELINUX_STATUS,,}" == "permissive" ]]; then
                warn "SELinux está en modo Permissive (solo registra, no bloquea)."
                if ask_yes_no "¿Cambiar SELinux a modo Enforcing?" "y"; then
                    setenforce 1 2>/dev/null || true
                    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config 2>/dev/null || true
                    ok "SELinux → Enforcing (cambio permanente en /etc/selinux/config)."
                fi
            else
                warn "SELinux está DESHABILITADO."
                if ask_yes_no "¿Habilitar SELinux en modo Enforcing? (requiere reinicio)" "y"; then
                    $PKG_INSTALL selinux-policy selinux-policy-targeted >> "$LOG_FILE" 2>&1 || true
                    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config 2>/dev/null || true
                    warn "SELinux se activará tras el próximo reinicio."
                fi
            fi
            ;;
    esac
}

# =============================================================================
# MÓDULO 11 — Blacklist de módulos del kernel
# Evitamos cargar módulos que no usamos. "install <mod> /bin/true" hace que
# cualquier intento de cargar el módulo (incluso por dependencia) ejecute
# /bin/true en vez de cargarlo, sin generar error.
# =============================================================================
setup_kernel_blacklist() {
    title "11/18  BLACKLIST DE MÓDULOS DEL KERNEL"

    if ! ask_yes_no "¿Deshabilitar módulos del kernel innecesarios/peligrosos?" "y"; then
        info "Blacklist omitida."; return
    fi

    BLIST_FILE="/etc/modprobe.d/blacklist-hardening.conf"
    : > "$BLIST_FILE"

    declare -A MODULES=(
        ["usb-storage"]="Almacenamiento USB (riesgo de exfiltración de datos)"
        ["firewire-core"]="FireWire (acceso DMA directo a memoria)"
        ["cramfs"]="Sistema de archivos cramfs (raramente necesario)"
        ["freevxfs"]="Sistema de archivos freevxfs (raramente necesario)"
        ["jffs2"]="Sistema de archivos jffs2 (raramente necesario)"
        ["hfs"]="Sistema de archivos HFS (macOS, raramente necesario)"
        ["hfsplus"]="Sistema de archivos HFS+ (macOS, raramente necesario)"
        ["squashfs"]="Sistema de archivos squashfs (raramente necesario en servers)"
        ["udf"]="Sistema de archivos UDF (DVDs, raramente necesario)"
        ["dccp"]="Protocolo DCCP (raramente usado)"
        ["sctp"]="Protocolo SCTP (raramente usado)"
        ["rds"]="Protocolo RDS (raramente usado)"
        ["tipc"]="Protocolo TIPC (raramente usado)"
    )

    section "Selección de módulos a bloquear"
    echo ""
    cat >> "$BLIST_FILE" <<HEADER
# /etc/modprobe.d/blacklist-hardening.conf — configurado por server_init.sh el $(date '+%Y-%m-%d')
# "install <mod> /bin/true" previene la carga del módulo incluso por dependencia
HEADER

    for mod in "${!MODULES[@]}"; do
        desc="${MODULES[$mod]}"
        if ask_yes_no "  ¿Bloquear $mod? ($desc)" "y"; then
            echo "install $mod /bin/true" >> "$BLIST_FILE"
            echo "blacklist $mod"         >> "$BLIST_FILE"
            ok "  Bloqueado: $mod"
        fi
    done

    depmod -a >> "$LOG_FILE" 2>&1 || true
    ok "Blacklist guardada en $BLIST_FILE"
}

# =============================================================================
# MÓDULO 12 — Hardening de sudoers
# Usamos /etc/sudoers.d/ para no tocar el fichero principal.
# visudo -c valida la sintaxis antes de dejarlo en producción.
# =============================================================================
setup_sudoers() {
    title "12/18  HARDENING DE SUDOERS"

    if ! ask_yes_no "¿Aplicar hardening de sudoers?" "y"; then
        info "Sudoers omitido."; return
    fi

    SUDOERS_FILE="/etc/sudoers.d/hardening"

    section "Opciones de sudoers"

    SUDO_TIMEOUT=$(ask_value "Timeout de sudo (minutos, 0=siempre pide password)" "5")

    SUDO_LINES="# /etc/sudoers.d/hardening — configurado por server_init.sh el $(date '+%Y-%m-%d')\n"

    if ask_yes_no "¿Establecer timeout de ${SUDO_TIMEOUT} minutos para sudo?" "y"; then
        SUDO_LINES+="Defaults\ttimestamp_timeout=${SUDO_TIMEOUT}\n"
    fi

    if ask_yes_no "¿Registrar todos los comandos sudo en log?" "y"; then
        SUDO_LOG=$(ask_value "Ruta del log de sudo" "/var/log/sudo.log")
        SUDO_LINES+="Defaults\tlogfile=${SUDO_LOG}\n"
        SUDO_LINES+="Defaults\tlog_input,log_output\n"
        touch "$SUDO_LOG"
        chmod 640 "$SUDO_LOG"
    fi

    if ask_yes_no "¿Requerir TTY para sudo (bloquea ejecución no interactiva)?" "y"; then
        # requiretty impide que scripts o cron ejecuten sudo sin terminal
        SUDO_LINES+="Defaults\trequiretty\n"
    fi

    if ask_yes_no "¿Deshabilitar sudo sin contraseña (NOPASSWD) si está configurado?"; then
        SUDO_LINES+="Defaults\t!authenticate_timeout\n"
    fi

    echo -e "$SUDO_LINES" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"

    # Si visudo detecta un error de sintaxis, eliminamos el fichero para no romper sudo
    if visudo -c -f "$SUDOERS_FILE" >> "$LOG_FILE" 2>&1; then
        ok "Hardening de sudoers aplicado correctamente."
    else
        warn "Error de sintaxis en sudoers — fichero eliminado por seguridad."
        rm -f "$SUDOERS_FILE"
    fi
}

# =============================================================================
# MÓDULO 13 — Deshabilitar Ctrl+Alt+Del
# Por defecto, systemd-logind reacciona a esta combinación reiniciando el sistema.
# En un servidor esto es un riesgo si alguien tiene acceso físico o a la consola KVM.
# =============================================================================
setup_ctrl_alt_del() {
    title "13/18  DESHABILITAR CTRL+ALT+DEL"

    if ! ask_yes_no "¿Deshabilitar el atajo Ctrl+Alt+Del (reinicio físico)?" "y"; then
        info "Ctrl+Alt+Del omitido."; return
    fi

    systemctl mask ctrl-alt-del.target >> "$LOG_FILE" 2>&1
    systemctl daemon-reload >> "$LOG_FILE" 2>&1

    ok "Ctrl+Alt+Del deshabilitado (ctrl-alt-del.target enmascarado)."
}

# =============================================================================
# MÓDULO 14 — AIDE (Advanced Intrusion Detection Environment)
# Genera un hash de todos los ficheros del sistema y los compara periódicamente.
# Si algo cambia sin que tú lo hayas hecho, AIDE lo detecta.
# La inicialización tarda porque escanea todo el disco; la lanzamos en background.
# =============================================================================
setup_aide() {
    title "14/18  AIDE — INTEGRIDAD DE FICHEROS"

    if ! ask_yes_no "¿Instalar y configurar AIDE (File Integrity Monitoring)?" "y"; then
        info "AIDE omitido."; return
    fi

    case "$DISTRO" in
        debian|ubuntu) $PKG_INSTALL aide aide-common >> "$LOG_FILE" 2>&1 ;;
        almalinux|rhel|centos|rocky) $PKG_INSTALL aide >> "$LOG_FILE" 2>&1 ;;
    esac

    section "Inicialización de la base de datos AIDE"
    warn "La inicialización puede tardar varios minutos..."
    if ask_yes_no "¿Inicializar ahora la base de datos de AIDE?" "y"; then
        case "$DISTRO" in
            debian|ubuntu)
                aideinit >> "$LOG_FILE" 2>&1 &
                AIDE_PID=$!
                info "Inicializando AIDE en segundo plano (PID: $AIDE_PID)..."
                info "El proceso puede tardar 5-15 minutos. Puedes continuar."
                ;;
            almalinux|rhel|centos|rocky)
                aide --init >> "$LOG_FILE" 2>&1 &
                AIDE_PID=$!
                info "Inicializando AIDE en segundo plano (PID: $AIDE_PID)..."
                # En RHEL, la base de datos se genera como .new.gz; hay que renombrarla
                mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz 2>/dev/null || true
                ;;
        esac
    fi

    section "Comprobación diaria con cron"
    if ask_yes_no "¿Configurar comprobación diaria automática de AIDE?" "y"; then
        AIDE_HOUR=$(ask_value "Hora para la comprobación (0-23)" "3")
        AIDE_EMAIL=$(ask_value "Email para alertas de AIDE (vacío para omitir)" "")

        AIDE_CMD="aide --check"
        [[ -n "$AIDE_EMAIL" ]] && AIDE_CMD="aide --check | mail -s 'AIDE: Alerta de integridad' $AIDE_EMAIL"

        cat > /etc/cron.d/aide-check <<EOF
# Comprobación diaria de integridad de ficheros — server_init.sh
$AIDE_HOUR 0 * * * root $AIDE_CMD >> /var/log/aide-check.log 2>&1
EOF
        chmod 644 /etc/cron.d/aide-check
        ok "Comprobación diaria de AIDE a las ${AIDE_HOUR}:00."
    fi

    ok "AIDE configurado."
}

# =============================================================================
# MÓDULO 15 — rkhunter (Rootkit Hunter)
# Escanea el sistema buscando rootkits conocidos, backdoors y ficheros sospechosos.
# --propupd guarda el estado actual del sistema como baseline legítimo.
# En Debian también ofrecemos chkrootkit como segunda opinión independiente.
# =============================================================================
setup_rkhunter() {
    title "15/18  RKHUNTER — DETECCIÓN DE ROOTKITS"

    if ! ask_yes_no "¿Instalar y configurar rkhunter?" "y"; then
        info "rkhunter omitido."; return
    fi

    case "$DISTRO" in
        debian|ubuntu)
            $PKG_INSTALL rkhunter >> "$LOG_FILE" 2>&1
            if ask_yes_no "¿Instalar también chkrootkit (segunda opinión)?"; then
                $PKG_INSTALL chkrootkit >> "$LOG_FILE" 2>&1 && ok "chkrootkit instalado."
            fi
            ;;
        almalinux|rhel|centos|rocky)
            $PKG_INSTALL epel-release >> "$LOG_FILE" 2>&1 || true
            $PKG_INSTALL rkhunter >> "$LOG_FILE" 2>&1
            ;;
    esac

    section "Configuración de rkhunter"
    RKH_CONF="/etc/rkhunter.conf"
    [[ -f "$RKH_CONF" ]] && cp "$RKH_CONF" "${RKH_CONF}.bak.$(date +%Y%m%d)"

    info "Actualizando base de datos de rkhunter..."
    rkhunter --update >> "$LOG_FILE" 2>&1 || true

    # Guardamos el estado actual del sistema como baseline de referencia.
    # Cualquier cambio posterior en binarios o configuración del sistema
    # aparecerá como warning en el próximo escaneo.
    info "Guardando baseline del sistema..."
    rkhunter --propupd >> "$LOG_FILE" 2>&1 || true

    section "Escaneo semanal con cron"
    if ask_yes_no "¿Configurar escaneo semanal automático?" "y"; then
        RKH_DAY=$(ask_value "Día de la semana (0=Dom,1=Lun,...,6=Sab)" "0")
        RKH_HOUR=$(ask_value "Hora del escaneo (0-23)" "2")
        RKH_EMAIL=$(ask_value "Email para alertas de rkhunter (vacío para omitir)" "")

        RKH_CMD="rkhunter --check --skip-keypress --report-warnings-only"
        [[ -n "$RKH_EMAIL" ]] && \
            RKH_CMD="rkhunter --check --skip-keypress --report-warnings-only | mail -s 'rkhunter: Alerta en \$(hostname)' $RKH_EMAIL"

        cat > /etc/cron.d/rkhunter-check <<EOF
# Escaneo semanal de rootkits — server_init.sh
$RKH_HOUR 0 * * $RKH_DAY root $RKH_CMD >> /var/log/rkhunter-check.log 2>&1
EOF
        chmod 644 /etc/cron.d/rkhunter-check
        ok "Escaneo rkhunter programado: día=$RKH_DAY, hora=${RKH_HOUR}:00."
    fi

    ok "rkhunter instalado y configurado."
}

# =============================================================================
# MÓDULO 16 — Alertas por email vía msmtp
# msmtp es un MTA minimalista que hace relay hacia un servidor SMTP externo.
# Es mucho más sencillo de configurar que postfix para el caso de uso de "solo envío".
# =============================================================================
setup_email_alerts() {
    title "16/18  ALERTAS POR EMAIL"

    if ! ask_yes_no "¿Configurar envío de alertas por email?" "n"; then
        info "Alertas email omitidas."; return
    fi

    ALERT_EMAIL=$(ask_value "Email de destino para alertas" "admin@ejemplo.com")
    SMTP_HOST=$(ask_value "Servidor SMTP" "smtp.gmail.com")
    SMTP_PORT=$(ask_value "Puerto SMTP" "587")
    SMTP_USER=$(ask_value "Usuario SMTP" "$ALERT_EMAIL")
    SMTP_PASS=$(ask_secret "Contraseña SMTP")

    section "Instalando msmtp"
    case "$DISTRO" in
        debian|ubuntu) $PKG_INSTALL msmtp msmtp-mta mailutils >> "$LOG_FILE" 2>&1 ;;
        almalinux|rhel|centos|rocky) $PKG_INSTALL msmtp mailx >> "$LOG_FILE" 2>&1 ;;
    esac

    cat > /etc/msmtprc <<EOF
# /etc/msmtprc — configurado por server_init.sh el $(date '+%Y-%m-%d')
# Permisos 600 obligatorios; msmtp rechaza el fichero si son más permisivos

defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           $SMTP_HOST
port           $SMTP_PORT
from           $SMTP_USER
user           $SMTP_USER
password       $SMTP_PASS
EOF
    chmod 600 /etc/msmtprc

    # Registramos msmtp como sendmail del sistema para que 'mail' lo use
    if [[ -f /etc/msmtprc ]]; then
        echo "set sendmail=/usr/bin/msmtp" > /etc/mail.rc 2>/dev/null || true
    fi

    # Si fail2ban está configurado, le añadimos el destino de email
    if [[ -f /etc/fail2ban/jail.local ]]; then
        section "Integrando alertas con Fail2ban"
        if ask_yes_no "¿Enviar email cuando Fail2ban banee una IP?" "y"; then
            sed -i "/^\[DEFAULT\]/a destemail = $ALERT_EMAIL\naction = %(action_mwl)s" \
                /etc/fail2ban/jail.local 2>/dev/null || true
            systemctl restart fail2ban >> "$LOG_FILE" 2>&1 || true
            ok "Alertas de Fail2ban → $ALERT_EMAIL"
        fi
    fi

    # Script en profile.d: se ejecuta en cada login interactivo
    if ask_yes_no "¿Enviar email al iniciar sesión SSH (alerta de acceso)?" "y"; then
        cat > /etc/profile.d/ssh-login-alert.sh <<PROFILE
#!/bin/bash
if [[ -n "\$SSH_CLIENT" ]]; then
    IP=\$(echo "\$SSH_CLIENT" | awk '{print \$1}')
    echo "Acceso SSH en \$(hostname) por \$USER desde \$IP (\$(date))" | \
        mail -s "SSH Login: \$(hostname)" $ALERT_EMAIL
fi
PROFILE
        chmod +x /etc/profile.d/ssh-login-alert.sh
        ok "Alerta de login SSH configurada → $ALERT_EMAIL"
    fi

    ok "Alertas por email configuradas. SMTP: ${SMTP_HOST}:${SMTP_PORT}"
    warn "Verifica las credenciales SMTP enviando un email de prueba: echo 'Test' | mail -s 'Test' ${ALERT_EMAIL}"
}

# =============================================================================
# MÓDULO 17 — Swap
# Muchos VPS se despliegan sin swap. Con poca RAM, el OOM killer puede matar
# procesos críticos; un swapfile pequeño da margen de maniobra.
# swappiness=10 hace que el kernel use swap solo cuando realmente se queda sin RAM.
# =============================================================================
setup_swap() {
    title "17/18  SWAP"

    if ! ask_yes_no "¿Revisar/configurar la memoria swap?" "y"; then
        info "Swap omitido."; return
    fi

    section "Estado actual del swap"
    SWAP_INFO=$(swapon --show 2>/dev/null)
    if [[ -n "$SWAP_INFO" ]]; then
        echo "$SWAP_INFO"
        ok "Swap ya configurado."
        if ! ask_yes_no "¿Crear swap adicional de todas formas?"; then
            return
        fi
    else
        warn "No hay swap configurado en este sistema."
    fi

    # Sugerimos el tamaño de swap según la RAM disponible (regla práctica)
    RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    if (( RAM_MB <= 2048 )); then
        SWAP_SUGGESTED="2048"
    elif (( RAM_MB <= 8192 )); then
        SWAP_SUGGESTED="4096"
    else
        SWAP_SUGGESTED="8192"
    fi

    info "RAM detectada: ${RAM_MB} MB. Swap sugerida: ${SWAP_SUGGESTED} MB."

    if ask_yes_no "¿Crear swapfile?" "y"; then
        SWAP_FILE=$(ask_value "Ruta del swapfile" "/swapfile")
        SWAP_SIZE=$(ask_value "Tamaño en MB" "$SWAP_SUGGESTED")

        if [[ -f "$SWAP_FILE" ]]; then
            warn "Ya existe $SWAP_FILE. ¿Eliminarlo y recrearlo?"
            if ask_yes_no "¿Reemplazar swapfile existente?"; then
                swapoff "$SWAP_FILE" >> "$LOG_FILE" 2>&1 || true
                rm -f "$SWAP_FILE"
            else
                info "Manteniendo swapfile existente."; return
            fi
        fi

        info "Creando swapfile de ${SWAP_SIZE} MB en ${SWAP_FILE}..."
        dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE" status=progress >> "$LOG_FILE" 2>&1
        chmod 600 "$SWAP_FILE"
        mkswap "$SWAP_FILE" >> "$LOG_FILE" 2>&1
        swapon "$SWAP_FILE"

        # Añadimos a fstab para que se monte en cada arranque
        if ! grep -q "$SWAP_FILE" /etc/fstab; then
            echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
        fi

        SWAPPINESS=$(ask_value "Valor de swappiness (0-100, recomendado 10 para servidor)" "10")
        sysctl vm.swappiness="$SWAPPINESS" >> "$LOG_FILE" 2>&1
        grep -q "vm.swappiness" /etc/sysctl.d/99-hardening.conf 2>/dev/null || \
            echo "vm.swappiness = $SWAPPINESS" >> /etc/sysctl.d/99-hardening.conf

        ok "Swap creado: ${SWAP_FILE} (${SWAP_SIZE} MB, swappiness=${SWAPPINESS})."
    fi
}

# =============================================================================
# MÓDULO 18 — Lynis
# Auditoría de seguridad que analiza el sistema completo y da un hardening index.
# Útil como punto de partida y para auditorías periódicas después de cambios.
# El informe queda en /var/log/ con la fecha del día para poder comparar versiones.
# =============================================================================
setup_lynis() {
    title "18/18  LYNIS — AUDITORÍA DE SEGURIDAD"

    if ! ask_yes_no "¿Instalar y ejecutar auditoría Lynis?" "y"; then
        info "Lynis omitido."; return
    fi

    case "$DISTRO" in
        debian|ubuntu) $PKG_INSTALL lynis >> "$LOG_FILE" 2>&1 ;;
        almalinux|rhel|centos|rocky)
            $PKG_INSTALL epel-release >> "$LOG_FILE" 2>&1 || true
            $PKG_INSTALL lynis >> "$LOG_FILE" 2>&1
            ;;
    esac

    lynis update info >> "$LOG_FILE" 2>&1 || true

    LYNIS_REPORT="/var/log/lynis-report-$(date +%Y%m%d).log"

    section "Ejecutando auditoría Lynis"
    info "La auditoría puede tardar 1-3 minutos..."
    if ask_yes_no "¿Ejecutar auditoría completa ahora? (recomendado)" "y"; then
        lynis audit system --no-colors --quiet >> "$LYNIS_REPORT" 2>&1 || true

        # El hardening index es la puntuación global de 0 a 100
        HARDENING_INDEX=$(grep "Hardening index" "$LYNIS_REPORT" 2>/dev/null | tail -1 || echo "N/A")
        ok "Auditoría completada."
        info "Resultado: ${HARDENING_INDEX}"
        info "Informe guardado en: $LYNIS_REPORT"

        if ask_yes_no "¿Mostrar las principales sugerencias de Lynis?"; then
            echo ""
            grep -A2 "Suggestion\|Warning" "$LYNIS_REPORT" 2>/dev/null | head -40 || \
                info "No se encontraron sugerencias en el log."
        fi
    fi

    ok "Lynis instalado. Ejecuta 'lynis audit system' para futuras auditorías."
}

# =============================================================================
# Resumen final — muestra el estado del sistema tras la ejecución
# =============================================================================
show_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║         CONFIGURACIÓN COMPLETADA ✔                  ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}  Resumen:${NC}"
    echo -e "  • Distribución : ${CYAN}$DISTRO${NC}"
    echo -e "  • Hostname     : ${CYAN}$(hostname)${NC}"
    echo -e "  • Zona horaria : ${CYAN}$(timedatectl show -p Timezone --value 2>/dev/null || echo '-')${NC}"
    echo -e "  • Puerto SSH   : ${CYAN}${SSH_PORT:-sin cambios}${NC}"
    echo -e "  • Swap         : ${CYAN}$(swapon --show --noheadings 2>/dev/null | awk '{print $1" "$3}' || echo 'no configurado')${NC}"
    echo -e "  • SELinux/AA   : ${CYAN}$(getenforce 2>/dev/null || aa-status 2>/dev/null | head -1 || echo '-')${NC}"
    echo -e "  • Log completo : ${CYAN}$LOG_FILE${NC}"
    echo ""
    echo -e "${BOLD}${RED}  ¡IMPORTANTE!${NC}"
    echo -e "  1. Abre una NUEVA sesión SSH al puerto ${SSH_PORT:-22} antes de cerrar ésta."
    echo -e "  2. Verifica que puedes hacer 'sudo su' con el usuario admin."
    echo -e "  3. Guarda las credenciales en un gestor de contraseñas seguro."
    echo -e "  4. Revisa los logs de Lynis en /var/log/lynis-report-*.log"
    echo -e "  5. Verifica el estado de AIDE: aide --check"
    echo ""
    warn "Se recomienda reiniciar el servidor para aplicar todos los cambios."
    if ask_yes_no "¿Reiniciar ahora?"; then
        log "Reiniciando el sistema..."
        reboot
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    # Procesamos los flags primero porque --update y --version no requieren root
    parse_args "$@"

    clear
    echo -e "${BOLD}${BLUE}"
    cat <<'BANNER'
  ███████╗███████╗ ██████╗    ██╗███╗   ██╗██╗████████╗
  ██╔════╝██╔════╝██╔════╝    ██║████╗  ██║██║╚══██╔══╝
  ███████╗█████╗  ██║         ██║██╔██╗ ██║██║   ██║
  ╚════██║██╔══╝  ██║         ██║██║╚██╗██║██║   ██║
  ███████║███████╗╚██████╗    ██║██║ ╚████║██║   ██║
  ╚══════╝╚══════╝ ╚═════╝    ╚═╝╚═╝  ╚═══╝╚═╝   ╚═╝
BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}SERVER SECURITY INITIALIZATION${NC}  ${CYAN}v${VERSION}${NC}"
    echo -e "  ${CYAN}${REPO_URL}${NC}\n"

    require_root
    touch "$LOG_FILE"
    log "=== Inicio de server_init.sh v${VERSION} ==="
    detect_distro

    echo -e "\n${BOLD}  Este script configurará y asegurará tu servidor paso a paso.${NC}"
    echo -e "  Puedes omitir cualquier módulo respondiendo 'n'.\n"

    if ! ask_yes_no "¿Continuar con la configuración?" "y"; then
        info "Cancelado."; exit 0
    fi

    setup_system
    update_system
    manage_users
    setup_ssh
    setup_firewall
    setup_fail2ban
    setup_hardening
    setup_ntp
    setup_pam
    setup_mac
    setup_kernel_blacklist
    setup_sudoers
    setup_ctrl_alt_del
    setup_aide
    setup_rkhunter
    setup_email_alerts
    setup_swap
    setup_lynis
    show_summary

    log "=== server_init.sh completado ==="
}

main "$@"
