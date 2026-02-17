# Módulo 00: Configuración del Entorno

## Descripción

Este módulo te guiará para configurar tu entorno de desarrollo de Big Data. Al finalizar, tendrás un cluster de Spark funcionando con Jupyter Lab.

## Prerequisitos

- Docker Desktop instalado
- 8GB RAM mínimo disponible
- Conexión a internet

## Contenido

| Notebook | Descripción | Tiempo |
|----------|-------------|--------|
| `01_environment_check.ipynb` | Verificar que todo funciona | 15 min |
| `02_spark_basics.ipynb` | Primeros pasos con Spark | 30 min |

## Instrucciones de Instalación

### 1. Instalar Docker

**macOS:**
```bash
brew install --cask docker
```

**Windows/Linux:**
Descargar de https://www.docker.com/products/docker-desktop

### 2. Verificar Docker

**macOS/Linux/Windows:**
```bash
docker --version
docker compose version
```

**Nota para Windows:** Si recibes un error de ejecución de scripts en PowerShell, ejecuta:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
Esto permite ejecutar scripts locales en PowerShell.

### 3. Iniciar el Cluster

**macOS/Linux:**
```bash
cd big-data-uag-2026
./infrastructure/scripts/start-cluster.sh spark
```

**Windows (PowerShell):**
```powershell
cd big-data-uag-2026
.\infrastructure\scripts\start-cluster.ps1 spark
```

**Windows (Command Prompt):**
```cmd
cd big-data-uag-2026
powershell -ExecutionPolicy Bypass -File .\infrastructure\scripts\start-cluster.ps1 spark
```

**Alternativa directa con Docker Compose (todas las plataformas):**
```bash
cd big-data-uag-2026
cd infrastructure
docker compose -f docker-compose.spark.yml up -d --build
```

### 4. Acceder a Jupyter

Abrir http://localhost:8888 en el navegador.

### 5. Verificar Servicios

| Servicio | URL |
|----------|-----|
| Jupyter Lab | http://localhost:8888 |
| Spark Master | http://localhost:8080 |
| Spark Worker | http://localhost:8081 |

## Solución de Problemas

### "Puerto en uso"

**macOS/Linux:**
```bash
# Detener servicios existentes
./infrastructure/scripts/stop-cluster.sh

# Verificar puertos
lsof -i :8888
lsof -i :8080
```

**Windows:**
```powershell
# Detener servicios existentes
.\infrastructure\scripts\stop-cluster.ps1

# Verificar puertos (PowerShell)
netstat -ano | findstr :8888
netstat -ano | findstr :8080
```

**Alternativa directa con Docker Compose:**
```bash
cd infrastructure
docker compose -f docker-compose.spark.yml down
```

### "No hay memoria suficiente"

1. Abrir Docker Desktop
2. Settings → Resources
3. Aumentar memoria a 8GB mínimo

### "Contenedor no inicia"

**macOS/Linux:**
```bash
# Ver logs
docker compose -f infrastructure/docker-compose.spark.yml logs

# Reiniciar
./infrastructure/scripts/stop-cluster.sh
./infrastructure/scripts/start-cluster.sh spark
```

**Windows:**
```powershell
# Ver logs
docker compose -f infrastructure\docker-compose.spark.yml logs

# Reiniciar
.\infrastructure\scripts\stop-cluster.ps1
.\infrastructure\scripts\start-cluster.ps1 spark
```

**Alternativa directa con Docker Compose:**
```bash
cd infrastructure
docker compose -f docker-compose.spark.yml logs
docker compose -f docker-compose.spark.yml down
docker compose -f docker-compose.spark.yml up -d --build
```

## Siguiente Paso

Una vez verificado el entorno, continúa con `01_environment_check.ipynb`.
