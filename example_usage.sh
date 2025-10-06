#!/bin/bash

#################################################################################
#                        SCRIPT DE EJEMPLO DE USO                              #
#                      Instalador de Agente Zabbix                             #
#################################################################################
# Este script demuestra cómo usar el instalador de Zabbix con diferentes       #
# configuraciones y escenarios comunes.                                        #
#################################################################################

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
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

# Verificar que el script principal existe
ZABBIX_SCRIPT="./zabbix.sh"
if [[ ! -f "$ZABBIX_SCRIPT" ]]; then
    print_error "Script zabbix.sh no encontrado en el directorio actual"
    exit 1
fi

# Verificar permisos de ejecución
if [[ ! -x "$ZABBIX_SCRIPT" ]]; then
    print_info "Agregando permisos de ejecución al script..."
    chmod +x "$ZABBIX_SCRIPT"
fi

print_section "EJEMPLOS DE USO DEL INSTALADOR ZABBIX"

echo "Este script demuestra diferentes formas de usar el instalador de Zabbix."
echo "NUEVO: Ahora soporta parámetros de línea de comandos para mayor seguridad."
echo "Seleccione una opción:"
echo
echo "1) Instalación con parámetros de línea de comandos (RECOMENDADO)"
echo "2) Instalación estilo curl una línea"
echo "3) Instalación con variables de entorno (método anterior)"
echo "4) Instalación en modo dry-run"
echo "5) Instalación forzada con parámetros"
echo "6) Actualizar host existente con parámetros"
echo "7) Configuración de producción con parámetros"
echo "8) Mostrar ayuda del instalador"
echo "9) Mostrar versión del instalador"
echo "10) Salir"
echo

read -p "Seleccione una opción (1-10): " option

case $option in
    1)
        print_section "INSTALACIÓN CON PARÁMETROS (RECOMENDADO)"
        print_info "Este método es más seguro ya que no expone credenciales en variables de entorno"
        echo
        read -p "URL del servidor Zabbix (ej: http://zabbix.ejemplo.com): " server_url
        read -p "Usuario API de Zabbix: " api_user
        read -s -p "Contraseña API de Zabbix: " api_password
        echo
        read -p "Grupo de hosts (opcional, Enter para default): " host_group
        
        if [[ -z "$server_url" ]] || [[ -z "$api_user" ]] || [[ -z "$api_password" ]]; then
            print_error "URL, usuario y contraseña son requeridos"
            exit 1
        fi
        
        print_info "Ejecutando instalación con parámetros..."
        
        cmd="sudo '$ZABBIX_SCRIPT' --server-url '$server_url' --api-user '$api_user' --api-password '$api_password'"
        if [[ -n "$host_group" ]]; then
            cmd+=" --host-group '$host_group'"
        fi
        
        echo "Comando a ejecutar:"
        echo "sudo $ZABBIX_SCRIPT --server-url '$server_url' --api-user '$api_user' --api-password '***' [--host-group '$host_group']"
        
        eval "$cmd"
        ;;
        
    2)
        print_section "INSTALACIÓN ESTILO CURL UNA LÍNEA"
        print_info "Simula descarga con curl y ejecución directa"
        print_warning "En producción, reemplace la URL con la ubicación real del script"
        echo
        read -p "URL del servidor Zabbix: " server_url
        read -p "Usuario API: " api_user
        read -s -p "Contraseña API: " api_password
        echo
        
        if [[ -z "$server_url" ]] || [[ -z "$api_user" ]] || [[ -z "$api_password" ]]; then
            print_error "Todos los campos son requeridos"
            exit 1
        fi
        
        print_info "Comando equivalente para curl:"
        echo
        echo "curl -fsSL https://raw.githubusercontent.com/user/repo/main/zabbix.sh | \\"
        echo "    sudo bash -s -- \\"
        echo "        --server-url '$server_url' \\"
        echo "        --api-user '$api_user' \\"
        echo "        --api-password '$api_password'"
        echo
        
        print_info "Ejecutando localmente..."
        sudo "$ZABBIX_SCRIPT" --server-url "$server_url" --api-user "$api_user" --api-password "$api_password"
        ;;
        
    3)
        print_section "INSTALACIÓN CON VARIABLES DE ENTORNO"
        print_warning "Este método es menos seguro pero aún soportado"
        
        read -p "URL del servidor Zabbix: " server_url
        read -p "Usuario API: " api_user
        read -s -p "Contraseña API: " api_password
        echo
        
        if [[ -z "$server_url" ]] || [[ -z "$api_user" ]] || [[ -z "$api_password" ]]; then
            print_error "Todos los campos son requeridos"
            exit 1
        fi
        
        export ZABBIX_SERVER_URL="$server_url"
        export ZABBIX_API_USER="$api_user"
        export ZABBIX_API_PASSWORD="$api_password"
        export DEBUG="true"
        
        print_info "Variables de entorno configuradas, ejecutando..."
        sudo -E "$ZABBIX_SCRIPT"
        ;;
        
    4)
        print_section "MODO DRY-RUN (SOLO VALIDACIONES)"
        print_info "Este modo solo ejecuta validaciones sin hacer cambios"
        
        print_info "Usando configuración de prueba..."
        sudo "$ZABBIX_SCRIPT" \
            --server-url "http://zabbix.ejemplo.com" \
            --api-user "test-user" \
            --api-password "test-password" \
            --dry-run
        ;;
        
    5)
        print_section "INSTALACIÓN FORZADA CON PARÁMETROS"
        print_warning "Esta opción reinstalará Zabbix aunque ya esté instalado"
        
        read -p "URL del servidor Zabbix: " server_url
        read -p "Usuario API: " api_user
        read -s -p "Contraseña API: " api_password
        echo
        
        if [[ -z "$server_url" ]] || [[ -z "$api_user" ]] || [[ -z "$api_password" ]]; then
            print_error "Todos los campos son requeridos"
            exit 1
        fi
        
        print_warning "ADVERTENCIA: Esto desinstalará cualquier instalación existente"
        read -p "¿Está seguro que desea continuar? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            sudo "$ZABBIX_SCRIPT" \
                --server-url "$server_url" \
                --api-user "$api_user" \
                --api-password "$api_password" \
                --force-reinstall \
                --debug
        else
            print_info "Instalación cancelada"
        fi
        ;;
        
    6)
        print_section "ACTUALIZAR HOST EXISTENTE CON PARÁMETROS"
        print_info "Esta opción actualiza un host que ya existe en Zabbix"
        
        read -p "URL del servidor Zabbix: " server_url
        read -p "Usuario API: " api_user
        read -s -p "Contraseña API: " api_password
        echo
        
        if [[ -z "$server_url" ]] || [[ -z "$api_user" ]] || [[ -z "$api_password" ]]; then
            print_error "Todos los campos son requeridos"
            exit 1
        fi
        
        print_info "Ejecutando actualización de host existente..."
        sudo "$ZABBIX_SCRIPT" \
            --server-url "$server_url" \
            --api-user "$api_user" \
            --api-password "$api_password" \
            --update-existing
        ;;
        
    7)
        print_section "CONFIGURACIÓN DE PRODUCCIÓN CON PARÁMETROS"
        print_info "Instalación con configuraciones recomendadas para producción"
        
        read -p "URL del servidor Zabbix (HTTPS recomendado): " server_url
        read -p "Usuario API: " api_user
        read -s -p "Contraseña API: " api_password
        echo
        read -p "Grupo de hosts (default: Production Servers): " host_group
        read -p "Puerto del agente (default: 10050): " agent_port
        
        # Valores por defecto
        host_group="${host_group:-Production Servers}"
        agent_port="${agent_port:-10050}"
        
        if [[ -z "$server_url" ]] || [[ -z "$api_user" ]] || [[ -z "$api_password" ]]; then
            print_error "URL, usuario y contraseña son requeridos"
            exit 1
        fi
        
        # Validar que sea HTTPS en producción
        if [[ ! "$server_url" =~ ^https:// ]]; then
            print_warning "Se recomienda usar HTTPS en entornos de producción"
            read -p "¿Continuar de todas formas? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                print_info "Instalación cancelada"
                exit 0
            fi
        fi
        
        print_info "Configuración de producción:"
        echo "  - Servidor: $server_url"
        echo "  - Grupo: $host_group"
        echo "  - Puerto: $agent_port"
        
        print_info "Comando completo:"
        echo "sudo $ZABBIX_SCRIPT --server-url '$server_url' --api-user '$api_user' --api-password '***' --host-group '$host_group' --agent-port '$agent_port'"
        echo
        
        read -p "¿Confirmar instalación? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            sudo "$ZABBIX_SCRIPT" \
                --server-url "$server_url" \
                --api-user "$api_user" \
                --api-password "$api_password" \
                --host-group "$host_group" \
                --agent-port "$agent_port"
        else
            print_info "Instalación cancelada"
        fi
        ;;
        
    8)
        print_section "AYUDA DEL INSTALADOR"
        "$ZABBIX_SCRIPT" --help
        ;;
        
    9)
        print_section "VERSIÓN DEL INSTALADOR"
        "$ZABBIX_SCRIPT" --version
        ;;
        
    10)
        print_info "Saliendo..."
        exit 0
        ;;
        
    *)
        print_error "Opción inválida: $option"
        exit 1
        ;;
esac

print_section "FINALIZADO"
print_info "Para más información, consulte el archivo README.md"