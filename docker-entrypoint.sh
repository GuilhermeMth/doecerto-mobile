#!/bin/sh
set -e

# ===============================================
# 🎁 DoeCerto API - Docker Entrypoint Script
# ===============================================

# Cores para output (opcional, remove se não suportar)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções de log
log_info() {
    echo "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo "${RED}❌ $1${NC}"
}

# ===============================================
# 1️⃣ Inicialização
# ===============================================

log_info "Starting DoeCerto API..."
log_info "Environment: $NODE_ENV"
log_info "Port: $PORT"
log_info "Timezone: $TZ"

# ===============================================
# 2️⃣ Tratamento de Sinais (Graceful Shutdown)
# ===============================================

handle_signal() {
    log_warning "Received shutdown signal. Shutting down gracefully..."
    
    # Dar tempo para conexões finalizarem
    sleep 2
    
    # Enviar SIGTERM para o processo filho
    if [ ! -z "$APP_PID" ]; then
        kill -TERM "$APP_PID" 2>/dev/null || true
        
        # Aguardar até 30 segundos para graceful shutdown
        TIMEOUT=30
        while kill -0 "$APP_PID" 2>/dev/null && [ $TIMEOUT -gt 0 ]; do
            sleep 1
            TIMEOUT=$((TIMEOUT - 1))
        done
        
        # Forçar encerramento se não desligou
        if kill -0 "$APP_PID" 2>/dev/null; then
            log_warning "Forcing shutdown..."
            kill -9 "$APP_PID" 2>/dev/null || true
        fi
    fi
    
    log_success "Application stopped"
    exit 0
}

# Registrar tratadores de sinais
trap handle_signal SIGTERM SIGINT EXIT

# ===============================================
# 3️⃣ Validações Iniciais
# ===============================================

log_info "Validating environment..."

# Verificar variáveis críticas
if [ -z "$DATABASE_URL" ]; then
    log_error "DATABASE_URL not set!"
    exit 1
fi

if [ -z "$NODE_ENV" ]; then
    log_warning "NODE_ENV not set, defaulting to production"
    export NODE_ENV=production
fi

if [ -z "$PORT" ]; then
    log_warning "PORT not set, defaulting to 3000"
    export PORT=3000
fi

log_success "Environment validation passed"

# ===============================================
# 4️⃣ Aguardar Banco de Dados
# ===============================================

log_info "Waiting for database to be ready..."

MAX_RETRIES=60
RETRY_COUNT=0
RETRY_DELAY=2

until npx prisma db push --skip-generate 2>/dev/null; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    if [ $RETRY_COUNT -gt $MAX_RETRIES ]; then
        log_error "Database connection failed after $MAX_RETRIES attempts (${RETRY_COUNT}s)"
        log_error "Check DATABASE_URL: $DATABASE_URL"
        exit 1
    fi
    
    ELAPSED=$((RETRY_COUNT * RETRY_DELAY))
    log_warning "Database unavailable - attempt $RETRY_COUNT/$MAX_RETRIES (${ELAPSED}s elapsed)"
    sleep $RETRY_DELAY
done

log_success "Database connection successful"

# ===============================================
# 5️⃣ Executar Migrations
# ===============================================

log_info "Running database migrations..."

if ! npx prisma migrate deploy 2>&1; then
    log_error "Migration failed!"
    log_warning "Attempting to resolve migration..."
    
    # Tentar resolver conflitos de migration
    if ! npx prisma migrate resolve --rolled-back 2>&1; then
        log_error "Could not resolve migration conflict"
        exit 1
    fi
    
    log_info "Migration conflict resolved, retrying..."
    if ! npx prisma migrate deploy 2>&1; then
        log_error "Migration still failed after resolution"
        exit 1
    fi
fi

log_success "Database migrations completed"

# ===============================================
# 6️⃣ Seed do Banco (Opcional)
# ===============================================

if [ "$RUN_SEED" = "true" ] || [ "$RUN_SEED" = "1" ]; then
    log_info "Seeding database..."
    
    if npx prisma db seed 2>&1; then
        log_success "Database seeded successfully"
    else
        log_warning "Seed failed or not configured"
        # Não falha o entrypoint se o seed falhar
    fi
fi

# ===============================================
# 7️⃣ Verificações de Arquivos
# ===============================================

log_info "Verifying application files..."

if [ ! -f "./dist/main.js" ]; then
    log_error "Application build not found at ./dist/main.js"
    exit 1
fi

if [ ! -d "./node_modules" ]; then
    log_error "node_modules directory not found"
    exit 1
fi

log_success "All files verified"

# ===============================================
# 8️⃣ Iniciar Aplicação
# ===============================================

log_info "=========================================="
log_success "DoeCerto API is starting..."
log_info "=========================================="

# Executar aplicação em background para capturar sinais
node dist/main.js &
APP_PID=$!

log_info "Application PID: $APP_PID"

# Aguardar o processo filho
wait $APP_PID
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    log_error "Application exited with code $EXIT_CODE"
fi

exit $EXIT_CODE