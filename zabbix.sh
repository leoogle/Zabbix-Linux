#!/bin/bash

#################################################################################
#                            ZABBIX AGENT INSTALLER                            #
#                         Instalador Automático de Agente Zabbix               #
#################################################################################
# Script para instalar y configurar automáticamente el agente Zabbix en        #
# sistemas Linux (Debian, Ubuntu, CentOS) y registrarlo via API               #
#                                                                               #
# Uso: ./zabbix.sh                                                             #
# Variables de entorno requeridas:                                             #
#   ZABBIX_SERVER_URL    - URL del servidor Zabbix (ej: http://zabbix.local)  #
#   ZABBIX_API_USER      - Usuario para API de Zabbix                         #
#   ZABBIX_API_PASSWORD  - Contraseña para API de Zabbix                      #
#   ZABBIX_HOST_GROUP     - Grupo de hosts (opcional, default: "Linux servers") #
#################################################################################

# Configuración global
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Variables de configuración (pueden ser sobrescritas por parámetros o variables de entorno)
ZABBIX_SERVER_URL="${ZABBIX_SERVER_URL:-}"
ZABBIX_API_USER="${ZABBIX_API_USER:-}"
ZABBIX_API_PASSWORD="${ZABBIX_API_PASSWORD:-}"
ZABBIX_HOST_GROUP="${ZABBIX_HOST_GROUP:-Linux servers}"
ZABBIX_SERVER_PORT="${ZABBIX_SERVER_PORT:-10051}"
ZABBIX_AGENT_PORT="${ZABBIX_AGENT_PORT:-10050}"

# Variables para parámetros de línea de comandos
PARAM_SERVER_URL=""
PARAM_API_USER=""
PARAM_API_PASSWORD=""
PARAM_HOST_GROUP=""
PARAM_SERVER_PORT=""
PARAM_AGENT_PORT=""

# Variables internas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/zabbix_install_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/tmp/zabbix_backup_$(date +%Y%m%d_%H%M%S)"
AUTH_TOKEN=""
HOST_IP=""
HOSTNAME=""
DISTRO=""
VERSION=""
ZABBIX_CONFIG_FILE=""
INSTALLED_PACKAGES=()

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#################################################################################
#                              FUNCIONES DE LOGGING                            #
#################################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$@"
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

#################################################################################
#                           FUNCIONES DE VALIDACIÓN                            #
#################################################################################

validate_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root o con sudo"
        exit 1
    fi
}

validate_requirements() {
    log_info "Validando requisitos del sistema..."
    
    # Validar comandos requeridos
    local required_commands=("curl" "wget" "systemctl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Comando requerido no encontrado: $cmd"
            exit 1
        fi
    done
    
    # Aplicar parámetros de línea de comandos sobre variables de entorno
    if [[ -n "$PARAM_SERVER_URL" ]]; then
        ZABBIX_SERVER_URL="$PARAM_SERVER_URL"
    fi
    if [[ -n "$PARAM_API_USER" ]]; then
        ZABBIX_API_USER="$PARAM_API_USER"
    fi
    if [[ -n "$PARAM_API_PASSWORD" ]]; then
        ZABBIX_API_PASSWORD="$PARAM_API_PASSWORD"
    fi
    if [[ -n "$PARAM_HOST_GROUP" ]]; then
        ZABBIX_HOST_GROUP="$PARAM_HOST_GROUP"
    fi
    if [[ -n "$PARAM_SERVER_PORT" ]]; then
        ZABBIX_SERVER_PORT="$PARAM_SERVER_PORT"
    fi
    if [[ -n "$PARAM_AGENT_PORT" ]]; then
        ZABBIX_AGENT_PORT="$PARAM_AGENT_PORT"
    fi
    
    # Validar variables de entorno requeridas
    if [[ -z "$ZABBIX_SERVER_URL" ]]; then
        log_error "URL del servidor Zabbix no definida"
        log_info "Use: --server-url <URL> o export ZABBIX_SERVER_URL='http://zabbix.example.com'"
        exit 1
    fi
    
    if [[ -z "$ZABBIX_API_USER" ]]; then
        log_error "Usuario de API de Zabbix no definido"
        log_info "Use: --api-user <USER> o export ZABBIX_API_USER='admin'"
        exit 1
    fi
    
    if [[ -z "$ZABBIX_API_PASSWORD" ]]; then
        log_error "Contraseña de API de Zabbix no definida"
        log_info "Use: --api-password <PASS> o export ZABBIX_API_PASSWORD='password'"
        exit 1
    fi
    
    # Validar formato de URL
    if [[ ! "$ZABBIX_SERVER_URL" =~ ^https?:// ]]; then
        log_error "ZABBIX_SERVER_URL debe comenzar con http:// o https://"
        exit 1
    fi
    
    log_success "Validación de requisitos completada"
}

validate_network() {
    log_info "Validando conectividad de red..."
    
    # Obtener IP del servidor desde URL
    local server_host=$(echo "$ZABBIX_SERVER_URL" | sed -e 's|^[^/]*//||' -e 's|[:/].*||')
    
    # Test de conectividad básica
    if ! ping -c 3 "$server_host" &>/dev/null; then
        log_warning "No se puede hacer ping a $server_host, pero continuando..."
    fi
    
    # Test de conectividad HTTP/HTTPS
    if ! curl -s --connect-timeout 10 --max-time 30 "$ZABBIX_SERVER_URL/api_jsonrpc.php" &>/dev/null; then
        log_error "No se puede conectar a la API de Zabbix en $ZABBIX_SERVER_URL"
        exit 1
    fi
    
    log_success "Conectividad de red validada"
}

get_system_info() {
    log_info "Obteniendo información del sistema..."
    
    # Obtener hostname
    HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    log_info "Hostname: $HOSTNAME"
    
    # Obtener IP principal
    HOST_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || \
              hostname -I 2>/dev/null | awk '{print $1}' || \
              ifconfig 2>/dev/null | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
    
    if [[ -z "$HOST_IP" ]]; then
        log_error "No se pudo determinar la IP del sistema"
        exit 1
    fi
    
    log_info "IP del sistema: $HOST_IP"
    
    # Crear directorio de backup
    mkdir -p "$BACKUP_DIR"
    log_info "Directorio de backup creado: $BACKUP_DIR"
}

#################################################################################
#                      FUNCIONES DE DETECCIÓN DE SISTEMA                       #
#################################################################################

detect_distribution() {
    log_info "Detectando distribución del sistema..."
    
    # Inicializar variables
    DISTRO=""
    VERSION=""
    
    # Detectar usando /etc/os-release (método preferido para sistemas modernos)
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        
        case "${ID,,}" in
            "ubuntu")
                DISTRO="ubuntu"
                VERSION="$VERSION_ID"
                ;;
            "debian")
                DISTRO="debian"
                VERSION="$VERSION_ID"
                ;;
            "centos")
                DISTRO="centos"
                VERSION="$VERSION_ID"
                ;;
            "rhel"|"redhat")
                DISTRO="rhel"
                VERSION="$VERSION_ID"
                ;;
            "rocky")
                DISTRO="rocky"
                VERSION="$VERSION_ID"
                ;;
            "almalinux")
                DISTRO="almalinux"
                VERSION="$VERSION_ID"
                ;;
        esac
        
        log_info "Detectado via os-release: $DISTRO $VERSION"
    fi
    
    # Método de respaldo para sistemas más antiguos
    if [[ -z "$DISTRO" ]]; then
        if [[ -f /etc/debian_version ]]; then
            if grep -q "Ubuntu" /etc/issue 2>/dev/null; then
                DISTRO="ubuntu"
                VERSION=$(grep -oP 'Ubuntu \K[0-9]+\.[0-9]+' /etc/issue | head -1)
            else
                DISTRO="debian"
                VERSION=$(cat /etc/debian_version | cut -d. -f1)
            fi
        elif [[ -f /etc/redhat-release ]]; then
            if grep -q "CentOS" /etc/redhat-release; then
                DISTRO="centos"
                VERSION=$(grep -oP 'CentOS .*? \K[0-9]+' /etc/redhat-release)
            elif grep -q "Red Hat" /etc/redhat-release; then
                DISTRO="rhel"
                VERSION=$(grep -oP 'Red Hat .*? \K[0-9]+' /etc/redhat-release)
            elif grep -q "Rocky" /etc/redhat-release; then
                DISTRO="rocky"
                VERSION=$(grep -oP 'Rocky .*? \K[0-9]+' /etc/redhat-release)
            elif grep -q "AlmaLinux" /etc/redhat-release; then
                DISTRO="almalinux"
                VERSION=$(grep -oP 'AlmaLinux .*? \K[0-9]+' /etc/redhat-release)
            fi
        fi
        
        log_info "Detectado via archivos legacy: $DISTRO $VERSION"
    fi
    
    # Validar que se detectó la distribución
    if [[ -z "$DISTRO" ]]; then
        log_error "No se pudo detectar la distribución del sistema"
        log_info "Distribuciones soportadas: Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux"
        exit 1
    fi
    
    # Validar versiones soportadas
    case "$DISTRO" in
        "ubuntu")
            if [[ ! "$VERSION" =~ ^(18|20|22|24)\. ]]; then
                log_warning "Versión de Ubuntu no completamente probada: $VERSION"
                log_info "Versiones recomendadas: 18.04, 20.04, 22.04, 24.04"
            fi
            ;;
        "debian")
            local major_version=$(echo "$VERSION" | cut -d. -f1)
            if [[ "$major_version" -lt 9 ]] || [[ "$major_version" -gt 12 ]]; then
                log_warning "Versión de Debian no completamente probada: $VERSION"
                log_info "Versiones recomendadas: 9, 10, 11, 12"
            fi
            ;;
        "centos"|"rhel"|"rocky"|"almalinux")
            local major_version=$(echo "$VERSION" | cut -d. -f1)
            if [[ "$major_version" -lt 7 ]] || [[ "$major_version" -gt 9 ]]; then
                log_warning "Versión no completamente probada: $VERSION"
                log_info "Versiones recomendadas: 7, 8, 9"
            fi
            ;;
    esac
    
    log_success "Distribución detectada: $DISTRO $VERSION"
    
    # Detectar arquitectura
    local arch=$(uname -m)
    log_info "Arquitectura: $arch"
    
    if [[ "$arch" != "x86_64" ]] && [[ "$arch" != "aarch64" ]]; then
        log_warning "Arquitectura no completamente soportada: $arch"
    fi
}

get_package_manager_info() {
    log_info "Configurando información del gestor de paquetes..."
    
    case "$DISTRO" in
        "ubuntu"|"debian")
            # Actualizar repositorios
            log_info "Actualizando repositorios APT..."
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq || {
                log_error "Error al actualizar repositorios APT"
                exit 1
            }
            
            # Instalar dependencias si no están presentes
            local required_packages=("curl" "wget" "gnupg" "lsb-release")
            for package in "${required_packages[@]}"; do
                if ! dpkg -l | grep -q "^ii.*$package "; then
                    log_info "Instalando dependencia: $package"
                    apt-get install -y "$package" || {
                        log_error "Error instalando $package"
                        exit 1
                    }
                fi
            done
            ;;
            
        "centos"|"rhel"|"rocky"|"almalinux")
            # Verificar si yum o dnf está disponible
            if command -v dnf &> /dev/null; then
                log_info "Usando DNF como gestor de paquetes"
                alias yum='dnf'
            elif command -v yum &> /dev/null; then
                log_info "Usando YUM como gestor de paquetes"
            else
                log_error "No se encontró gestor de paquetes (yum/dnf)"
                exit 1
            fi
            
            # Instalar dependencias EPEL si es necesario
            local major_version=$(echo "$VERSION" | cut -d. -f1)
            if [[ "$major_version" -ge 7 ]]; then
                if ! rpm -qa | grep -q epel-release; then
                    log_info "Instalando repositorio EPEL..."
                    yum install -y epel-release || {
                        log_warning "No se pudo instalar EPEL, continuando..."
                    }
                fi
            fi
            
            # Instalar dependencias básicas
            local required_packages=("curl" "wget")
            for package in "${required_packages[@]}"; do
                if ! rpm -qa | grep -q "$package"; then
                    log_info "Instalando dependencia: $package"
                    yum install -y "$package" || {
                        log_error "Error instalando $package"
                        exit 1
                    }
                fi
            done
            ;;
    esac
    
    log_success "Gestor de paquetes configurado correctamente"
}

#################################################################################
#                    FUNCIONES DE INSTALACIÓN POR DISTRIBUCIÓN                 #
#################################################################################

install_zabbix_repository() {
    log_info "Instalando repositorio oficial de Zabbix..."
    
    case "$DISTRO" in
        "ubuntu")
            local zabbix_repo_url="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/"
            case "$VERSION" in
                "18.04"|"18."*)
                    zabbix_repo_url+="zabbix-release_7.0-2+ubuntu18.04_all.deb"
                    ;;
                "20.04"|"20."*)
                    zabbix_repo_url+="zabbix-release_7.0-2+ubuntu20.04_all.deb"
                    ;;
                "22.04"|"22."*)
                    zabbix_repo_url+="zabbix-release_7.0-2+ubuntu22.04_all.deb"
                    ;;
                "24.04"|"24."*)
                    zabbix_repo_url+="zabbix-release_7.0-2+ubuntu24.04_all.deb"
                    ;;
                *)
                    log_warning "Versión de Ubuntu no reconocida, usando repositorio para 22.04"
                    zabbix_repo_url+="zabbix-release_7.0-2+ubuntu22.04_all.deb"
                    ;;
            esac
            
            log_info "Descargando e instalando repositorio: $zabbix_repo_url"
            wget -q "$zabbix_repo_url" -O /tmp/zabbix-release.deb || {
                log_error "Error descargando repositorio de Zabbix"
                exit 1
            }
            
            dpkg -i /tmp/zabbix-release.deb || {
                log_error "Error instalando repositorio de Zabbix"
                exit 1
            }
            
            apt-get update -qq
            rm -f /tmp/zabbix-release.deb
            ;;
            
        "debian")
            local major_version=$(echo "$VERSION" | cut -d. -f1)
            local zabbix_repo_url="https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/"
            
            case "$major_version" in
                "9")
                    zabbix_repo_url+="zabbix-release_7.0-2+debian9_all.deb"
                    ;;
                "10")
                    zabbix_repo_url+="zabbix-release_7.0-2+debian10_all.deb"
                    ;;
                "11")
                    zabbix_repo_url+="zabbix-release_7.0-2+debian11_all.deb"
                    ;;
                "12")
                    zabbix_repo_url+="zabbix-release_7.0-2+debian12_all.deb"
                    ;;
                *)
                    log_warning "Versión de Debian no reconocida, usando repositorio para Debian 11"
                    zabbix_repo_url+="zabbix-release_7.0-2+debian11_all.deb"
                    ;;
            esac
            
            log_info "Descargando e instalando repositorio: $zabbix_repo_url"
            wget -q "$zabbix_repo_url" -O /tmp/zabbix-release.deb || {
                log_error "Error descargando repositorio de Zabbix"
                exit 1
            }
            
            dpkg -i /tmp/zabbix-release.deb || {
                log_error "Error instalando repositorio de Zabbix"
                exit 1
            }
            
            apt-get update -qq
            rm -f /tmp/zabbix-release.deb
            ;;
            
        "centos"|"rhel"|"rocky"|"almalinux")
            local major_version=$(echo "$VERSION" | cut -d. -f1)
            local zabbix_repo_url="https://repo.zabbix.com/zabbix/7.0/rhel/${major_version}/x86_64/zabbix-release-7.0-2.el${major_version}.noarch.rpm"
            
            log_info "Instalando repositorio: $zabbix_repo_url"
            rpm -Uvh "$zabbix_repo_url" || {
                log_error "Error instalando repositorio de Zabbix"
                exit 1
            }
            
            # Limpiar cache de yum/dnf
            yum clean all 2>/dev/null || dnf clean all 2>/dev/null || true
            ;;
    esac
    
    log_success "Repositorio de Zabbix instalado correctamente"
}

install_zabbix_agent() {
    log_info "Instalando agente Zabbix..."
    
    case "$DISTRO" in
        "ubuntu"|"debian")
            # Backup de configuración existente si existe
            if [[ -f /etc/zabbix/zabbix_agentd.conf ]]; then
                log_info "Creando backup de configuración existente..."
                cp /etc/zabbix/zabbix_agentd.conf "$BACKUP_DIR/zabbix_agentd.conf.backup"
            fi
            
            # Instalar paquetes
            local packages=("zabbix-agent")
            log_info "Instalando paquetes: ${packages[*]}"
            
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y "${packages[@]}" || {
                log_error "Error instalando paquetes de Zabbix"
                exit 1
            }
            
            INSTALLED_PACKAGES+=("${packages[@]}")
            ZABBIX_CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
            ;;
            
        "centos"|"rhel"|"rocky"|"almalinux")
            # Backup de configuración existente si existe
            if [[ -f /etc/zabbix/zabbix_agentd.conf ]]; then
                log_info "Creando backup de configuración existente..."
                cp /etc/zabbix/zabbix_agentd.conf "$BACKUP_DIR/zabbix_agentd.conf.backup"
            fi
            
            # Instalar paquetes
            local packages=("zabbix-agent")
            log_info "Instalando paquetes: ${packages[*]}"
            
            yum install -y "${packages[@]}" || {
                log_error "Error instalando paquetes de Zabbix"
                exit 1
            }
            
            INSTALLED_PACKAGES+=("${packages[@]}")
            ZABBIX_CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
            ;;
    esac
    
    # Verificar que el archivo de configuración existe
    if [[ ! -f "$ZABBIX_CONFIG_FILE" ]]; then
        log_error "Archivo de configuración no encontrado: $ZABBIX_CONFIG_FILE"
        exit 1
    fi
    
    log_success "Agente Zabbix instalado correctamente"
}

check_existing_installation() {
    log_info "Verificando instalación existente de Zabbix..."
    
    local zabbix_installed=false
    local zabbix_running=false
    
    # Verificar si Zabbix está instalado
    case "$DISTRO" in
        "ubuntu"|"debian")
            if dpkg -l | grep -q "zabbix-agent"; then
                zabbix_installed=true
                log_info "Zabbix agent ya está instalado"
            fi
            ;;
        "centos"|"rhel"|"rocky"|"almalinux")
            if rpm -qa | grep -q "zabbix-agent"; then
                zabbix_installed=true
                log_info "Zabbix agent ya está instalado"
            fi
            ;;
    esac
    
    # Verificar si el servicio está corriendo
    if systemctl is-active --quiet zabbix-agent 2>/dev/null; then
        zabbix_running=true
        log_info "Servicio zabbix-agent está activo"
    fi
    
    # Si está instalado y corriendo, preguntar qué hacer
    if [[ "$zabbix_installed" == true ]]; then
        log_warning "Zabbix agent ya está instalado en el sistema"
        
        if [[ "${FORCE_REINSTALL:-false}" != "true" ]]; then
            log_info "Para forzar reinstalación, use: export FORCE_REINSTALL=true"
            log_info "Procediendo con reconfiguración del agente existente..."
            
            # Solo hacer backup y reconfigurar
            if [[ -f "$ZABBIX_CONFIG_FILE" ]]; then
                cp "$ZABBIX_CONFIG_FILE" "$BACKUP_DIR/zabbix_agentd.conf.backup"
            fi
            
            return 0
        else
            log_info "FORCE_REINSTALL=true, procediendo con reinstalación completa..."
            
            # Detener servicio si está corriendo
            if [[ "$zabbix_running" == true ]]; then
                systemctl stop zabbix-agent || true
            fi
            
            # Remover instalación existente
            case "$DISTRO" in
                "ubuntu"|"debian")
                    apt-get remove --purge -y zabbix-agent* || true
                    ;;
                "centos"|"rhel"|"rocky"|"almalinux")
                    yum remove -y zabbix-agent* || true
                    ;;
            esac
        fi
    fi
    
    log_success "Verificación de instalación existente completada"
}

#################################################################################
#                         FUNCIONES DE API ZABBIX                              #
#################################################################################

zabbix_api_call() {
    local method="$1"
    local params="$2"
    local auth_required="${3:-true}"
    
    local request_data='{
        "jsonrpc": "2.0",
        "method": "'$method'",
        "params": '$params',
        "id": 1'
    
    if [[ "$auth_required" == "true" ]] && [[ -n "$AUTH_TOKEN" ]]; then
        request_data+=',
        "auth": "'$AUTH_TOKEN'"'
    fi
    
    request_data+='}'
    
    log_debug "API Request: $request_data"
    
    local response=$(curl -s \
        -H "Content-Type: application/json-rpc" \
        -H "User-Agent: Zabbix-Installer/1.0" \
        --connect-timeout 30 \
        --max-time 60 \
        -d "$request_data" \
        "$ZABBIX_SERVER_URL/api_jsonrpc.php")
    
    if [[ -z "$response" ]]; then
        log_error "No se recibió respuesta de la API de Zabbix"
        return 1
    fi
    
    log_debug "API Response: $response"
    
    # Verificar si hay error en la respuesta
    if echo "$response" | grep -q '"error"'; then
        local error_message=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d':' -f2 | tr -d '"')
        log_error "Error en API de Zabbix: $error_message"
        return 1
    fi
    
    echo "$response"
    return 0
}

zabbix_authenticate() {
    log_info "Autenticando con la API de Zabbix..."
    
    local auth_params='{
        "user": "'$ZABBIX_API_USER'",
        "password": "'$ZABBIX_API_PASSWORD'"
    }'
    
    local response=$(zabbix_api_call "user.login" "$auth_params" "false")
    if [[ $? -ne 0 ]]; then
        log_error "Error en autenticación con Zabbix"
        exit 1
    fi
    
    AUTH_TOKEN=$(echo "$response" | grep -o '"result":"[^"]*"' | cut -d':' -f2 | tr -d '"')
    
    if [[ -z "$AUTH_TOKEN" ]]; then
        log_error "No se pudo obtener token de autenticación"
        exit 1
    fi
    
    log_success "Autenticación exitosa con Zabbix"
    log_debug "Token de autenticación obtenido"
}

check_host_exists() {
    log_info "Verificando si el host ya existe en Zabbix..."
    
    # Buscar por IP
    local search_params='{
        "output": ["hostid", "host", "name", "status"],
        "filter": {
            "ip": "'$HOST_IP'"
        }
    }'
    
    local response=$(zabbix_api_call "host.get" "$search_params")
    if [[ $? -ne 0 ]]; then
        log_error "Error consultando hosts existentes"
        return 1
    fi
    
    local host_count=$(echo "$response" | grep -o '"hostid"' | wc -l)
    
    if [[ $host_count -gt 0 ]]; then
        log_warning "Se encontró host existente con IP $HOST_IP"
        
        # Extraer información del host existente
        local existing_hostid=$(echo "$response" | grep -o '"hostid":"[^"]*"' | head -1 | cut -d':' -f2 | tr -d '"')
        local existing_hostname=$(echo "$response" | grep -o '"host":"[^"]*"' | head -1 | cut -d':' -f2 | tr -d '"')
        local existing_status=$(echo "$response" | grep -o '"status":"[^"]*"' | head -1 | cut -d':' -f2 | tr -d '"')
        
        log_info "Host existente - ID: $existing_hostid, Nombre: $existing_hostname, Estado: $existing_status"
        
        if [[ "${UPDATE_EXISTING_HOST:-false}" == "true" ]]; then
            log_info "UPDATE_EXISTING_HOST=true, actualizando host existente..."
            update_existing_host "$existing_hostid"
            return 0
        else
            log_info "Para actualizar host existente, use: export UPDATE_EXISTING_HOST=true"
            log_info "Host ya registrado en Zabbix, saltando registro"
            return 0
        fi
    fi
    
    log_info "No se encontró host existente con IP $HOST_IP"
    return 1
}

get_hostgroup_id() {
    log_info "Obteniendo ID del grupo de hosts: $ZABBIX_HOST_GROUP"
    
    local group_params='{
        "output": ["groupid", "name"],
        "filter": {
            "name": ["'$ZABBIX_HOST_GROUP'"]
        }
    }'
    
    local response=$(zabbix_api_call "hostgroup.get" "$group_params")
    if [[ $? -ne 0 ]]; then
        log_error "Error consultando grupos de hosts"
        return 1
    fi
    
    local group_id=$(echo "$response" | grep -o '"groupid":"[^"]*"' | head -1 | cut -d':' -f2 | tr -d '"')
    
    if [[ -z "$group_id" ]]; then
        log_warning "Grupo '$ZABBIX_HOST_GROUP' no encontrado, creando..."
        create_hostgroup
        return $?
    fi
    
    log_success "ID del grupo '$ZABBIX_HOST_GROUP': $group_id"
    echo "$group_id"
    return 0
}

create_hostgroup() {
    log_info "Creando grupo de hosts: $ZABBIX_HOST_GROUP"
    
    local create_params='{
        "name": "'$ZABBIX_HOST_GROUP'"
    }'
    
    local response=$(zabbix_api_call "hostgroup.create" "$create_params")
    if [[ $? -ne 0 ]]; then
        log_error "Error creando grupo de hosts"
        return 1
    fi
    
    local group_id=$(echo "$response" | grep -o '"groupids":\["[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$group_id" ]]; then
        log_error "No se pudo obtener ID del grupo creado"
        return 1
    fi
    
    log_success "Grupo creado exitosamente con ID: $group_id"
    echo "$group_id"
    return 0
}

register_host_zabbix() {
    log_info "Registrando host en Zabbix..."
    
    # Obtener ID del grupo de hosts
    local group_id=$(get_hostgroup_id)
    if [[ $? -ne 0 ]] || [[ -z "$group_id" ]]; then
        log_error "No se pudo obtener ID del grupo de hosts"
        return 1
    fi
    
    # Extraer servidor de la URL para configuración
    local server_host=$(echo "$ZABBIX_SERVER_URL" | sed -e 's|^[^/]*//||' -e 's|[:/].*||')
    
    local host_params='{
        "host": "'$HOSTNAME'",
        "name": "'$HOSTNAME'",
        "interfaces": [
            {
                "type": 1,
                "main": 1,
                "useip": 1,
                "ip": "'$HOST_IP'",
                "dns": "",
                "port": "'$ZABBIX_AGENT_PORT'"
            }
        ],
        "groups": [
            {
                "groupid": "'$group_id'"
            }
        ],
        "templates": [
            {
                "templateid": "10001"
            }
        ],
        "inventory_mode": 1,
        "inventory": {
            "os": "'$(uname -a)'",
            "os_full": "'$DISTRO $VERSION'",
            "hardware": "'$(uname -m)'",
            "software": "Zabbix Agent Auto-installed"
        }
    }'
    
    local response=$(zabbix_api_call "host.create" "$host_params")
    if [[ $? -ne 0 ]]; then
        log_error "Error registrando host en Zabbix"
        return 1
    fi
    
    local host_id=$(echo "$response" | grep -o '"hostids":\["[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$host_id" ]]; then
        log_error "No se pudo obtener ID del host creado"
        return 1
    fi
    
    log_success "Host registrado exitosamente en Zabbix con ID: $host_id"
    return 0
}

update_existing_host() {
    local host_id="$1"
    log_info "Actualizando host existente con ID: $host_id"
    
    local update_params='{
        "hostid": "'$host_id'",
        "host": "'$HOSTNAME'",
        "name": "'$HOSTNAME'",
        "interfaces": [
            {
                "type": 1,
                "main": 1,
                "useip": 1,
                "ip": "'$HOST_IP'",
                "dns": "",
                "port": "'$ZABBIX_AGENT_PORT'"
            }
        ],
        "inventory": {
            "os": "'$(uname -a)'",
            "os_full": "'$DISTRO $VERSION'",
            "hardware": "'$(uname -m)'",
            "software": "Zabbix Agent Auto-updated"
        }
    }'
    
    local response=$(zabbix_api_call "host.update" "$update_params")
    if [[ $? -ne 0 ]]; then
        log_error "Error actualizando host en Zabbix"
        return 1
    fi
    
    log_success "Host actualizado exitosamente en Zabbix"
    return 0
}

validate_zabbix_connectivity() {
    log_info "Validando conectividad completa con Zabbix..."
    
    # Test de conectividad básica a API
    local api_test=$(curl -s --connect-timeout 10 --max-time 30 \
        -H "Content-Type: application/json-rpc" \
        -d '{"jsonrpc":"2.0","method":"apiinfo.version","id":1}' \
        "$ZABBIX_SERVER_URL/api_jsonrpc.php")
    
    if [[ -z "$api_test" ]]; then
        log_error "No se puede conectar a la API de Zabbix"
        return 1
    fi
    
    local api_version=$(echo "$api_test" | grep -o '"result":"[^"]*"' | cut -d':' -f2 | tr -d '"')
    if [[ -n "$api_version" ]]; then
        log_success "API de Zabbix disponible, versión: $api_version"
    else
        log_error "Respuesta inválida de la API de Zabbix"
        return 1
    fi
    
    # Test de conectividad del servidor Zabbix (puerto del servidor)
    local server_host=$(echo "$ZABBIX_SERVER_URL" | sed -e 's|^[^/]*//||' -e 's|[:/].*||')
    if command -v nc &> /dev/null; then
        if nc -z "$server_host" "$ZABBIX_SERVER_PORT" 2>/dev/null; then
            log_success "Puerto del servidor Zabbix ($ZABBIX_SERVER_PORT) accesible"
        else
            log_warning "Puerto del servidor Zabbix ($ZABBIX_SERVER_PORT) no accesible"
            log_info "Esto puede ser normal si el servidor tiene firewall configurado"
        fi
    fi
    
    return 0
}

#################################################################################
#                       FUNCIONES DE CONFIGURACIÓN                             #
#################################################################################

configure_zabbix_agent() {
    log_info "Configurando agente Zabbix..."
    
    if [[ ! -f "$ZABBIX_CONFIG_FILE" ]]; then
        log_error "Archivo de configuración no encontrado: $ZABBIX_CONFIG_FILE"
        return 1
    fi
    
    # Crear backup del archivo original
    cp "$ZABBIX_CONFIG_FILE" "$BACKUP_DIR/zabbix_agentd.conf.original"
    
    # Extraer servidor de la URL
    local server_host=$(echo "$ZABBIX_SERVER_URL" | sed -e 's|^[^/]*//||' -e 's|[:/].*||')
    
    log_info "Configurando servidor Zabbix: $server_host"
    log_info "Configurando hostname: $HOSTNAME"
    
    # Configuraciones principales
    local config_changes=(
        "s/^Server=.*/Server=$server_host/"
        "s/^ServerActive=.*/ServerActive=$server_host:$ZABBIX_SERVER_PORT/"
        "s/^Hostname=.*/Hostname=$HOSTNAME/"
        "s/^# ListenPort=.*/ListenPort=$ZABBIX_AGENT_PORT/"
        "s/^ListenPort=.*/ListenPort=$ZABBIX_AGENT_PORT/"
        "s/^# ListenIP=.*/ListenIP=0.0.0.0/"
        "s/^ListenIP=.*/ListenIP=0.0.0.0/"
        "s/^# StartAgents=.*/StartAgents=3/"
        "s/^StartAgents=.*/StartAgents=3/"
        "s/^# RefreshActiveChecks=.*/RefreshActiveChecks=60/"
        "s/^RefreshActiveChecks=.*/RefreshActiveChecks=60/"
        "s/^# BufferSend=.*/BufferSend=5/"
        "s/^BufferSend=.*/BufferSend=5/"
        "s/^# BufferSize=.*/BufferSize=100/"
        "s/^BufferSize=.*/BufferSize=100/"
        "s/^# Timeout=.*/Timeout=3/"
        "s/^Timeout=.*/Timeout=3/"
        "s/^# EnableRemoteCommands=.*/EnableRemoteCommands=0/"
        "s/^EnableRemoteCommands=.*/EnableRemoteCommands=0/"
        "s/^# LogRemoteCommands=.*/LogRemoteCommands=0/"
        "s/^LogRemoteCommands=.*/LogRemoteCommands=0/"
    )
    
    # Aplicar cambios de configuración
    for change in "${config_changes[@]}"; do
        sed -i "$change" "$ZABBIX_CONFIG_FILE"
    done
    
    # Agregar configuraciones adicionales si no existen
    if ! grep -q "^HostMetadata=" "$ZABBIX_CONFIG_FILE"; then
        echo "" >> "$ZABBIX_CONFIG_FILE"
        echo "# Auto-configured by Zabbix installer" >> "$ZABBIX_CONFIG_FILE"
        echo "HostMetadata=Linux $DISTRO $VERSION $(uname -m)" >> "$ZABBIX_CONFIG_FILE"
    fi
    
    # Configurar logs
    if ! grep -q "^LogFile=" "$ZABBIX_CONFIG_FILE"; then
        echo "LogFile=/var/log/zabbix/zabbix_agentd.log" >> "$ZABBIX_CONFIG_FILE"
    fi
    
    if ! grep -q "^LogFileSize=" "$ZABBIX_CONFIG_FILE"; then
        echo "LogFileSize=10" >> "$ZABBIX_CONFIG_FILE"
    fi
    
    # Crear directorio de logs si no existe
    mkdir -p /var/log/zabbix
    chown zabbix:zabbix /var/log/zabbix 2>/dev/null || true
    
    # Validar configuración
    if ! zabbix_agentd -t -c "$ZABBIX_CONFIG_FILE" &>/dev/null; then
        log_error "Configuración de Zabbix inválida"
        log_info "Restaurando configuración original..."
        cp "$BACKUP_DIR/zabbix_agentd.conf.original" "$ZABBIX_CONFIG_FILE"
        return 1
    fi
    
    log_success "Agente Zabbix configurado correctamente"
    return 0
}

setup_zabbix_service() {
    log_info "Configurando servicio de Zabbix..."
    
    # Habilitar y iniciar el servicio
    systemctl enable zabbix-agent || {
        log_error "Error habilitando servicio zabbix-agent"
        return 1
    }
    
    # Detener el servicio si está corriendo para aplicar nueva configuración
    if systemctl is-active --quiet zabbix-agent; then
        log_info "Deteniendo servicio existente..."
        systemctl stop zabbix-agent || {
            log_error "Error deteniendo servicio zabbix-agent"
            return 1
        }
    fi
    
    # Iniciar el servicio
    log_info "Iniciando servicio zabbix-agent..."
    systemctl start zabbix-agent || {
        log_error "Error iniciando servicio zabbix-agent"
        log_info "Verificando logs..."
        journalctl -u zabbix-agent --no-pager -l | tail -10
        return 1
    }
    
    # Verificar que el servicio está corriendo
    sleep 3
    if ! systemctl is-active --quiet zabbix-agent; then
        log_error "Servicio zabbix-agent no está corriendo"
        log_info "Estado del servicio:"
        systemctl status zabbix-agent --no-pager -l
        return 1
    fi
    
    log_success "Servicio zabbix-agent configurado y corriendo"
    return 0
}

configure_firewall() {
    log_info "Configurando firewall si es necesario..."
    
    # Verificar si hay firewall activo
    local firewall_active=false
    
    # Verificar UFW (Ubuntu/Debian)
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        log_info "UFW detectado y activo, configurando regla..."
        ufw allow "$ZABBIX_AGENT_PORT/tcp" comment "Zabbix Agent" || {
            log_warning "Error configurando UFW, puede necesitar configuración manual"
        }
        firewall_active=true
    fi
    
    # Verificar firewalld (CentOS/RHEL)
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        log_info "Firewalld detectado y activo, configurando regla..."
        firewall-cmd --permanent --add-port="$ZABBIX_AGENT_PORT/tcp" || {
            log_warning "Error configurando firewalld, puede necesitar configuración manual"
        }
        firewall-cmd --reload || true
        firewall_active=true
    fi
    
    # Verificar iptables
    if command -v iptables &> /dev/null && iptables -L | grep -q "Chain INPUT"; then
        local iptables_rules=$(iptables -L INPUT -n | grep -c "$ZABBIX_AGENT_PORT")
        if [[ $iptables_rules -eq 0 ]]; then
            log_info "Iptables detectado, puede necesitar configuración manual"
            log_info "Regla sugerida: iptables -A INPUT -p tcp --dport $ZABBIX_AGENT_PORT -j ACCEPT"
            firewall_active=true
        fi
    fi
    
    if [[ "$firewall_active" == false ]]; then
        log_info "No se detectó firewall activo"
    fi
    
    return 0
}

verify_agent_connectivity() {
    log_info "Verificando conectividad del agente..."
    
    # Test local del agente
    if command -v zabbix_get &> /dev/null; then
        local test_result=$(zabbix_get -s localhost -p "$ZABBIX_AGENT_PORT" -k "agent.ping" 2>/dev/null)
        if [[ "$test_result" == "1" ]]; then
            log_success "Agente responde correctamente en puerto local"
        else
            log_warning "Agente no responde en puerto local"
        fi
    fi
    
    # Test de conectividad de red
    if command -v nc &> /dev/null; then
        if nc -z localhost "$ZABBIX_AGENT_PORT" 2>/dev/null; then
            log_success "Puerto $ZABBIX_AGENT_PORT está abierto localmente"
        else
            log_error "Puerto $ZABBIX_AGENT_PORT no está abierto"
            return 1
        fi
    fi
    
    # Verificar logs del agente
    if [[ -f /var/log/zabbix/zabbix_agentd.log ]]; then
        local error_count=$(grep -c "ERROR" /var/log/zabbix/zabbix_agentd.log 2>/dev/null || echo "0")
        if [[ $error_count -gt 0 ]]; then
            log_warning "Se encontraron $error_count errores en los logs del agente"
            log_info "Últimos errores:"
            grep "ERROR" /var/log/zabbix/zabbix_agentd.log | tail -3
        else
            log_success "No se encontraron errores en los logs del agente"
        fi
    fi
    
    return 0
}

#################################################################################
#                        FUNCIONES DE MANEJO DE ERRORES                        #
#################################################################################

cleanup() {
    local exit_code=$?
    log_info "Ejecutando limpieza..."
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script terminado con errores (código: $exit_code)"
        rollback_installation
    fi
    
    log_info "Log guardado en: $LOG_FILE"
    exit $exit_code
}

rollback_installation() {
    log_warning "Iniciando rollback de la instalación..."
    
    # Restaurar archivos de configuración
    if [[ -d "$BACKUP_DIR" ]] && [[ $(ls -A "$BACKUP_DIR" 2>/dev/null) ]]; then
        log_info "Restaurando archivos de configuración..."
        cp -r "$BACKUP_DIR"/* / 2>/dev/null || true
    fi
    
    # Desinstalar paquetes si se instalaron en esta sesión
    if [[ ${#INSTALLED_PACKAGES[@]} -gt 0 ]]; then
        log_info "Removiendo paquetes instalados: ${INSTALLED_PACKAGES[*]}"
        case "$DISTRO" in
            "debian"|"ubuntu")
                apt-get remove -y "${INSTALLED_PACKAGES[@]}" 2>/dev/null || true
                apt-get autoremove -y 2>/dev/null || true
                ;;
            "centos"|"rhel"|"rocky"|"almalinux")
                yum remove -y "${INSTALLED_PACKAGES[@]}" 2>/dev/null || true
                ;;
        esac
    fi
    
    log_warning "Rollback completado"
}

# Trap para ejecutar cleanup al salir
trap cleanup EXIT ERR

#################################################################################
#                           FUNCIONES AUXILIARES                               #
#################################################################################

show_help() {
    cat << EOF
Instalador Automático de Agente Zabbix
======================================

Este script instala y configura automáticamente el agente Zabbix en sistemas
Linux y lo registra en un servidor Zabbix usando la API.

Uso:
    ./zabbix.sh [opciones]
    
    # Usando parámetros (RECOMENDADO para seguridad)
    ./zabbix.sh --server-url <URL> --api-user <USER> --api-password <PASS>
    
    # Descarga y ejecución en una línea (curl)
    curl -s https://raw.githubusercontent.com/user/repo/main/zabbix.sh | \\
        sudo bash -s -- --server-url "http://zabbix.local" \\
                        --api-user "admin" \\
                        --api-password "password"

Parámetros requeridos:
    -s, --server-url <URL>        URL del servidor Zabbix (ej: http://zabbix.local)
    -u, --api-user <USER>         Usuario para API de Zabbix
    -p, --api-password <PASS>     Contraseña para API de Zabbix

Parámetros opcionales:
    -g, --host-group <GROUP>      Grupo de hosts (default: "Linux servers")
    --server-port <PORT>          Puerto del servidor (default: 10051)
    --agent-port <PORT>           Puerto del agente (default: 10050)
    --force-reinstall             Forzar reinstalación
    --update-existing             Actualizar host existente
    --debug                       Habilitar modo debug

Variables de entorno alternativas (MENOS SEGURO):
    ZABBIX_SERVER_URL     - URL del servidor Zabbix
    ZABBIX_API_USER       - Usuario para API de Zabbix
    ZABBIX_API_PASSWORD   - Contraseña para API de Zabbix
    ZABBIX_HOST_GROUP     - Grupo de hosts
    FORCE_REINSTALL       - Forzar reinstalación (true/false)
    UPDATE_EXISTING_HOST  - Actualizar host existente (true/false)
    DEBUG                 - Habilitar modo debug (true/false)

Distribuciones soportadas:
    - Ubuntu 18.04, 20.04, 22.04, 24.04
    - Debian 9, 10, 11, 12
    - CentOS 7, 8, 9
    - RHEL 7, 8, 9
    - Rocky Linux 8, 9
    - AlmaLinux 8, 9

Ejemplos:

1) Instalación local con parámetros:
    sudo ./zabbix.sh --server-url "http://zabbix.empresa.com" \\
                     --api-user "admin" \\
                     --api-password "mi-password" \\
                     --host-group "Servidores Linux"

2) Descarga e instalación directa con curl:
    curl -fsSL https://raw.githubusercontent.com/user/repo/main/zabbix.sh | \\
        sudo bash -s -- \\
            --server-url "https://monitoring.empresa.com" \\
            --api-user "api-user" \\
            --api-password "secure-password" \\
            --force-reinstall

3) Instalación con configuración personalizada:
    curl -s https://example.com/zabbix.sh | \\
        sudo bash -s -- \\
            --server-url "http://zabbix.local" \\
            --api-user "admin" \\
            --api-password "password" \\
            --host-group "Production Servers" \\
            --server-port "10051" \\
            --agent-port "10050" \\
            --debug

4) Solo validaciones (dry-run):
    curl -s https://example.com/zabbix.sh | \\
        sudo bash -s -- \\
            --server-url "http://test.local" \\
            --api-user "test" \\
            --api-password "test" \\
            --dry-run

Opciones adicionales:
    -h, --help         Mostrar esta ayuda
    -v, --version      Mostrar versión del script
    --dry-run          Ejecutar sin hacer cambios (solo validaciones)

Notas de seguridad:
    - Los parámetros de línea de comandos son más seguros que variables de entorno
    - No hardcodee credenciales en scripts
    - Use HTTPS cuando sea posible
    - Los parámetros pueden ser visibles en 'ps' temporalmente

EOF
}

show_version() {
    echo "Zabbix Agent Installer v1.0.0"
    echo "Compatible con Zabbix 7.0"
    echo "Soporte para Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux"
}

show_summary() {
    log_info "=== RESUMEN DE INSTALACIÓN ==="
    log_info "Distribución: $DISTRO $VERSION"
    log_info "Hostname: $HOSTNAME"
    log_info "IP: $HOST_IP"
    log_info "Servidor Zabbix: $ZABBIX_SERVER_URL"
    log_info "Grupo de hosts: $ZABBIX_HOST_GROUP"
    log_info "Puerto del agente: $ZABBIX_AGENT_PORT"
    log_info "Archivo de config: $ZABBIX_CONFIG_FILE"
    log_info "Log de instalación: $LOG_FILE"
    log_info "Backup directory: $BACKUP_DIR"
    log_info "==============================="
}

final_verification() {
    log_info "Realizando verificación final..."
    
    local all_good=true
    
    # Verificar servicio
    if systemctl is-active --quiet zabbix-agent; then
        log_success "✓ Servicio zabbix-agent está corriendo"
    else
        log_error "✗ Servicio zabbix-agent no está corriendo"
        all_good=false
    fi
    
    # Verificar configuración
    if zabbix_agentd -t -c "$ZABBIX_CONFIG_FILE" &>/dev/null; then
        log_success "✓ Configuración del agente es válida"
    else
        log_error "✗ Configuración del agente tiene errores"
        all_good=false
    fi
    
    # Verificar conectividad del puerto
    if command -v nc &> /dev/null; then
        if nc -z localhost "$ZABBIX_AGENT_PORT" 2>/dev/null; then
            log_success "✓ Puerto $ZABBIX_AGENT_PORT está abierto"
        else
            log_error "✗ Puerto $ZABBIX_AGENT_PORT no está accesible"
            all_good=false
        fi
    fi
    
    # Verificar logs de errores recientes
    if [[ -f /var/log/zabbix/zabbix_agentd.log ]]; then
        local recent_errors=$(tail -50 /var/log/zabbix/zabbix_agentd.log | grep -c "ERROR" 2>/dev/null || echo "0")
        if [[ $recent_errors -eq 0 ]]; then
            log_success "✓ No hay errores recientes en los logs"
        else
            log_warning "⚠ Se encontraron $recent_errors errores recientes en logs"
        fi
    fi
    
    if [[ "$all_good" == true ]]; then
        log_success "=== INSTALACIÓN COMPLETADA EXITOSAMENTE ==="
        log_info "El agente Zabbix está instalado, configurado y corriendo."
        log_info "El host ha sido registrado en el servidor Zabbix."
        log_info ""
        log_info "Próximos pasos:"
        log_info "1. Verificar que el host aparece en la interfaz web de Zabbix"
        log_info "2. Asignar templates adicionales si es necesario"
        log_info "3. Configurar triggers y alertas según requerimientos"
    else
        log_error "=== INSTALACIÓN COMPLETADA CON ADVERTENCIAS ==="
        log_info "Revise los mensajes de error anteriores."
        log_info "El agente puede requerir configuración manual adicional."
    fi
    
    return $all_good
}

#################################################################################
#                                FUNCIÓN MAIN                                   #
#################################################################################

main() {
    # Procesar argumentos de línea de comandos
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--server-url)
                PARAM_SERVER_URL="$2"
                shift 2
                ;;
            -u|--api-user)
                PARAM_API_USER="$2"
                shift 2
                ;;
            -p|--api-password)
                PARAM_API_PASSWORD="$2"
                shift 2
                ;;
            -g|--host-group)
                PARAM_HOST_GROUP="$2"
                shift 2
                ;;
            --server-port)
                PARAM_SERVER_PORT="$2"
                shift 2
                ;;
            --agent-port)
                PARAM_AGENT_PORT="$2"
                shift 2
                ;;
            --force-reinstall)
                export FORCE_REINSTALL="true"
                shift
                ;;
            --update-existing)
                export UPDATE_EXISTING_HOST="true"
                shift
                ;;
            --debug)
                export DEBUG="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            --dry-run)
                export DRY_RUN="true"
                log_info "Modo dry-run activado - solo validaciones"
                shift
                ;;
            *)
                log_error "Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_info "=== INICIANDO INSTALACIÓN DE ZABBIX AGENT ==="
    log_info "Timestamp: $(date)"
    log_info "Usuario: $(whoami)"
    log_info "Sistema: $(uname -a)"
    
    # Validaciones iniciales
    validate_root
    validate_requirements
    get_system_info
    
    # Detección del sistema
    detect_distribution
    get_package_manager_info
    
    # Validaciones de red y Zabbix
    validate_network
    validate_zabbix_connectivity
    
    # Mostrar resumen
    show_summary
    
    # Si es dry-run, salir después de validaciones
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_success "Dry-run completado - todas las validaciones pasaron"
        exit 0
    fi
    
    # Verificar instalación existente
    check_existing_installation
    
    # Instalar Zabbix
    install_zabbix_repository
    install_zabbix_agent
    
    # Configurar agente
    configure_zabbix_agent
    configure_firewall
    setup_zabbix_service
    
    # Registrar en servidor Zabbix
    zabbix_authenticate
    
    if ! check_host_exists; then
        register_host_zabbix
    fi
    
    # Verificaciones finales
    verify_agent_connectivity
    final_verification
    
    log_success "=== PROCESO COMPLETADO ==="
}

# Ejecutar solo si el script es llamado directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
