#!/bin/bash

#################################################################################
#                          SCRIPT DE PRUEBAS                                   #
#                      Instalador de Agente Zabbix                             #
#################################################################################
# Este script ejecuta pruebas básicas del instalador de Zabbix                 #
#################################################################################

# Configuración de pruebas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZABBIX_SCRIPT="$SCRIPT_DIR/zabbix.sh"
LOG_FILE="/tmp/zabbix_test_$(date +%Y%m%d_%H%M%S).log"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Contadores
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo "[$1] $2" | tee -a "$LOG_FILE"
}

test_passed() {
    ((TESTS_PASSED++))
    log_test "$(date)" "PASS: $1"
    echo -e "${GREEN}✓ PASS:${NC} $1"
}

test_failed() {
    ((TESTS_FAILED++))
    log_test "$(date)" "FAIL: $1"
    echo -e "${RED}✗ FAIL:${NC} $1"
}

run_test() {
    ((TESTS_TOTAL++))
    local test_name="$1"
    local test_command="$2"
    
    echo -e "\n${BLUE}Ejecutando:${NC} $test_name"
    
    if eval "$test_command" &>/dev/null; then
        test_passed "$test_name"
    else
        test_failed "$test_name"
    fi
}

echo "=== PRUEBAS DEL INSTALADOR ZABBIX ==="
echo "Archivo de pruebas: $LOG_FILE"
echo

# Verificar que el script existe
if [[ ! -f "$ZABBIX_SCRIPT" ]]; then
    echo -e "${RED}ERROR:${NC} Script zabbix.sh no encontrado en $ZABBIX_SCRIPT"
    exit 1
fi

# Hacer el script ejecutable
chmod +x "$ZABBIX_SCRIPT" 2>/dev/null

echo "=== PRUEBAS BÁSICAS ==="

# Test 1: Verificar que el script tiene sintaxis válida
run_test "Sintaxis de script válida" "bash -n '$ZABBIX_SCRIPT'"

# Test 2: Verificar que muestra ayuda
run_test "Mostrar ayuda" "'$ZABBIX_SCRIPT' --help"

# Test 3: Verificar que muestra versión
run_test "Mostrar versión" "'$ZABBIX_SCRIPT' --version"

# Test 4: Verificar que detecta falta de permisos root (solo si no es root)
if [[ $EUID -ne 0 ]]; then
    run_test "Detectar falta de permisos root" "! '$ZABBIX_SCRIPT' 2>/dev/null"
fi

echo -e "\n=== PRUEBAS DE VALIDACIÓN ==="

# Test 5: Verificar validación de variables de entorno
run_test "Validar variables de entorno faltantes" "! sudo '$ZABBIX_SCRIPT' --dry-run 2>/dev/null"

# Test 6: Verificar dry-run con configuración mínima
export ZABBIX_SERVER_URL="http://test.local"
export ZABBIX_API_USER="test"
export ZABBIX_API_PASSWORD="test"

if [[ $EUID -eq 0 ]]; then
    run_test "Dry-run con configuración básica" "'$ZABBIX_SCRIPT' --dry-run"
else
    run_test "Dry-run con configuración básica" "sudo -E '$ZABBIX_SCRIPT' --dry-run"
fi

echo -e "\n=== PRUEBAS DE DEPENDENCIAS ==="

# Test 7: Verificar dependencias del sistema
dependencies=("curl" "wget" "systemctl")
for dep in "${dependencies[@]}"; do
    run_test "Dependencia disponible: $dep" "command -v $dep"
done

echo -e "\n=== PRUEBAS DE DISTRIBUCIÓN ==="

# Test 8: Verificar detección de distribución
if [[ -f /etc/os-release ]]; then
    run_test "Archivo /etc/os-release existe" "test -f /etc/os-release"
    run_test "ID de distribución disponible" "grep -q '^ID=' /etc/os-release"
fi

# Test 9: Verificar detección de versión
if [[ -f /etc/os-release ]]; then
    run_test "Versión de distribución disponible" "grep -q 'VERSION' /etc/os-release"
fi

echo -e "\n=== PRUEBAS DE RED ==="

# Test 10: Verificar conectividad básica
run_test "Conectividad a internet" "ping -c 1 8.8.8.8"

# Test 11: Verificar herramientas de red
run_test "Netcat disponible" "command -v nc || command -v netcat"

echo -e "\n=== PRUEBAS DE PERMISOS ==="

# Test 12: Verificar permisos de directorio /tmp
run_test "Directorio /tmp escribible" "test -w /tmp"

# Test 13: Verificar permisos de directorio /etc
if [[ $EUID -eq 0 ]]; then
    run_test "Directorio /etc escribible (como root)" "test -w /etc"
fi

echo -e "\n=== PRUEBAS DE FUNCIONES INTERNAS ==="

# Test 14: Verificar funciones principales del script
if [[ $EUID -eq 0 ]]; then
    # Source del script para probar funciones internas
    export -f test_passed test_failed
    
    # Test básico de funciones de logging
    run_test "Funciones de logging disponibles" "source '$ZABBIX_SCRIPT' && declare -f log_info >/dev/null"
fi

echo -e "\n=== RESUMEN DE PRUEBAS ==="
echo "Total de pruebas: $TESTS_TOTAL"
echo -e "Pruebas exitosas: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Pruebas fallidas: ${RED}$TESTS_FAILED${NC}"

# Calcular porcentaje de éxito
if [[ $TESTS_TOTAL -gt 0 ]]; then
    SUCCESS_RATE=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    echo "Tasa de éxito: $SUCCESS_RATE%"
    
    if [[ $SUCCESS_RATE -ge 80 ]]; then
        echo -e "${GREEN}Estado: BUENO${NC} - El script está listo para usar"
        exit_code=0
    elif [[ $SUCCESS_RATE -ge 60 ]]; then
        echo -e "${YELLOW}Estado: ACEPTABLE${NC} - Algunas funciones pueden no estar disponibles"
        exit_code=1
    else
        echo -e "${RED}Estado: PROBLEMÁTICO${NC} - Revise los errores antes de usar"
        exit_code=2
    fi
else
    echo -e "${RED}Estado: ERROR${NC} - No se pudieron ejecutar pruebas"
    exit_code=3
fi

echo "Log de pruebas guardado en: $LOG_FILE"

exit $exit_code