#!/bin/bash

# SSL Self-Signed Certificate Generation Script for OPCP-SwAutoMorph

set -e

# Load domain from deploy.ini or use default
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/conf/deploy.ini" ]; then
    DOMAIN_FROM_INI=$(grep -E '^DOMAIN=' "$SCRIPT_DIR/conf/deploy.ini" | cut -d'=' -f2 | xargs)
fi
DOMAIN=${DOMAIN:-${DOMAIN_FROM_INI:-"softfluid.fr"}}

SSL_DIR="$SCRIPT_DIR/ssl/$DOMAIN"

echo "🔐 Generating self-signed SSL certificates for $DOMAIN..."

# Create SSL directory
mkdir -p "$SSL_DIR"

# Check if certificates already exist
if [ -f "$SSL_DIR/fullchain_domain.crt" ] && [ -f "$SSL_DIR/privateKey_domain.key" ]; then
    echo "⚠️  SSL certificates already exist in $SSL_DIR"
    if [ "$1" != "--force" ]; then
        echo "   Use --force to regenerate."
        exit 0
    fi
    echo "🔄 Regenerating certificates..."
fi

# Generate private key
echo "🔑 Generating private key..."
openssl genrsa -out "$SSL_DIR/privateKey_domain.key" 2048

# Generate self-signed certificate (valid for 365 days) with SAN
echo "📜 Generating self-signed certificate..."
openssl req -new -x509 \
    -key "$SSL_DIR/privateKey_domain.key" \
    -out "$SSL_DIR/fullchain_domain.crt" \
    -days 365 \
    -subj "/C=FR/ST=France/L=Paris/O=SoftFluid/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,DNS:www.$DOMAIN"

# Set proper permissions
chmod 600 "$SSL_DIR/privateKey_domain.key"
chmod 644 "$SSL_DIR/fullchain_domain.crt"

echo ""
echo "✅ SSL certificates generated successfully!"
echo "📁 Certificate files:"
echo "   Certificate: $SSL_DIR/fullchain_domain.crt"
echo "   Private Key: $SSL_DIR/privateKey_domain.key"
echo ""
echo "⚠️  This is a self-signed certificate for development/testing."
echo "   Browsers will show a security warning."
echo "   For production, use Let's Encrypt: ./scripts/setup_letsencrypt.sh"
