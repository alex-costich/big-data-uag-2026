# =============================================================================
# Script para detener el cluster de Big Data (Windows PowerShell)
# Big Data UAG 2026 - AWS Academy Data Engineering
# =============================================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("spark", "kafka", "full", "all", "clean", "help")]
    [string]$Option = "all"
)

$ErrorActionPreference = "Continue"

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

function Show-Usage {
    Write-Host "Uso: .\stop-cluster.ps1 [opcion]"
    Write-Host ""
    Write-Host "Opciones:"
    Write-Host "  spark     - Detener solo Spark + Jupyter"
    Write-Host "  kafka     - Detener solo Kafka"
    Write-Host "  full      - Detener todo"
    Write-Host "  all       - Detener todos los stacks"
    Write-Host "  clean     - Detener todo y eliminar volumenes"
    Write-Host "  help      - Mostrar esta ayuda"
    Write-Host ""
    Write-Host "Ejemplo: .\stop-cluster.ps1 spark"
}

# Detener Spark
function Stop-Spark {
    Write-Status "Deteniendo cluster Spark..."
    
    $scriptPath = Split-Path -Parent $MyInvocation.PSCommandPath
    $infraDir = Split-Path -Parent $scriptPath
    Set-Location $infraDir
    
    docker compose -f docker-compose.spark.yml down 2>$null
    Write-Success "Cluster Spark detenido"
}

# Detener Kafka
function Stop-Kafka {
    Write-Status "Deteniendo Kafka..."
    
    $scriptPath = Split-Path -Parent $MyInvocation.PSCommandPath
    $infraDir = Split-Path -Parent $scriptPath
    Set-Location $infraDir
    
    docker compose -f docker-compose.kafka.yml down 2>$null
    Write-Success "Kafka detenido"
}

# Detener Full Stack
function Stop-FullStack {
    Write-Status "Deteniendo Full Stack..."
    
    $scriptPath = Split-Path -Parent $MyInvocation.PSCommandPath
    $infraDir = Split-Path -Parent $scriptPath
    Set-Location $infraDir
    
    docker compose -f docker-compose.full-stack.yml down 2>$null
    Write-Success "Full Stack detenido"
}

# Detener todo
function Stop-All {
    Write-Status "Deteniendo todos los servicios..."
    
    $scriptPath = Split-Path -Parent $MyInvocation.PSCommandPath
    $infraDir = Split-Path -Parent $scriptPath
    Set-Location $infraDir
    
    docker compose -f docker-compose.spark.yml down 2>$null
    docker compose -f docker-compose.kafka.yml down 2>$null
    docker compose -f docker-compose.full-stack.yml down 2>$null
    
    Write-Success "Todos los servicios detenidos"
}

# Limpieza completa
function Clear-All {
    Write-Warning "Esto eliminara todos los contenedores y volumenes..."
    $confirm = Read-Host "Continuar? (y/N)"
    
    if ($confirm -match "^[Yy]$") {
        Write-Status "Deteniendo y limpiando..."
        
        $scriptPath = Split-Path -Parent $MyInvocation.PSCommandPath
        $infraDir = Split-Path -Parent $scriptPath
        Set-Location $infraDir
        
        docker compose -f docker-compose.spark.yml down -v 2>$null
        docker compose -f docker-compose.kafka.yml down -v 2>$null
        docker compose -f docker-compose.full-stack.yml down -v 2>$null
        
        # Eliminar volumenes huerfanos
        docker volume prune -f 2>$null
        
        Write-Success "Limpieza completa realizada"
    } else {
        Write-Status "Operacion cancelada"
    }
}

# Main
Write-Host ""
Write-Host "=========================================="
Write-Host "  Big Data UAG 2026 - Stop Cluster"
Write-Host "=========================================="
Write-Host ""

switch ($Option) {
    "spark" {
        Stop-Spark
    }
    "kafka" {
        Stop-Kafka
    }
    "full" {
        Stop-FullStack
    }
    "all" {
        Stop-All
    }
    "clean" {
        Clear-All
    }
    "help" {
        Show-Usage
    }
    default {
        Write-Warning "Opcion no reconocida: $Option"
        Show-Usage
        exit 1
    }
}

Write-Host ""
