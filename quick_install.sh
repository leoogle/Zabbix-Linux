#!/bin/bash

#################################################################################
#                     SCRIPT DE INSTALACIÓN RÁPIDA                             #
#                      Zabbix Agent - Una Línea                                #
#################################################################################
# Este script demuestra cómo instalar Zabbix Agent en una sola línea usando    #
# curl y parámetros de línea de comandos para mayor seguridad.                 #
#################################################################################

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# URL del script (cambiar por la URL real en GitHub)
SCRIPT_URL="https://raw.githubusercontent.com/tu-usuario/zabbix-installer/main/zabbix.sh"

print_header() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    INSTALADOR RÁPIDO ZABBIX AGENT                           ║"
    echo "║                          Instalación Una Línea                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_examples() {
    echo -e "\n${BLUE}=== EJEMPLOS DE USO CON CURL ===${NC}\n"
    
    echo "1. Instalación básica:"
    echo -e "${GREEN}curl -fsSL $SCRIPT_URL | \\"
    echo "    sudo bash -s -- \\"
    echo "        --server-url \"http://zabbix.empresa.com\" \\"
    echo "        --api-user \"admin\" \\"
    echo -e "        --api-password \"tu-password\"${NC}"
    echo
    
    echo "2. Instalación de producción con HTTPS:"
    echo -e "${GREEN}curl -fsSL $SCRIPT_URL | \\"
    echo "    sudo bash -s -- \\"
    echo "        --server-url \"https://monitoring.empresa.com\" \\"
    echo "        --api-user \"production-api\" \\"
    echo "        --api-password \"password-seguro\" \\"
    echo "        --host-group \"Servidores Producción\" \\"
    echo -e "        --agent-port \"10050\"${NC}"
    echo
    
    echo "3. Solo validaciones (dry-run):"
    echo -e "${GREEN}curl -fsSL $SCRIPT_URL | \\"
    echo "    sudo bash -s -- \\"
    echo "        --server-url \"http://test.zabbix.com\" \\"
    echo "        --api-user \"test\" \\"
    echo "        --api-password \"test\" \\"
    echo -e "        --dry-run${NC}"
    echo
    
    echo "4. Forzar reinstalación:"
    echo -e "${GREEN}curl -fsSL $SCRIPT_URL | \\"
    echo "    sudo bash -s -- \\"
    echo "        --server-url \"http://zabbix.local\" \\"
    echo "        --api-user \"admin\" \\"
    echo "        --api-password \"admin\" \\"
    echo -e "        --force-reinstall --debug${NC}"
    echo
    
    echo "5. Actualizar host existente:"
    echo -e "${GREEN}curl -fsSL $SCRIPT_URL | \\"
    echo "    sudo bash -s -- \\"
    echo "        --server-url \"http://zabbix.empresa.com\" \\"
    echo "        --api-user \"admin\" \\"
    echo "        --api-password \"password\" \\"
    echo -e "        --update-existing${NC}"
    echo
}

interactive_install() {
    echo -e "\n${BLUE}=== INSTALACIÓN INTERACTIVA ===${NC}\n"
    
    # Solicitar información básica
    read -p "URL del servidor Zabbix (ej: http://zabbix.empresa.com): " server_url
    read -p "Usuario API de Zabbix: " api_user
    read -s -p "Contraseña API de Zabbix: " api_password
    echo
    
    # Validar campos requeridos
    if [[ -z "$server_url" ]] || [[ -z "$api_user" ]] || [[ -z "$api_password" ]]; then
        print_error "Todos los campos básicos son requeridos"
        return 1
    fi
    
    # Solicitar configuración adicional
    echo -e "\n${YELLOW}Configuración adicional (opcional):${NC}"
    read -p "Grupo de hosts [Linux servers]: " host_group
    read -p "Puerto del agente [10050]: " agent_port
    
    # Valores por defecto
    host_group="${host_group:-Linux servers}"
    agent_port="${agent_port:-10050}"
    
    # Opciones avanzadas
    echo -e "\n${YELLOW}Opciones avanzadas:${NC}"
    read -p "¿Forzar reinstalación? (y/N): " force_reinstall
    read -p "¿Actualizar host existente? (y/N): " update_existing
    read -p "¿Habilitar debug? (y/N): " enable_debug
    read -p "¿Solo validaciones (dry-run)? (y/N): " dry_run
    
    # Construir comando
    local cmd="curl -fsSL $SCRIPT_URL | sudo bash -s --"
    cmd+=" --server-url \"$server_url\""
    cmd+=" --api-user \"$api_user\""
    cmd+=" --api-password \"$api_password\""
    cmd+=" --host-group \"$host_group\""
    cmd+=" --agent-port \"$agent_port\""
    
    if [[ "$force_reinstall" =~ ^[Yy]$ ]]; then
        cmd+=" --force-reinstall"
    fi
    
    if [[ "$update_existing" =~ ^[Yy]$ ]]; then
        cmd+=" --update-existing"
    fi
    
    if [[ "$enable_debug" =~ ^[Yy]$ ]]; then
        cmd+=" --debug"
    fi
    
    if [[ "$dry_run" =~ ^[Yy]$ ]]; then
        cmd+=" --dry-run"
    fi
    
    # Mostrar comando final
    echo -e "\n${BLUE}Comando a ejecutar:${NC}"
    # Ocultar password en la visualización
    local display_cmd=$(echo "$cmd" | sed "s/--api-password \"[^\"]*\"/--api-password \"***\"/")
    echo "$display_cmd"
    echo
    
    # Confirmar ejecución
    read -p "¿Ejecutar instalación? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Ejecutando instalación..."
        eval "$cmd"
    else
        print_info "Instalación cancelada"
    fi
}

generate_oneliner() {
    echo -e "\n${BLUE}=== GENERADOR DE COMANDO UNA LÍNEA ===${NC}\n"
    
    read -p "URL del servidor Zabbix: " server_url
    read -p "Usuario API: " api_user
    read -s -p "Contraseña API: " api_password
    echo
    
    if [[ -z "$server_url" ]] || [[ -z "$api_user" ]] || [[ -z "$api_password" ]]; then
        print_error "Campos básicos requeridos"
        return 1
    fi
    
    # Generar comando
    local oneliner="curl -fsSL $SCRIPT_URL | sudo bash -s -- --server-url \"$server_url\" --api-user \"$api_user\" --api-password \"$api_password\""
    
    echo -e "\n${GREEN}Comando generado:${NC}"
    echo "curl -fsSL $SCRIPT_URL | sudo bash -s -- --server-url \"$server_url\" --api-user \"$api_user\" --api-password \"***\""
    echo
    
    echo -e "${YELLOW}Comando completo (copiar y pegar):${NC}"
    echo "$oneliner"
    echo
    
    read -p "¿Ejecutar ahora? (y/N): " execute
    if [[ "$execute" =~ ^[Yy]$ ]]; then
        eval "$oneliner"
    fi
}

verify_requirements() {
    print_info "Verificando requisitos..."
    
    # Verificar curl
    if ! command -v curl &> /dev/null; then
        print_error "curl no está instalado"
        print_info "Instalar con: sudo apt update && sudo apt install curl"
        return 1
    fi
    
    # Verificar permisos
    if [[ $EUID -eq 0 ]]; then
        print_warning "Ejecutándose como root"
    else
        print_info "Recuerde usar 'sudo' para la instalación"
    fi
    
    # Verificar conectividad
    if ping -c 1 8.8.8.8 &> /dev/null; then
        print_info "Conectividad de red: OK"
    else
        print_warning "Sin conectividad de red"
    fi
    
    return 0
}

main() {
    print_header
    
    echo "Este script facilita la instalación de Zabbix Agent usando curl y parámetros"
    echo "de línea de comandos para mayor seguridad (no expone credenciales en GitHub)."
    echo
    
    verify_requirements
    
    echo -e "\n${BLUE}Opciones disponibles:${NC}"
    echo "1) Ver ejemplos de uso con curl"
    echo "2) Instalación interactiva (guiada)"
    echo "3) Generar comando de una línea"
    echo "4) Instalación rápida (valores por defecto)"
    echo "5) Salir"
    echo
    
    read -p "Seleccione una opción (1-5): " option
    
    case $option in
        1)
            show_examples
            ;;
        2)
            interactive_install
            ;;
        3)
            generate_oneliner
            ;;
        4)
            print_info "Instalación rápida con valores de desarrollo..."
            curl -fsSL "$SCRIPT_URL" | sudo bash -s -- \
                --server-url "http://zabbix.local" \
                --api-user "admin" \
                --api-password "zabbix" \
                --host-group "Development Servers" \
                --debug
            ;;
        5)
            print_info "Saliendo..."
            exit 0
            ;;
        *)
            print_error "Opción inválida"
            exit 1
            ;;
    esac
}

# Verificar si se está ejecutando directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi