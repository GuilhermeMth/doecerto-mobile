FROM node:20-alpine AS builder

# Metadados
LABEL maintainer="DoeCerto Team"
LABEL stage="builder"

# Instalamos apenas o essencial para o Prisma e pacotes nativos
RUN apk add --no-cache libc6-compat openssl python3 make g++

WORKDIR /app

# Copiar arquivos de dependências primeiro (melhor cache)
COPY package*.json ./
COPY prisma ./prisma/

# Instalação limpa das dependências (incluindo devDependencies)
RUN npm ci

COPY . .

# Gera o Prisma Client (essencial antes do build)
RUN npx prisma generate

# Build da aplicação
RUN npm run build

# Remove dependências de dev para economizar espaço
RUN npm prune --omit=dev && \
    npm cache clean --force

# ----------------
# Stage 2: Production
# ----------------
FROM node:20-alpine AS production

# Metadados da imagem
LABEL maintainer="DoeCerto Team"
LABEL version="1.0.0"
LABEL description="DoeCerto API - Backend para plataforma de doações"

# Dependências de sistema para o Prisma rodar em Alpine
RUN apk add --no-cache \
    dumb-init \
    curl \
    openssl \
    libc6-compat \
    tzdata

# Configuração de segurança (Non-root)
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app

# Pastas de uploads com permissões corretas
RUN mkdir -p /app/uploads/profiles /app/uploads/payment-proofs /app/logs && \
    chown -R nodejs:nodejs /app/uploads /app/logs

# Copiar apenas o estritamente necessário
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --from=builder --chown=nodejs:nodejs /app/prisma ./prisma
COPY --from=builder --chown=nodejs:nodejs /app/package*.json ./

# Script de entrada
COPY --chown=nodejs:nodejs docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Variáveis de ambiente com valores padrão
ENV NODE_ENV=production \
    PORT=3000 \
    TZ=America/Sao_Paulo \
    NODE_OPTIONS="--max-old-space-size=2048"

# Trocar para usuário não-root
USER nodejs

# Expor porta
EXPOSE 3000

# Health check para verificar se a API está respondendo
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Usar dumb-init para gerenciamento de processos
ENTRYPOINT ["dumb-init", "--"]
CMD ["docker-entrypoint.sh"]