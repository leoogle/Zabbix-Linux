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
#   ZABBIX_SERVER_URL      - URL del servidor Zabbix (ej: http://zabbix.local) #
#   ZABBIX_API_TOKEN       - Token de API para autenticación                  #
#                            (ej: 8a29710542180b6eb941de2b55aeeeba...)         #
#                                                                               #
# Variables opcionales:                                                         #
#   ZABBIX_HOST_GROUP      - Grupo de hosts (default: "Linux servers")        #
#   ZABBIX_EXPECTED_VERSION - Versión esperada del agente (para validación)   #
#   ZABBIX_TEMPLATE_NAME   - Nombre del template (default: "Linux by Zabbix agent") #
#   ZABBIX_KNOWN_GROUP_ID  - ID conocido del grupo (optimización)             #
#   ZABBIX_KNOWN_TEMPLATE_ID - ID conocido del template (optimización)        #
#   ZABBIX_SERVER_PORT     - Puerto del servidor (default: 10051)             #
#   ZABBIX_AGENT_PORT      - Puerto del agente (default: 10050)               #
#                                                                               #
# Características mejoradas:                                                   #
# - Autenticación mediante API token                                          #
# - URLs de fallback automático para diferentes configuraciones de Zabbix     #
# - Detección inteligente de IP excluyendo interfaces virtuales               #
# - Verificación y comparación de versiones del agente                        #
# - Gestión robusta de servicios con múltiples nombres                        #
# - Configuración conocida para evitar búsquedas innecesarias                 #
# - Manejo de errores mejorado con reintentos automáticos                     #
#################################################################################

# Configuración global
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Variables de configuración (pueden ser sobrescritas por parámetros o variables de entorno)
ZABBIX_SERVER_URL="${ZABBIX_SERVER_URL:-}"
ZABBIX_API_TOKEN="${ZABBIX_API_TOKEN:-}"
ZABBIX_HOST_GROUP="${ZABBIX_HOST_GROUP:-Linux servers}"
ZABBIX_SERVER_PORT="${ZABBIX_SERVER_PORT:-10051}"
ZABBIX_AGENT_PORT="${ZABBIX_AGENT_PORT:-10050}"
ZABBIX_EXPECTED_VERSION="${ZABBIX_EXPECTED_VERSION:-}"

# Configuración conocida para evitar búsquedas innecesarias (opcional)
ZABBIX_KNOWN_GROUP_ID="${ZABBIX_KNOWN_GROUP_ID:-}"
ZABBIX_KNOWN_TEMPLATE_ID="${ZABBIX_KNOWN_TEMPLATE_ID:-}"
ZABBIX_TEMPLATE_NAME="${ZABBIX_TEMPLATE_NAME:-Linux by Zabbix agent}"

# Variables para parámetros de línea de comandos
PARAM_SERVER_URL=""
PARAM_API_TOKEN=""
PARAM_HOST_GROUP=""
PARAM_SERVER_PORT=""
PARAM_AGENT_PORT=""

# Variables internas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd 2>/dev/null || pwd)"
LOG_FILE="/tmp/zabbix_install_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/tmp/zabbix_backup_$(date +%Y%m%d_%H%M%S)"
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
    if [[ -n "$PARAM_API_TOKEN" ]]; then
        ZABBIX_API_TOKEN="$PARAM_API_TOKEN"
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
    
    # Validar que se proporcione el API token
    if [[ -z "$ZABBIX_API_TOKEN" ]]; then
        log_error "Se requiere el token de API de Zabbix"
        log_info "Use: --api-token <TOKEN> o export ZABBIX_API_TOKEN='8a29710542180b6eb941de2b55aeeeba...'"
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

detect_primary_ip() {
    log_debug "Detectando IP principal del sistema..."
    
    # Lista de interfaces a excluir (virtuales, VPN, etc.)
    local excluded_interfaces=(
        "lo" "loopback" "docker" "br-" "veth" "virbr" "vmnet" "vbox" 
        "tun" "tap" "ppp" "wg" "vpn" "vlan" "bond" "team"
    )
    
    # Patrones de IP a excluir
    local excluded_ip_patterns=(
        "127\."          # Loopback
        "169\.254\."     # APIPA/Link-local
        "172\.1[6-9]\."  # Docker default range start
        "172\.2[0-9]\."  # Docker default range middle
        "172\.3[0-1]\."  # Docker default range end
        "192\.168\.27\." # VirtualBox host-only
        "192\.168\.56\." # VirtualBox host-only default
        "10\.0\.75\."    # Hyper-V default
    )
    
    local best_ip=""
    local best_interface=""
    local best_score=0
    
    # Método 1: Usar ip route para obtener la IP de la ruta por defecto
    local default_route_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/ {print $7}' | head -1)
    if [[ -n "$default_route_ip" ]]; then
        local default_route_interface=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {print $5}' | head -1)
        log_debug "IP de ruta por defecto: $default_route_ip (interfaz: $default_route_interface)"
        
        # Verificar si esta IP debe ser excluida
        local exclude_ip=false
        for pattern in "${excluded_ip_patterns[@]}"; do
            if [[ "$default_route_ip" =~ $pattern ]]; then
                exclude_ip=true
                log_debug "IP $default_route_ip excluida por patrón: $pattern"
                break
            fi
        done
        
        # Verificar si la interfaz debe ser excluida
        local exclude_interface=false
        for excluded in "${excluded_interfaces[@]}"; do
            if [[ "$default_route_interface" == *"$excluded"* ]]; then
                exclude_interface=true
                log_debug "Interfaz $default_route_interface excluida por contener: $excluded"
                break
            fi
        done
        
        if [[ "$exclude_ip" == false && "$exclude_interface" == false ]]; then
            best_ip="$default_route_ip"
            best_interface="$default_route_interface"
            best_score=100
            log_debug "Usando IP de ruta por defecto: $best_ip"
        fi
    fi
    
    # Método 2: Si no tenemos una buena IP, buscar en todas las interfaces
    if [[ -z "$best_ip" ]]; then
        log_debug "Buscando IPs en todas las interfaces..."
        
        # Obtener todas las IPs del sistema
        local all_ips
        if command -v ip &>/dev/null; then
            all_ips=$(ip addr show 2>/dev/null | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2, $NF}')
        elif command -v ifconfig &>/dev/null; then
            all_ips=$(ifconfig 2>/dev/null | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2, $1}' | sed 's/addr://')
        fi
        
        while IFS=' ' read -r ip_cidr interface; do
            [[ -z "$ip_cidr" ]] && continue
            
            local ip_addr="${ip_cidr%/*}"  # Remover CIDR
            [[ -z "$ip_addr" ]] && continue
            
            log_debug "Evaluando IP: $ip_addr (interfaz: $interface)"
            
            # Verificar patrones de IP excluidos
            local exclude_ip=false
            for pattern in "${excluded_ip_patterns[@]}"; do
                if [[ "$ip_addr" =~ $pattern ]]; then
                    exclude_ip=true
                    log_debug "IP $ip_addr excluida por patrón: $pattern"
                    break
                fi
            done
            
            [[ "$exclude_ip" == true ]] && continue
            
            # Verificar interfaces excluidas
            local exclude_interface=false
            for excluded in "${excluded_interfaces[@]}"; do
                if [[ "$interface" == *"$excluded"* ]]; then
                    exclude_interface=true
                    log_debug "Interfaz $interface excluida por contener: $excluded"
                    break
                fi
            done
            
            [[ "$exclude_interface" == true ]] && continue
            
            # Calcular puntuación para esta IP
            local score=0
            
            # IPs privadas comunes tienen mayor puntuación
            if [[ "$ip_addr" =~ ^192\.168\. ]]; then
                score=$((score + 50))
            elif [[ "$ip_addr" =~ ^10\. ]]; then
                score=$((score + 40))
            elif [[ "$ip_addr" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
                score=$((score + 30))
            else
                # IP pública
                score=$((score + 60))
            fi
            
            # Interfaces comunes tienen mayor puntuación
            if [[ "$interface" =~ ^(eth|ens|enp|eno|em) ]]; then
                score=$((score + 20))
            elif [[ "$interface" =~ ^wl ]]; then
                score=$((score + 15))
            fi
            
            log_debug "IP $ip_addr (interfaz: $interface) puntuación: $score"
            
            if [[ $score -gt $best_score ]]; then
                best_ip="$ip_addr"
                best_interface="$interface"
                best_score=$score
                log_debug "Nueva mejor IP: $best_ip (puntuación: $best_score)"
            fi
            
        done <<< "$all_ips"
    fi
    
    # Método 3: Fallback a métodos tradicionales
    if [[ -z "$best_ip" ]]; then
        log_warning "No se pudo detectar IP inteligentemente, usando métodos tradicionales..."
        best_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || \
                  ifconfig 2>/dev/null | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
    fi
    
    HOST_IP="$best_ip"
    log_debug "IP final seleccionada: $HOST_IP (interfaz: $best_interface)"
}

get_system_info() {
    log_info "Obteniendo información del sistema..."
    
    # Obtener hostname
    HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    log_info "Hostname: $HOSTNAME"
    
    # Obtener IP principal de forma inteligente (excluyendo interfaces virtuales)
    detect_primary_ip
    
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

get_installed_zabbix_version() {
    local installed_version=""
    
    case "$DISTRO" in
        "ubuntu"|"debian")
            if dpkg -l | grep -q "zabbix-agent"; then
                installed_version=$(dpkg -l | grep "zabbix-agent" | grep -v "zabbix-agent2" | awk '{print $3}' | head -1)
            elif dpkg -l | grep -q "zabbix-agent2"; then
                installed_version=$(dpkg -l | grep "zabbix-agent2" | awk '{print $3}' | head -1)
            fi
            ;;
        "centos"|"rhel"|"rocky"|"almalinux")
            if rpm -qa | grep -q "zabbix-agent-"; then
                installed_version=$(rpm -qa | grep "zabbix-agent-" | grep -v "zabbix-agent2-" | head -1 | sed 's/zabbix-agent-//' | cut -d'-' -f1)
            elif rpm -qa | grep -q "zabbix-agent2-"; then
                installed_version=$(rpm -qa | grep "zabbix-agent2-" | head -1 | sed 's/zabbix-agent2-//' | cut -d'-' -f1)
            fi
            ;;
    esac
    
    # También intentar obtener versión del binario si está instalado
    if [[ -z "$installed_version" ]]; then
        if command -v zabbix_agentd &>/dev/null; then
            installed_version=$(zabbix_agentd -V 2>/dev/null | grep "zabbix_agentd" | awk '{print $3}' | head -1)
        elif command -v zabbix_agent2 &>/dev/null; then
            installed_version=$(zabbix_agent2 -V 2>/dev/null | grep "zabbix_agent2" | awk '{print $3}' | head -1)
        fi
    fi
    
    echo "$installed_version"
}

compare_versions() {
    local version1="$1"
    local version2="$2"
    
    # Normalizar versiones (remover sufijos como -1ubuntu1, etc.)
    version1=$(echo "$version1" | sed 's/[:-].*//')
    version2=$(echo "$version2" | sed 's/[:-].*//')
    
    if [[ "$version1" == "$version2" ]]; then
        return 0  # Iguales
    fi
    
    # Comparar usando sort -V si está disponible
    if command -v sort &>/dev/null; then
        local latest=$(printf '%s\n%s\n' "$version1" "$version2" | sort -V | tail -1)
        if [[ "$latest" == "$version2" ]]; then
            return 1  # version2 es mayor
        else
            return 2  # version1 es mayor
        fi
    fi
    
    # Fallback: comparación simple
    if [[ "$version1" < "$version2" ]]; then
        return 1
    else
        return 2
    fi
}

check_version_requirements() {
    log_info "Verificando versión del agente Zabbix..."
    
    local installed_version=$(get_installed_zabbix_version)
    
    if [[ -z "$installed_version" ]]; then
        log_info "Agente Zabbix no está instalado"
        return 1  # Necesita instalación
    fi
    
    log_info "Versión instalada: $installed_version"
    
    if [[ -n "$ZABBIX_EXPECTED_VERSION" ]]; then
        log_info "Versión esperada: $ZABBIX_EXPECTED_VERSION"
        
        compare_versions "$installed_version" "$ZABBIX_EXPECTED_VERSION"
        local comparison=$?
        
        case $comparison in
            0)
                log_success "La versión instalada coincide con la esperada"
                return 0  # No necesita actualización
                ;;
            1)
                log_warning "La versión instalada ($installed_version) es anterior a la esperada ($ZABBIX_EXPECTED_VERSION)"
                log_info "Se procederá a actualizar..."
                return 1  # Necesita actualización
                ;;
            2)
                log_info "La versión instalada ($installed_version) es posterior a la esperada ($ZABBIX_EXPECTED_VERSION)"
                log_info "Se mantendrá la versión actual"
                return 0  # No necesita actualización
                ;;
        esac
    else
        log_info "No se especificó versión esperada, se mantendrá la versión actual: $installed_version"
        return 0  # No necesita actualización
    fi
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
    
    # Verificar versión y determinar si necesita instalación/actualización
    if ! check_version_requirements; then
        log_info "Se requiere instalación o actualización del agente"
        return 1  # Necesita instalación/actualización
    fi
    
    # Verificar si el servicio está corriendo
    local service_running=false
    local service_names=("zabbix-agent" "zabbix-agent2")
    local active_service=""
    
    for service_name in "${service_names[@]}"; do
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            service_running=true
            active_service="$service_name"
            log_info "Servicio $service_name está activo"
            break
        fi
    done
    
    if [[ "$service_running" == false ]]; then
        log_warning "Agente Zabbix está instalado pero el servicio no está corriendo"
        
        # Intentar encontrar el servicio correcto
        for service_name in "${service_names[@]}"; do
            if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
                log_info "Encontrado servicio habilitado: $service_name"
                active_service="$service_name"
                break
            fi
        done
        
        if [[ -n "$active_service" ]]; then
            log_info "Intentando iniciar servicio $active_service..."
            if systemctl start "$active_service" 2>/dev/null; then
                log_success "Servicio $active_service iniciado correctamente"
                service_running=true
            else
                log_warning "No se pudo iniciar el servicio $active_service"
            fi
        fi
    fi
    
    # Determinar configuración de archivos
    if [[ -f "/etc/zabbix/zabbix_agentd.conf" ]]; then
        ZABBIX_CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
    elif [[ -f "/etc/zabbix/zabbix_agent2.conf" ]]; then
        ZABBIX_CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
    else
        log_warning "No se encontró archivo de configuración de Zabbix"
        return 1  # Necesita instalación
    fi
    
    # Verificar si se debe forzar reinstalación
    if [[ "${FORCE_REINSTALL:-false}" == "true" ]]; then
        log_info "FORCE_REINSTALL=true, procediendo con reinstalación completa..."
        
        # Detener servicio si está corriendo
        if [[ "$service_running" == true ]]; then
            systemctl stop "$active_service" 2>/dev/null || true
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
        
        return 1  # Necesita instalación
    else
        log_info "Agente Zabbix ya instalado. Use FORCE_REINSTALL=true para reinstalar"
        log_info "Procediendo con reconfiguración del agente existente..."
        
        # Hacer backup de configuración
        if [[ -f "$ZABBIX_CONFIG_FILE" ]]; then
            cp "$ZABBIX_CONFIG_FILE" "$BACKUP_DIR/zabbix_agentd.conf.backup"
        fi
        
        log_success "Verificación de instalación existente completada"
        return 0  # No necesita instalación
    fi
}

#################################################################################
#                         FUNCIONES DE API ZABBIX                              #
#################################################################################

zabbix_api_call() {
    local method="$1"
    local params="$2"
    local auth_required="${3:-true}"
    local max_retries=3
    local retry_count=0
    
    # URLs alternativas para probar
    local api_urls=(
        "$ZABBIX_SERVER_URL/api_jsonrpc.php"
        "$ZABBIX_SERVER_URL/zabbix/api_jsonrpc.php"
    )
    
    # Si el servidor no tiene esquema, agregar http y https
    if [[ ! "$ZABBIX_SERVER_URL" =~ ^https?:// ]]; then
        local base_url="$ZABBIX_SERVER_URL"
        api_urls=(
            "https://$base_url/api_jsonrpc.php"
            "https://$base_url/zabbix/api_jsonrpc.php"
            "http://$base_url/api_jsonrpc.php"
            "http://$base_url/zabbix/api_jsonrpc.php"
        )
    fi
    
    while [[ $retry_count -lt $max_retries ]]; do
        for api_url in "${api_urls[@]}"; do
            log_debug "Intentando API URL: $api_url (intento $((retry_count + 1))/$max_retries)"
            
            local request_data='{
                "jsonrpc": "2.0",
                "method": "'$method'",
                "params": '$params',
                "id": 1'
            
            # Manejar autenticación con API token
            if [[ "$auth_required" == "true" ]]; then
                if [[ -z "$ZABBIX_API_TOKEN" ]]; then
                    log_error "No hay token de API disponible"
                    return 1
                fi
                # Usar API token en header
                local headers=(-H "Content-Type: application/json-rpc" 
                             -H "User-Agent: Zabbix-Installer/1.0"
                             -H "Authorization: Bearer $ZABBIX_API_TOKEN")
            else
                local headers=(-H "Content-Type: application/json-rpc" 
                             -H "User-Agent: Zabbix-Installer/1.0")
            fi
            
            request_data+='}'
            log_debug "API Request: $request_data"
            
            local response=$(curl -s \
                "${headers[@]}" \
                --connect-timeout 15 \
                --max-time 30 \
                -d "$request_data" \
                "$api_url" 2>/dev/null)
            
            if [[ -n "$response" ]]; then
                log_debug "API Response: $response"
                
                # Verificar si hay error en la respuesta
                if echo "$response" | grep -q '"error"'; then
                    local error_code=$(echo "$response" | jq -r '.error.code // empty' 2>/dev/null || echo "")
                    local error_message=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null || 
                                        echo "$response" | grep -o '"message":"[^"]*"' | cut -d':' -f2 | tr -d '"')
                    local error_data=$(echo "$response" | jq -r '.error.data // empty' 2>/dev/null || echo "")
                    
                    log_debug "Error de API - Código: $error_code, Mensaje: $error_message, Datos: $error_data"
                    
                    # Solo mostrar error en el último intento
                    if [[ $retry_count -eq $((max_retries - 1)) ]]; then
                        log_error "Error en API de Zabbix: $error_message"
                        [[ -n "$error_data" ]] && log_error "Detalles: $error_data"
                    fi
                    
                    # Si es error de autenticación, no reintentar
                    if [[ "$error_code" =~ ^-?(32602|32700|32004)$ ]]; then
                        return 1
                    fi
                else
                    # Respuesta exitosa
                    echo "$response"
                    return 0
                fi
            else
                log_debug "No se recibió respuesta de $api_url"
            fi
        done
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_debug "Reintentando en 5 segundos..."
            sleep 5
        fi
    done
    
    log_error "No se pudo conectar a la API de Zabbix después de $max_retries intentos"
    return 1
}

test_zabbix_connection() {
    log_info "Probando conexión a la API de Zabbix..."
    
    # Probar versión de API primero
    local version_response=$(zabbix_api_call "apiinfo.version" "{}" "false")
    if [[ $? -eq 0 && -n "$version_response" ]]; then
        local version=$(echo "$version_response" | jq -r '.result // empty' 2>/dev/null || 
                       echo "$version_response" | grep -o '"result":"[^"]*"' | cut -d':' -f2 | tr -d '"')
        log_success "Conexión exitosa. Versión del servidor: $version"
        
        # Probar autenticación con API token
        log_info "Probando autenticación con API token..."
        local test_auth=$(zabbix_api_call "hostgroup.get" '{"output": ["groupid"], "limit": 1}' "true")
        if [[ $? -eq 0 ]]; then
            log_success "Autenticación con API token exitosa"
            return 0
        else
            log_error "Fallo autenticación con API token"
            return 1
        fi
    else
        log_error "No se pudo conectar a la API de Zabbix"
        return 1
    fi
}

zabbix_authenticate() {
    # Verificar que tenemos el API token
    if [[ -z "$ZABBIX_API_TOKEN" ]]; then
        log_error "No se ha proporcionado el token de API"
        return 1
    fi
    
    log_info "Usando API token para autenticación"
    log_success "Token de API configurado correctamente"
    return 0
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
    
    # Si tenemos un ID conocido, verificar que existe y usarlo
    if [[ -n "$ZABBIX_KNOWN_GROUP_ID" ]]; then
        log_debug "Verificando ID de grupo conocido: $ZABBIX_KNOWN_GROUP_ID"
        
        local verify_params='{
            "output": ["groupid", "name"],
            "groupids": ["'$ZABBIX_KNOWN_GROUP_ID'"]
        }'
        
        local response=$(zabbix_api_call "hostgroup.get" "$verify_params")
        if [[ $? -eq 0 ]]; then
            local found_name=$(echo "$response" | jq -r '.result[0].name // empty' 2>/dev/null || 
                              echo "$response" | grep -o '"name":"[^"]*"' | head -1 | cut -d':' -f2 | tr -d '"')
            
            if [[ -n "$found_name" ]]; then
                log_success "Usando ID de grupo conocido: $ZABBIX_KNOWN_GROUP_ID (nombre: $found_name)"
                echo "$ZABBIX_KNOWN_GROUP_ID"
                return 0
            else
                log_warning "ID de grupo conocido $ZABBIX_KNOWN_GROUP_ID no es válido, buscando por nombre..."
            fi
        else
            log_warning "Error verificando ID de grupo conocido, buscando por nombre..."
        fi
    fi
    
    # Buscar por nombre
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
    
    local group_id=$(echo "$response" | jq -r '.result[0].groupid // empty' 2>/dev/null || 
                    echo "$response" | grep -o '"groupid":"[^"]*"' | head -1 | cut -d':' -f2 | tr -d '"')
    
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

get_template_id() {
    log_info "Obteniendo ID del template: $ZABBIX_TEMPLATE_NAME"
    
    # Si tenemos un ID conocido, verificar que existe y usarlo
    if [[ -n "$ZABBIX_KNOWN_TEMPLATE_ID" ]]; then
        log_debug "Verificando ID de template conocido: $ZABBIX_KNOWN_TEMPLATE_ID"
        
        local verify_params='{
            "output": ["templateid", "host", "name"],
            "templateids": ["'$ZABBIX_KNOWN_TEMPLATE_ID'"]
        }'
        
        local response=$(zabbix_api_call "template.get" "$verify_params")
        if [[ $? -eq 0 ]]; then
            local found_name=$(echo "$response" | jq -r '.result[0].name // .result[0].host // empty' 2>/dev/null || 
                              echo "$response" | grep -o '"name":"[^"]*"' | head -1 | cut -d':' -f2 | tr -d '"')
            
            if [[ -n "$found_name" ]]; then
                log_success "Usando ID de template conocido: $ZABBIX_KNOWN_TEMPLATE_ID (nombre: $found_name)"
                echo "$ZABBIX_KNOWN_TEMPLATE_ID"
                return 0
            else
                log_warning "ID de template conocido $ZABBIX_KNOWN_TEMPLATE_ID no es válido, buscando por nombre..."
            fi
        else
            log_warning "Error verificando ID de template conocido, buscando por nombre..."
        fi
    fi
    
    # Buscar por nombre
    local template_params='{
        "output": ["templateid", "host", "name"],
        "filter": {
            "name": ["'$ZABBIX_TEMPLATE_NAME'"]
        }
    }'
    
    local response=$(zabbix_api_call "template.get" "$template_params")
    if [[ $? -ne 0 ]]; then
        log_warning "Error consultando templates por nombre, intentando por host..."
        
        # Intentar buscar por host (nombre técnico)
        template_params='{
            "output": ["templateid", "host", "name"],
            "filter": {
                "host": ["'$ZABBIX_TEMPLATE_NAME'"]
            }
        }'
        
        response=$(zabbix_api_call "template.get" "$template_params")
        if [[ $? -ne 0 ]]; then
            log_error "Error consultando templates"
            return 1
        fi
    fi
    
    local template_id=$(echo "$response" | jq -r '.result[0].templateid // empty' 2>/dev/null || 
                       echo "$response" | grep -o '"templateid":"[^"]*"' | head -1 | cut -d':' -f2 | tr -d '"')
    
    if [[ -z "$template_id" ]]; then
        log_warning "Template '$ZABBIX_TEMPLATE_NAME' no encontrado"
        
        # Lista de templates comunes de Linux como fallback
        local common_templates=("Linux by Zabbix agent" "Template OS Linux" "Template OS Linux by Zabbix agent" "10001")
        
        for fallback_template in "${common_templates[@]}"; do
            if [[ "$fallback_template" == "$ZABBIX_TEMPLATE_NAME" ]]; then
                continue  # Ya lo intentamos
            fi
            
            log_info "Intentando template fallback: $fallback_template"
            
            if [[ "$fallback_template" =~ ^[0-9]+$ ]]; then
                # Es un ID numérico, verificar directamente
                local verify_params='{
                    "output": ["templateid", "host", "name"],
                    "templateids": ["'$fallback_template'"]
                }'
                
                local fallback_response=$(zabbix_api_call "template.get" "$verify_params")
                if [[ $? -eq 0 ]]; then
                    local found_id=$(echo "$fallback_response" | jq -r '.result[0].templateid // empty' 2>/dev/null || 
                                    echo "$fallback_response" | grep -o '"templateid":"[^"]*"' | head -1 | cut -d':' -f2 | tr -d '"')
                    
                    if [[ -n "$found_id" ]]; then
                        log_success "Usando template fallback con ID: $found_id"
                        echo "$found_id"
                        return 0
                    fi
                fi
            else
                # Buscar por nombre
                local fallback_params='{
                    "output": ["templateid", "host", "name"],
                    "search": {
                        "name": "'$fallback_template'"
                    }
                }'
                
                local fallback_response=$(zabbix_api_call "template.get" "$fallback_params")
                if [[ $? -eq 0 ]]; then
                    local found_id=$(echo "$fallback_response" | jq -r '.result[0].templateid // empty' 2>/dev/null || 
                                    echo "$fallback_response" | grep -o '"templateid":"[^"]*"' | head -1 | cut -d':' -f2 | tr -d '"')
                    
                    if [[ -n "$found_id" ]]; then
                        log_success "Usando template fallback: $fallback_template (ID: $found_id)"
                        echo "$found_id"
                        return 0
                    fi
                fi
            fi
        done
        
        log_error "No se encontró ningún template válido para Linux"
        return 1
    fi
    
    log_success "ID del template '$ZABBIX_TEMPLATE_NAME': $template_id"
    echo "$template_id"
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
    
    # Obtener ID del template
    local template_id=$(get_template_id)
    if [[ $? -ne 0 ]] || [[ -z "$template_id" ]]; then
        log_warning "No se pudo obtener ID del template, continuando sin template..."
        template_id=""
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
        ]'
    
    # Agregar template si se encontró uno válido
    if [[ -n "$template_id" ]]; then
        host_params+=',
        "templates": [
            {
                "templateid": "'$template_id'"
            }
        ]'
    fi
    
    host_params+=',
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
        log_debug "Respuesta recibida: $api_test"
        log_info "Intentando probar con URL alternativa: $ZABBIX_SERVER_URL/zabbix/api_jsonrpc.php"
        
        # Intentar con ruta alternativa
        local api_test_alt=$(curl -s --connect-timeout 10 --max-time 30 \
            -H "Content-Type: application/json-rpc" \
            -d '{"jsonrpc":"2.0","method":"apiinfo.version","id":1}' \
            "$ZABBIX_SERVER_URL/zabbix/api_jsonrpc.php")
        
        local api_version_alt=$(echo "$api_test_alt" | grep -o '"result":"[^"]*"' | cut -d':' -f2 | tr -d '"')
        if [[ -n "$api_version_alt" ]]; then
            log_success "API de Zabbix disponible en ruta alternativa, versión: $api_version_alt"
        else
            log_debug "Respuesta alternativa recibida: $api_test_alt"
            log_error "No se pudo validar la API de Zabbix en ninguna ruta"
            return 1
        fi
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

get_zabbix_service_name() {
    local service_names=("zabbix-agent" "zabbix-agent2")
    
    for service_name in "${service_names[@]}"; do
        if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^$service_name.service"; then
            echo "$service_name"
            return 0
        fi
    done
    
    # Fallback: buscar por paquetes instalados
    case "$DISTRO" in
        "ubuntu"|"debian")
            if dpkg -l | grep -q "zabbix-agent2"; then
                echo "zabbix-agent2"
                return 0
            elif dpkg -l | grep -q "zabbix-agent"; then
                echo "zabbix-agent"
                return 0
            fi
            ;;
        "centos"|"rhel"|"rocky"|"almalinux")
            if rpm -qa | grep -q "zabbix-agent2-"; then
                echo "zabbix-agent2"
                return 0
            elif rpm -qa | grep -q "zabbix-agent-"; then
                echo "zabbix-agent"
                return 0
            fi
            ;;
    esac
    
    return 1
}

setup_zabbix_service() {
    log_info "Configurando servicio de Zabbix..."
    
    # Detectar el nombre correcto del servicio
    local service_name=$(get_zabbix_service_name)
    if [[ -z "$service_name" ]]; then
        log_error "No se pudo determinar el nombre del servicio Zabbix"
        return 1
    fi
    
    log_info "Servicio detectado: $service_name"
    
    # Verificar si el servicio existe
    if ! systemctl list-unit-files --type=service 2>/dev/null | grep -q "^$service_name.service"; then
        log_error "Servicio $service_name no encontrado"
        return 1
    fi
    
    # Habilitar el servicio para inicio automático
    log_info "Habilitando servicio $service_name para inicio automático..."
    if ! systemctl enable "$service_name" 2>/dev/null; then
        log_warning "No se pudo habilitar $service_name para inicio automático"
    else
        log_success "Servicio $service_name habilitado para inicio automático"
    fi
    
    # Verificar si el servicio está corriendo y detenerlo para aplicar nueva configuración
    if systemctl is-active --quiet "$service_name"; then
        log_info "Deteniendo servicio existente $service_name..."
        if ! systemctl stop "$service_name" 2>/dev/null; then
            log_warning "No se pudo detener el servicio $service_name correctamente"
        else
            # Esperar un momento para asegurar que se detuvo
            sleep 2
        fi
    fi
    
    # Recargar la configuración de systemd
    systemctl daemon-reload 2>/dev/null || true
    
    # Iniciar el servicio
    log_info "Iniciando servicio $service_name..."
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Intento $attempt de $max_attempts para iniciar $service_name"
        
        if systemctl start "$service_name" 2>/dev/null; then
            log_debug "Comando de inicio ejecutado correctamente"
            
            # Esperar un momento y verificar el estado
            sleep 3
            
            if systemctl is-active --quiet "$service_name"; then
                log_success "Servicio $service_name iniciado correctamente"
                
                # Verificar que está escuchando en el puerto
                local port=$ZABBIX_AGENT_PORT
                if ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; then
                    log_success "Servicio $service_name está escuchando en puerto $port"
                else
                    log_warning "Servicio $service_name está corriendo pero no parece estar escuchando en puerto $port"
                fi
                
                return 0
            else
                log_warning "Servicio $service_name no está activo después del inicio (intento $attempt)"
            fi
        else
            log_warning "Error al ejecutar comando de inicio para $service_name (intento $attempt)"
        fi
        
        # Mostrar logs para diagnóstico
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "No se pudo iniciar el servicio $service_name después de $max_attempts intentos"
            log_info "Estado del servicio:"
            systemctl status "$service_name" --no-pager -l 2>/dev/null || true
            log_info "Últimos logs del servicio:"
            journalctl -u "$service_name" --no-pager -l -n 20 2>/dev/null || true
            
            # Verificar configuración
            if [[ -f "$ZABBIX_CONFIG_FILE" ]]; then
                log_info "Verificando sintaxis de configuración..."
                local config_check=""
                if [[ "$service_name" == "zabbix-agent2" ]]; then
                    config_check=$(zabbix_agent2 -t -c "$ZABBIX_CONFIG_FILE" 2>&1 || true)
                else
                    config_check=$(zabbix_agentd -t -c "$ZABBIX_CONFIG_FILE" 2>&1 || true)
                fi
                
                if [[ -n "$config_check" ]]; then
                    log_info "Resultado de verificación: $config_check"
                fi
            fi
            
            return 1
        fi
        
        attempt=$((attempt + 1))
        log_info "Reintentando en 5 segundos..."
        sleep 5
    done
    
    return 1
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
    ./zabbix.sh --server-url <URL> --api-token <TOKEN>
    
    # Descarga y ejecución en una línea (curl)
    curl -s https://raw.githubusercontent.com/user/repo/main/zabbix.sh | \\
        sudo bash -s -- --server-url "http://zabbix.local" \\
                        --api-token "8a29710542180b6eb941de2b55aeeeba..."

Parámetros requeridos:
    -s, --server-url <URL>        URL del servidor Zabbix (ej: http://zabbix.local)
    -t, --api-token <TOKEN>       Token de API de Zabbix para autenticación

Parámetros opcionales:
    -g, --host-group <GROUP>      Grupo de hosts (default: "Linux servers")
    --server-port <PORT>          Puerto del servidor (default: 10051)
    --agent-port <PORT>           Puerto del agente (default: 10050)
    --force-reinstall             Forzar reinstalación
    --update-existing             Actualizar host existente
    --debug                       Habilitar modo debug

Variables de entorno alternativas (MENOS SEGURO):
    ZABBIX_SERVER_URL     - URL del servidor Zabbix
    ZABBIX_API_TOKEN      - Token de API de Zabbix
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
                     --api-token "8a29710542180b6eb941de2b55aeeeba833589d4..." \\
                     --host-group "Servidores Linux"

2) Descarga e instalación directa con curl:
    curl -fsSL https://raw.githubusercontent.com/user/repo/main/zabbix.sh | \\
        sudo bash -s -- \\
            --server-url "https://monitoring.empresa.com" \\
            --api-token "your-api-token-here" \\
            --force-reinstall

3) Instalación con configuración personalizada:
    curl -s https://example.com/zabbix.sh | \\
        sudo bash -s -- \\
            --server-url "http://zabbix.local" \\
            --api-token "8a29710542180b6eb941de2b55aeeeba..." \\
            --host-group "Production Servers" \\
            --server-port "10051" \\
            --agent-port "10050" \\
            --debug

4) Solo validaciones (dry-run):
    curl -s https://example.com/zabbix.sh | \\
        sudo bash -s -- \\
            --server-url "http://test.local" \\
            --api-token "test-token-123" \\
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
            -t|--api-token)
                PARAM_API_TOKEN="$2"
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
# Protección para cuando BASH_SOURCE no está definido (ej: curl | bash)
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
    main "$@"
fi
