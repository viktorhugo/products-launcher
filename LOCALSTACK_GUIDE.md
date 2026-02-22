# 📘 Guía de LocalStack

## ¿Qué es LocalStack?

LocalStack es un **emulador de AWS** que corre en tu computadora. Te permite usar servicios de AWS sin pagar y sin conexión a internet.

---

## 🚀 Inicio Rápido

### 1. Levantar todos los servicios

```bash
docker-compose up -d localstack sqs-admin dynamodb-admin
```

### 2. Verificar que funciona

Abre en tu navegador:

- **SQS Admin**: [http://localhost:3999](http://localhost:3999)
- **DynamoDB Admin**: [http://localhost:8001](http://localhost:8001)
- **Health Check**: [http://localhost:4566/_localstack/health](http://localhost:4566/_localstack/health)

> ⚠️ La Web UI de LocalStack en el puerto 8080 solo está disponible en la versión **Pro (de pago)**. La versión community no la incluye.

---

## 📦 Servicios Disponibles

| Servicio | ¿Para qué sirve? | Ejemplo de uso | Guía |
|----------|------------------|----------------|------|
| **S3** | Almacenar archivos (imágenes, PDFs, videos) | Guardar fotos de productos | `LOCALSTACK_EXAMPLE.md` |
| **SQS** | Colas de mensajes | Procesar pedidos en segundo plano | - |
| **SES** | Enviar emails | Notificaciones a usuarios | - |
| **DynamoDB** | Base de datos NoSQL | Guardar sesiones de usuario | - |
| **Secrets Manager** | Guardar contraseñas/secretos | API keys, credenciales | `SECRETS_MANAGER_GUIDE.md` |
| **Parameter Store** | Configuraciones de la app | Feature flags, URLs, límites | `PARAMETER_STORE_GUIDE.md` |
| **EventBridge** | Bus de eventos entre servicios | Eventos de órdenes, pagos | `EVENTBRIDGE_GUIDE.md` |

---

## 🌐 Interfaces Web

| UI | URL | Para qué sirve |
|----|-----|----------------|
| **LocalStack Web UI** | [http://localhost:8080](http://localhost:8080) | Ver todos los recursos AWS |
| **SQS Admin** | [http://localhost:3999](http://localhost:3999) | Gestionar colas, ver/enviar mensajes |
| **DynamoDB Admin** | [http://localhost:8001](http://localhost:8001) | Ver/editar tablas y registros |

---

## 🎯 Script de Inicialización

El archivo `scripts/localstack-setup.sh` se ejecuta automáticamente cuando LocalStack arranca.

**Qué crea automáticamente:**

| Tipo | Recurso | Descripción |
|------|---------|-------------|
| **S3** | `products-images` | Bucket para imágenes de productos |
| **SQS** | `orders-queue` | Cola para procesar órdenes |
| **DynamoDB** | `user-sessions` | Tabla para sesiones de usuario |
| **Secrets Manager** | `prod/database/credentials` | Credenciales de la base de datos |
| **Secrets Manager** | `prod/stripe/api-keys` | Claves de Stripe |
| **Secrets Manager** | `prod/jwt/secret` | Clave secreta para JWT |
| **Secrets Manager** | `prod/aws/credentials` | Credenciales de AWS S3 |
| **EventBridge** | `order-created-rule` | Evento de orden creada |
| **EventBridge** | `payment-completed-rule` | Evento de pago completado |
| **EventBridge** | `user-registered-rule` | Evento de usuario registrado |
| **Parameter Store** | `/app/api/base-url` | URL base del API Gateway |
| **Parameter Store** | `/app/features/*` | Feature flags |
| **Parameter Store** | `/app/limits/*` | Límites de negocio |
| **Parameter Store** | `/app/email/sender-address` | Email del remitente |
| **Parameter Store** | `/app/s3/images-bucket` | Nombre del bucket S3 |

**Personalizar:** Edita `scripts/localstack-setup.sh` para agregar más recursos que necesites.

---

## 💻 Instalar AWS CLI Local

```bash
pip install awscli-local
```

---

## 💻 Comandos Básicos

### 📦 S3 - Almacenar archivos

```bash
# Crear un bucket
awslocal s3 mb s3://mi-bucket

# Subir un archivo
awslocal s3 cp ./foto.jpg s3://mi-bucket/foto.jpg

# Listar archivos
awslocal s3 ls s3://mi-bucket

# Descargar un archivo
awslocal s3 cp s3://mi-bucket/foto.jpg ./descargada.jpg
```

### 📬 SQS - Colas de mensajes

```bash
# Crear una cola
awslocal sqs create-queue --queue-name mi-cola

# Enviar un mensaje
awslocal sqs send-message \
  --queue-url http://localhost:4566/000000000000/mi-cola \
  --message-body "Hola desde SQS"

# Leer mensajes
awslocal sqs receive-message \
  --queue-url http://localhost:4566/000000000000/mi-cola
```

### 💾 DynamoDB - Base de datos NoSQL

```bash
# Crear tabla
awslocal dynamodb create-table \
  --table-name usuarios \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# Insertar dato
awslocal dynamodb put-item \
  --table-name usuarios \
  --item '{"id":{"S":"1"},"nombre":{"S":"Victor"}}'

# Leer dato
awslocal dynamodb get-item \
  --table-name usuarios \
  --key '{"id":{"S":"1"}}'
```

### 🔐 Secrets Manager

```bash
# Listar secretos
awslocal secretsmanager list-secrets

# Obtener un secreto
awslocal secretsmanager get-secret-value \
  --secret-id prod/database/credentials
```

> Ver guía completa en `SECRETS_MANAGER_GUIDE.md`

### ⚙️ Parameter Store

```bash
# Listar parámetros
awslocal ssm describe-parameters

# Obtener un parámetro
awslocal ssm get-parameter --name "/app/api/base-url"
```

> Ver guía completa en `PARAMETER_STORE_GUIDE.md`

### 📡 EventBridge

```bash
# Listar reglas
awslocal events list-rules

# Ver detalles de una regla
awslocal events describe-rule --name order-created-rule
```

> Ver guía completa en `EVENTBRIDGE_GUIDE.md`

---

## 🔧 Configurar AWS SDK en NestJS

```typescript
// src/config/aws.config.ts
import { S3Client } from '@aws-sdk/client-s3';

const isLocal = process.env.NODE_ENV === 'development';

export const s3Client = new S3Client({
  endpoint: isLocal ? 'http://localstack:4566' : undefined,
  region: 'us-east-1',
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || 'test',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || 'test',
  },
  forcePathStyle: isLocal, // Necesario para LocalStack
});
```

---

## 🐛 Troubleshooting

### LocalStack no inicia

```bash
# Ver logs
docker-compose logs localstack

# Reiniciar
docker-compose restart localstack
```

### No puedo conectarme a LocalStack desde mi código

Verifica que uses:

- **Desde tu máquina**: `http://localhost:4566`
- **Desde un contenedor Docker**: `http://localstack:4566`
- Credentials: `accessKeyId: 'test'`, `secretAccessKey: 'test'`
- Region: `us-east-1`

### El script de inicialización no se ejecuta

Verifica que el script tenga permisos de ejecución:

```bash
chmod +x scripts/localstack-setup.sh
```

### SQS Admin no muestra colas

Verifica que LocalStack esté corriendo antes que SQS Admin:

```bash
docker-compose up -d localstack
docker-compose up -d sqs-admin
```

---

## 📚 Guías Detalladas

| Guía | Descripción |
|------|-------------|
| `LOCALSTACK_EXAMPLE.md` | Ejemplo práctico de subir imágenes a S3 |
| `SECRETS_MANAGER_GUIDE.md` | Cómo guardar y usar secretos |
| `PARAMETER_STORE_GUIDE.md` | Cómo gestionar configuraciones |
| `EVENTBRIDGE_GUIDE.md` | Arquitectura event-driven con EventBridge |

---

## 📚 Recursos

- [Documentación oficial de LocalStack](https://docs.localstack.cloud/)
- [AWS SDK para JavaScript](https://docs.aws.amazon.com/sdk-for-javascript/)
- [Ejemplos de LocalStack](https://github.com/localstack/localstack#examples)

---

## 💡 Casos de Uso Prácticos

### 1. Almacenar imágenes de productos → S3

- Sube fotos a S3
- Genera URLs públicas
- Sirve imágenes desde S3

### 2. Procesar pedidos en segundo plano → SQS

- Envía pedidos a la cola
- Worker consume la cola
- Procesa pagos/envíos de forma asíncrona

### 3. Enviar emails de confirmación → SES

- Usa SES para enviar emails
- Prueba templates de emails
- Verifica entregas en los logs

### 4. Guardar sesiones de usuario → DynamoDB

- Almacena tokens JWT
- Cache de datos temporales
- Expiración automática de sesiones

### 5. Guardar credenciales seguras → Secrets Manager

- API keys de terceros
- Contraseñas de base de datos
- Tokens de autenticación

### 6. Feature Flags y configuración → Parameter Store

- Activar/desactivar funcionalidades
- Cambiar límites de negocio
- URLs de servicios por ambiente

### 7. Comunicación entre microservicios → EventBridge

- Publicar eventos de dominio
- Desacoplar servicios
- Reaccionar a eventos de otros servicios
