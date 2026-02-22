#!/bin/bash

echo "🚀 Inicializando recursos de LocalStack..."

# Crear un bucket S3 para almacenar archivos
echo "📦 Creando bucket S3: products-images"
awslocal s3 mb s3://products-images

# Crear una cola SQS para procesar pedidos
echo "📬 Creando cola SQS: orders-queue"
awslocal sqs create-queue --queue-name orders-queue

# Configurar SES (Simple Email Service)
echo "📧 Configurando SES..."

# Verificar emails para poder enviarlos (obligatorio en SES)
awslocal ses verify-email-identity \
    --email-address noreply@ecommerce.com

awslocal ses verify-email-identity \
    --email-address admin@ecommerce.com

# Crear template de email para confirmación de orden
awslocal ses create-template \
    --template '{
        "TemplateName": "OrderConfirmation",
        "SubjectPart": "Orden #{{orderId}} confirmada",
        "TextPart": "Hola {{name}}, tu orden #{{orderId}} ha sido confirmada. Total: ${{total}}",
        "HtmlPart": "<h1>Hola {{name}}!</h1><p>Tu orden <strong>#{{orderId}}</strong> ha sido confirmada.</p><p>Total: <strong>${{total}}</strong></p>"
    }'

# Crear template de email para bienvenida
awslocal ses create-template \
    --template '{
        "TemplateName": "WelcomeEmail",
        "SubjectPart": "Bienvenido a ECommerce, {{name}}!",
        "TextPart": "Hola {{name}}, gracias por registrarte en ECommerce.",
        "HtmlPart": "<h1>Bienvenido {{name}}!</h1><p>Gracias por registrarte en <strong>ECommerce</strong>.</p>"
    }'

# Crear template de email para recuperar contraseña
awslocal ses create-template \
    --template '{
        "TemplateName": "PasswordReset",
        "SubjectPart": "Recuperar contraseña",
        "TextPart": "Hola {{name}}, usa este enlace para recuperar tu contraseña: {{resetUrl}}",
        "HtmlPart": "<h1>Recuperar contraseña</h1><p>Hola {{name}},</p><p><a href=\"{{resetUrl}}\">Haz clic aquí</a> para resetear tu contraseña. Expira en 1 hora.</p>"
    }'

# Crear tablas DynamoDB
echo "💾 Creando tablas DynamoDB..."

# Tabla para sesiones de usuario
echo "💾 Creando tabla DynamoDB: user-sessions"
awslocal dynamodb create-table \
    --table-name user-sessions \
    --attribute-definitions \
        AttributeName=userId,AttributeType=S \
    --key-schema \
        AttributeName=userId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST

# Tabla para autenticaciones (usuarios registrados)
# Campos al insertar: email, name, password, userId, createdAt
echo "💾 Creando tabla DynamoDB: authentications"
awslocal dynamodb create-table \
    --table-name authentications \
    --attribute-definitions \
        AttributeName=email,AttributeType=S \
    --key-schema \
        AttributeName=email,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST

# Tabla para refresh tokens
# Campos al insertar: userId, token, expiresAt, createdAt
echo "💾 Creando tabla DynamoDB: auth-tokens"
awslocal dynamodb create-table \
    --table-name auth-tokens \
    --attribute-definitions \
        AttributeName=userId,AttributeType=S \
        AttributeName=token,AttributeType=S \
    --key-schema \
        AttributeName=userId,KeyType=HASH \
        AttributeName=token,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST

# Insertar datos de ejemplo en authentications
echo "📝 Insertando usuarios de ejemplo..."
awslocal dynamodb put-item \
    --table-name authentications \
    --item '{
        "email":     {"S": "victor@example.com"},
        "name":      {"S": "Victor"},
        "password":  {"S": "hashed-password-123"},
        "userId":    {"S": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"},
        "createdAt": {"S": "2024-01-01T00:00:00Z"}
    }'

awslocal dynamodb put-item \
    --table-name authentications \
    --item '{
        "email":     {"S": "admin@ecommerce.com"},
        "name":      {"S": "Admin"},
        "password":  {"S": "hashed-admin-password-456"},
        "userId":    {"S": "b2c3d4e5-f6a7-8901-bcde-f12345678901"},
        "createdAt": {"S": "2024-01-01T00:00:00Z"}
    }'

# Crear secretos en Secrets Manager
echo "🔐 Creando secretos en Secrets Manager..."

# Secreto para base de datos
awslocal secretsmanager create-secret \
    --name prod/database/credentials \
    --description "Credenciales de la base de datos de producción" \
    --secret-string '{
        "username": "admin",
        "password": "super-secret-password-123",
        "host": "localhost",
        "port": "5432",
        "database": "ordersdb"
    }'

# Secreto para Stripe
awslocal secretsmanager create-secret \
    --name prod/stripe/api-keys \
    --description "Claves API de Stripe" \
    --secret-string '{
        "apiKey": "sk_test_1234567890",
        "webhookSecret": "whsec_1234567890"
    }'

# Secreto para JWT
awslocal secretsmanager create-secret \
    --name prod/jwt/secret \
    --description "Clave secreta para JWT" \
    --secret-string '{
        "secret": "my-super-secret-jwt-key-change-in-production",
        "expiresIn": "7d"
    }'

# Secreto para AWS Credentials
awslocal secretsmanager create-secret \
    --name prod/aws/credentials \
    --description "Credenciales de AWS S3" \
    --secret-string '{
        "accessKeyId": "AKIAIOSFODNN7EXAMPLE",
        "secretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "region": "us-east-1"
    }'

# Crear Event Bus (EventBridge)
echo "📡 Creando Event Bus y reglas..."

# Crear regla para eventos de orden creada
awslocal events put-rule \
    --name order-created-rule \
    --event-pattern '{
        "source": ["orders.service"],
        "detail-type": ["OrderCreated"]
    }' \
    --description "Regla para eventos de orden creada"

# Crear regla para eventos de pago completado
awslocal events put-rule \
    --name payment-completed-rule \
    --event-pattern '{
        "source": ["payments.service"],
        "detail-type": ["PaymentCompleted"]
    }' \
    --description "Regla para eventos de pago completado"

# Crear regla para eventos de usuario registrado
awslocal events put-rule \
    --name user-registered-rule \
    --event-pattern '{
        "source": ["auth.service"],
        "detail-type": ["UserRegistered"]
    }' \
    --description "Regla para eventos de usuario registrado"

# Crear parámetros en Parameter Store (SSM)
echo "⚙️  Creando parámetros de configuración..."

# URLs de servicios
awslocal ssm put-parameter \
    --name "/app/api/base-url" \
    --value "http://localhost:5000" \
    --type "String" \
    --description "URL base del API Gateway"

# Feature Flags
awslocal ssm put-parameter \
    --name "/app/features/enable-notifications" \
    --value "true" \
    --type "String" \
    --description "Activar notificaciones por email"

awslocal ssm put-parameter \
    --name "/app/features/enable-analytics" \
    --value "false" \
    --type "String" \
    --description "Activar Google Analytics"

# Límites de negocio
awslocal ssm put-parameter \
    --name "/app/limits/max-items-per-order" \
    --value "50" \
    --type "String" \
    --description "Máximo de items por orden"

awslocal ssm put-parameter \
    --name "/app/limits/free-shipping-threshold" \
    --value "75.00" \
    --type "String" \
    --description "Monto mínimo para envío gratis"

# Configuraciones de terceros
awslocal ssm put-parameter \
    --name "/app/email/sender-address" \
    --value "noreply@ecommerce.com" \
    --type "String" \
    --description "Email del remitente"

awslocal ssm put-parameter \
    --name "/app/s3/images-bucket" \
    --value "products-images" \
    --type "String" \
    --description "Nombre del bucket S3 para imágenes"

# Parámetro encriptado (SecureString)
awslocal ssm put-parameter \
    --name "/app/config/admin-email" \
    --value "admin@ecommerce.com" \
    --type "SecureString" \
    --description "Email del administrador (encriptado)"

echo "✅ Recursos inicializados correctamente!"
echo "🌐 Web UI disponible en: http://localhost:8080"
echo "🌐 SQS Admin disponible en: http://localhost:3999"
echo "🌐 DynamoDB Admin disponible en: http://localhost:8001"
