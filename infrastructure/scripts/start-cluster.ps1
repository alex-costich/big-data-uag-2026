# =============================================================================
# Script para iniciar el cluster de Big Data (Windows PowerShell)
# Big Data UAG 2026 - AWS Academy Data Engineering
# =============================================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("spark", "kafka", "full", "help")]
    [string]$Option = "spark"
)

# Colores para output
$ErrorActionPreference = "Stop"

function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Show-Usage {
    Write-Host "Uso: .\start-cluster.ps1 [opcion]"
    Write-Host ""
    Write-Host "Opciones:"
    Write-Host "  spark     - Iniciar solo Spark + Jupyter"
    Write-Host "  kafka     - Iniciar solo Kafka"
    Write-Host "  full      - Iniciar todo (Spark + Kafka + DBs)"
    Write-Host "  help      - Mostrar esta ayuda"
    Write-Host ""
    Write-Host "Ejemplo: .\start-cluster.ps1 spark"
}

# Verificar Docker
function Test-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error "Docker no esta instalado"
        exit 1
    }

    try {
        docker info | Out-Null
    } catch {
        Write-Error "Docker daemon no esta corriendo"
        Write-Host "Por favor, inicia Docker Desktop desde el menu de inicio" -ForegroundColor Yellow
        exit 1
    }

    Write-Success "Docker esta disponible"
}

# Iniciar cluster Spark
function Start-Spark {
    Write-Status "Iniciando cluster Spark..."
    
    $scriptPath = Split-Path -Parent $MyInvocation.PSCommandPath
    $infraDir = Split-Path -Parent $scriptPath
    Set-Location $infraDir
    
    docker compose -f docker-compose.spark.yml up -d --build

    Write-Status "Esperando a que los servicios esten listos..."
    Start-Sleep -Seconds 10

    Write-Host ""
    Write-Success "Cluster Spark iniciado!"
    Write-Host ""
    Write-Host "  Spark Master UI:  http://localhost:8080"
    Write-Host "  Spark Worker UI:  http://localhost:8081"
    Write-Host "  Jupyter Lab:      http://localhost:8888"
    Write-Host "  Spark App UI:     http://localhost:4040 (cuando hay una app corriendo)"
    Write-Host ""
}

# Iniciar Kafka
function Start-Kafka {
    Write-Status "Iniciando Kafka..."
    
    $scriptPath = Split-Path -Parent $MyInvocation.PSCommandPath
    $infraDir = Split-Path -Parent $scriptPath
    Set-Location $infraDir
    
    docker compose -f docker-compose.kafka.yml up -d

    Write-Status "Esperando a que los servicios esten listos..."
    Start-Sleep -Seconds 15

    Write-Host ""
    Write-Success "Kafka iniciado!"
    Write-Host ""
    Write-Host "  Kafka Broker:     localhost:9092"
    Write-Host "  Kafka UI:         http://localhost:9000"
    Write-Host "  Schema Registry:  http://localhost:8081"
    Write-Host "  Zookeeper:        localhost:2181"
    Write-Host ""
}

# Iniciar full stack
function Start-FullStack {
    Write-Status "Iniciando Full Stack (Spark + Kafka + DBs)..."
    
    $scriptPath = Split-Path -Parent $MyInvocation.PSCommandPath
    $infraDir = Split-Path -Parent $scriptPath
    Set-Location $infraDir
    
    docker compose -f docker-compose.full-stack.yml up -d --build

    Write-Status "Esperando a que los servicios esten listos..."
    Start-Sleep -Seconds 20

    Write-Host ""
    Write-Success "Full Stack iniciado!"
    Write-Host ""
    Write-Host "  === SPARK ==="
    Write-Host "  Spark Master UI:  http://localhost:8080"
    Write-Host "  Spark Worker UI:  http://localhost:8081"
    Write-Host "  Jupyter Lab:      http://localhost:8888"
    Write-Host ""
    Write-Host "  === KAFKA ==="
    Write-Host "  Kafka Broker:     localhost:9092"
    Write-Host "  Kafka UI:         http://localhost:9000"
    Write-Host ""
    Write-Host "  === DATABASES ==="
    Write-Host "  PostgreSQL:       localhost:5432 (user: bigdata, pass: bigdata123)"
    Write-Host "  Redis:            localhost:6379"
    Write-Host "  MinIO Console:    http://localhost:9001 (user: minioadmin, pass: minioadmin123)"
    Write-Host ""
}

# Main
Write-Host ""
Write-Host "=========================================="
Write-Host "  Big Data UAG 2026 - Cluster Manager"
Write-Host "=========================================="
Write-Host ""

Test-Docker

switch ($Option) {
    "spark" {
        Start-Spark
    }
    "kafka" {
        Start-Kafka
    }
    "full" {
        Start-FullStack
    }
    "help" {
        Show-Usage
    }
    default {
        Write-Error "Opcion no reconocida: $Option"
        Show-Usage
        exit 1
    }
}
