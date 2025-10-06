# Instalador Automático de Agente Zabbix

Este script bash instala y configura automáticamente el agente Zabbix en sistemas Linux y lo registra en un servidor Zabbix usando la API.

## 🚀 Características

- **Instalación automática** en múltiples distribuciones Linux
- **Detección automática** del sistema operativo y versión
- **Registro automático** del host en Zabbix via API
- **Validación de hosts existentes** por IP
- **Configuración automática** del firewall
- **Rollback automático** en caso de errores
- **Logging completo** de todas las operaciones
- **Modo dry-run** para validaciones sin cambios

## 📋 Distribuciones Soportadas

| Distribución | Versiones Soportadas |
|-------------|---------------------|
| Ubuntu | 18.04, 20.04, 22.04, 24.04 |
| Debian | 9, 10, 11, 12 |
| CentOS | 7, 8, 9 |
| RHEL | 7, 8, 9 |
| Rocky Linux | 8, 9 |
| AlmaLinux | 8, 9 |

## ⚙️ Requisitos Previos

1. **Sistema Linux** con una de las distribuciones soportadas
2. **Privilegios de root** o acceso sudo
3. **Conectividad de red** al servidor Zabbix
4. **Servidor Zabbix** funcional con API habilitada
5. **Credenciales de API** con permisos para crear/modificar hosts

### Dependencias del Sistema

El script verificará e instalará automáticamente las siguientes dependencias:

- `curl`
- `wget` 
- `systemctl`
- `nc` (netcat) - opcional para validaciones de red

## 🔧 Instalación y Uso

### 1. Método Recomendado: Descarga y Ejecución con curl

El método más seguro y conveniente es descargar y ejecutar el script en una sola línea usando parámetros:

```bash
# Instalación básica con curl
curl -fsSL https://raw.githubusercontent.com/tu-usuario/zabbix-installer/main/zabbix.sh | \
    sudo bash -s -- \
        --server-url "http://tu-servidor-zabbix.com" \
        --api-user "admin" \
        --api-password "tu-password"

# Instalación con configuración personalizada
curl -fsSL https://raw.githubusercontent.com/tu-usuario/zabbix-installer/main/zabbix.sh | \
    sudo bash -s -- \
        --server-url "https://monitoring.empresa.com" \
        --api-user "api-user" \
        --api-password "password-seguro" \
        --host-group "Servidores Producción" \
        --force-reinstall \
        --debug

# Solo validaciones (dry-run)
curl -fsSL https://raw.githubusercontent.com/tu-usuario/zabbix-installer/main/zabbix.sh | \
    sudo bash -s -- \
        --server-url "http://zabbix.test.com" \
        --api-user "test" \
        --api-password "test" \
        --dry-run
```

### 2. Descarga Manual y Ejecución

```bash
# Clonar desde GitHub
git clone https://github.com/tu-usuario/zabbix-installer.git
cd zabbix-installer

# O descargar directamente
wget https://raw.githubusercontent.com/tu-usuario/zabbix-installer/main/zabbix.sh
chmod +x zabbix.sh
```

### 3. Configurar Parámetros

#### Usando Parámetros de Línea de Comandos (RECOMENDADO)

```bash
# Instalación básica con parámetros
sudo ./zabbix.sh \
    --server-url "http://zabbix.empresa.com" \
    --api-user "admin" \
    --api-password "mi-password"

# Con todas las opciones
sudo ./zabbix.sh \
    --server-url "https://monitoring.empresa.com" \
    --api-user "api-user" \
    --api-password "password-seguro" \
    --host-group "Servidores Linux" \
    --server-port "10051" \
    --agent-port "10050" \
    --force-reinstall \
    --debug
```

#### Usando Variables de Entorno (Método Alternativo)

```bash
export ZABBIX_SERVER_URL="http://tu-servidor-zabbix.com"
export ZABBIX_API_USER="admin"
export ZABBIX_API_PASSWORD="tu-password"
export ZABBIX_HOST_GROUP="Linux servers"        # Opcional
export FORCE_REINSTALL="false"                  # Opcional
export UPDATE_EXISTING_HOST="false"             # Opcional
export DEBUG="false"                            # Opcional

sudo -E ./zabbix.sh
```

## 📖 Ejemplos de Uso

### Ejemplo 1: Instalación Rápida con curl (Una línea)

```bash
# Instalación inmediata desde GitHub
curl -fsSL https://raw.githubusercontent.com/user/repo/main/zabbix.sh | \
    sudo bash -s -- \
        --server-url "http://zabbix.empresa.com" \
        --api-user "admin" \
        --api-password "zabbix123"
```

### Ejemplo 2: Instalación de Producción con HTTPS

```bash
# Instalación segura para producción
curl -fsSL https://raw.githubusercontent.com/user/repo/main/zabbix.sh | \
    sudo bash -s -- \
        --server-url "https://monitoring.empresa.com" \
        --api-user "production-api" \
        --api-password "password-complejo-seguro" \
        --host-group "Servidores Producción" \
        --agent-port "10050"
```

### Ejemplo 3: Instalación Local con Parámetros

```bash
# Descarga y ejecución local
wget https://raw.githubusercontent.com/user/repo/main/zabbix.sh
chmod +x zabbix.sh

sudo ./zabbix.sh \
    --server-url "http://zabbix.local" \
    --api-user "admin" \
    --api-password "admin" \
    --host-group "Test Servers" \
    --debug
```

### Ejemplo 4: Validación sin Instalación (Dry-run)

```bash
# Solo validar configuración sin instalar
curl -fsSL https://raw.githubusercontent.com/user/repo/main/zabbix.sh | \
    sudo bash -s -- \
        --server-url "http://test.zabbix.com" \
        --api-user "test-user" \
        --api-password "test-pass" \
        --dry-run
```

### Ejemplo 5: Forzar Reinstalación

```bash
# Reinstalar completamente
curl -fsSL https://raw.githubusercontent.com/user/repo/main/zabbix.sh | \
    sudo bash -s -- \
        --server-url "http://zabbix.empresa.com" \
        --api-user "admin" \
        --api-password "admin" \
        --force-reinstall
```

### Ejemplo 6: Actualizar Host Existente

```bash
# Actualizar configuración de host existente
sudo ./zabbix.sh \
    --server-url "http://zabbix.local" \
    --api-user "admin" \
    --api-password "admin" \
    --update-existing
```

### Ejemplo 7: Usando Variables de Entorno (Método Alternativo)

```bash
#!/bin/bash
export ZABBIX_SERVER_URL="http://zabbix.empresa.com"
export ZABBIX_API_USER="admin"
export ZABBIX_API_PASSWORD="password"
export ZABBIX_HOST_GROUP="Servidores Linux"
export DEBUG="true"

curl -fsSL https://raw.githubusercontent.com/user/repo/main/zabbix.sh | sudo -E bash
```

## 🔍 Validaciones del Script

El script realiza múltiples validaciones antes y durante la instalación:

### Validaciones Iniciales
- ✅ Verificación de privilegios de root
- ✅ Validación de variables de entorno requeridas
- ✅ Verificación de comandos necesarios
- ✅ Detección de distribución y versión
- ✅ Conectividad de red con servidor Zabbix

### Validaciones de Instalación
- ✅ Verificación de instalación existente
- ✅ Validación de repositorios de Zabbix
- ✅ Verificación de instalación de paquetes
- ✅ Validación de configuración del agente

### Validaciones Finales
- ✅ Estado del servicio zabbix-agent
- ✅ Conectividad del puerto del agente
- ✅ Verificación de logs de errores
- ✅ Registro exitoso en servidor Zabbix

## 📁 Archivos Generados

Durante la ejecución, el script genera los siguientes archivos:

```
/tmp/zabbix_install_YYYYMMDD_HHMMSS.log     # Log completo de instalación
/tmp/zabbix_backup_YYYYMMDD_HHMMSS/         # Backup de configuraciones
/etc/zabbix/zabbix_agentd.conf              # Configuración del agente
/var/log/zabbix/zabbix_agentd.log           # Logs del agente Zabbix
```

## 🔧 Configuración del Agente

El script configura automáticamente los siguientes parámetros:

```ini
Server=tu-servidor-zabbix
ServerActive=tu-servidor-zabbix:10051
Hostname=hostname-del-sistema
ListenPort=10050
ListenIP=0.0.0.0
StartAgents=3
RefreshActiveChecks=60
BufferSend=5
BufferSize=100
Timeout=3
EnableRemoteCommands=0
LogRemoteCommands=0
HostMetadata=Linux distribucion version arquitectura
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=10
```

## 🛠️ Resolución de Problemas

### Error: "No se puede conectar a la API de Zabbix"

**Posibles causas:**
- URL del servidor incorrecta
- Servidor Zabbix no accesible
- Firewall bloqueando conexión

**Soluciones:**
```bash
# Verificar conectividad
curl -s http://tu-servidor-zabbix/api_jsonrpc.php

# Verificar DNS
nslookup tu-servidor-zabbix

# Verificar firewall
sudo ufw status  # Ubuntu/Debian
sudo firewall-cmd --list-all  # CentOS/RHEL
```

### Error: "Error en autenticación con Zabbix"

**Posibles causas:**
- Credenciales incorrectas
- Usuario sin permisos API
- API deshabilitada en Zabbix

**Soluciones:**
- Verificar credenciales en interfaz web
- Verificar permisos del usuario API
- Habilitar API en configuración de Zabbix

### Error: "Puerto 10050 no está abierto"

**Posibles causas:**
- Servicio zabbix-agent no iniciado
- Firewall bloqueando puerto
- Configuración incorrecta

**Soluciones:**
```bash
# Verificar servicio
sudo systemctl status zabbix-agent

# Verificar puerto
sudo netstat -tlnp | grep 10050

# Configurar firewall
sudo ufw allow 10050/tcp  # Ubuntu/Debian
sudo firewall-cmd --permanent --add-port=10050/tcp  # CentOS/RHEL
```

### Error: "Host ya existe en Zabbix"

**Solución:**
```bash
# Actualizar host existente
export UPDATE_EXISTING_HOST="true"
sudo ./zabbix.sh
```

## 🔐 Consideraciones de Seguridad

1. **Credenciales**: No hardcodear credenciales en scripts de producción
2. **Permisos**: Usar usuario API con permisos mínimos necesarios
3. **HTTPS**: Usar HTTPS para conexiones al servidor Zabbix
4. **Firewall**: Configurar reglas de firewall específicas
5. **Logs**: Proteger archivos de log que pueden contener información sensible

### Ejemplo de Variables de Entorno Seguras

```bash
# Usar archivo de configuración
echo 'export ZABBIX_SERVER_URL="https://zabbix.empresa.com"' > ~/.zabbix_config
echo 'export ZABBIX_API_USER="api-user"' >> ~/.zabbix_config
echo 'export ZABBIX_API_PASSWORD="password-seguro"' >> ~/.zabbix_config
chmod 600 ~/.zabbix_config

# Cargar configuración
source ~/.zabbix_config
sudo -E ./zabbix.sh
```

## 📝 Contribuir

1. Fork el repositorio
2. Crear rama para feature (`git checkout -b feature/nueva-funcionalidad`)
3. Commit cambios (`git commit -am 'Agregar nueva funcionalidad'`)
4. Push a la rama (`git push origin feature/nueva-funcionalidad`)
5. Crear Pull Request

## 📄 Licencia

Este proyecto está bajo la Licencia MIT. Ver el archivo `LICENSE` para más detalles.

## 🆘 Soporte

- **Issues**: Reportar problemas en GitHub Issues
- **Documentación**: Wiki del proyecto
- **Discusiones**: GitHub Discussions

## 📊 Changelog

### v1.0.0 (2024-10-06)
- Instalación automática en múltiples distribuciones
- API de Zabbix para registro de hosts
- Validación de hosts existentes
- Configuración automática de firewall
- Sistema de rollback automático
- Logging completo
- Modo dry-run

---

**Nota**: Este script está diseñado para Zabbix 7.0. Para versiones anteriores, puede requerir modificaciones en las URLs de repositorios.