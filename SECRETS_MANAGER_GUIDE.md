# 🔐 Guía de AWS Secrets Manager con LocalStack

## ¿Qué es Secrets Manager?

AWS Secrets Manager es un servicio para **guardar y gestionar información sensible** como:
- Contraseñas de bases de datos
- API keys (Stripe, SendGrid, etc.)
- Tokens de autenticación
- Credenciales de AWS

---

## 🎯 Secretos creados automáticamente

El script `localstack-setup.sh` crea estos secretos:

| Nombre | Descripción | Contenido |
|--------|-------------|-----------|
| `prod/database/credentials` | Credenciales de PostgreSQL | username, password, host, port, database |
| `prod/stripe/api-keys` | Claves de Stripe | apiKey, webhookSecret |
| `prod/jwt/secret` | Clave para JWT | secret, expiresIn |
| `prod/aws/credentials` | Credenciales de AWS | accessKeyId, secretAccessKey, region |

---

## 💻 Comandos básicos

### Ver todos los secretos

```bash
awslocal secretsmanager list-secrets
```

### Obtener un secreto

```bash
# Obtener las credenciales de la base de datos
awslocal secretsmanager get-secret-value \
  --secret-id prod/database/credentials
```

### Crear un nuevo secreto

```bash
awslocal secretsmanager create-secret \
  --name prod/sendgrid/api-key \
  --description "API Key de SendGrid" \
  --secret-string '{
    "apiKey": "SG.1234567890"
  }'
```

### Actualizar un secreto

```bash
awslocal secretsmanager update-secret \
  --secret-id prod/database/credentials \
  --secret-string '{
    "username": "admin",
    "password": "new-password-456",
    "host": "localhost",
    "port": "5432",
    "database": "ordersdb"
  }'
```

### Eliminar un secreto

```bash
awslocal secretsmanager delete-secret \
  --secret-id prod/sendgrid/api-key \
  --force-delete-without-recovery
```

---

## 🔧 Usar Secrets Manager en NestJS

### 1. Instalar dependencias

```bash
pnpm add @aws-sdk/client-secrets-manager
```

### 2. Crear servicio de Secrets Manager

Crea `src/config/secrets.service.ts`:

```typescript
import { Injectable, Logger } from '@nestjs/common';
import {
  SecretsManagerClient,
  GetSecretValueCommand,
} from '@aws-sdk/client-secrets-manager';

@Injectable()
export class SecretsService {
  private readonly logger = new Logger(SecretsService.name);
  private readonly client: SecretsManagerClient;

  constructor() {
    const isLocal = process.env.NODE_ENV === 'development';

    this.client = new SecretsManagerClient({
      endpoint: isLocal ? 'http://localstack:4566' : undefined,
      region: process.env.AWS_REGION || 'us-east-1',
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID || 'test',
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || 'test',
      },
    });
  }

  /**
   * Obtener un secreto por su nombre
   */
  async getSecret<T = any>(secretName: string): Promise<T> {
    try {
      const command = new GetSecretValueCommand({
        SecretId: secretName,
      });

      const response = await this.client.send(command);

      if (!response.SecretString) {
        throw new Error(`Secret ${secretName} is empty`);
      }

      const secret = JSON.parse(response.SecretString);
      this.logger.log(`Secret ${secretName} retrieved successfully`);
      return secret as T;
    } catch (error) {
      this.logger.error(`Error getting secret ${secretName}:`, error);
      throw error;
    }
  }

  /**
   * Obtener credenciales de base de datos
   */
  async getDatabaseCredentials() {
    return this.getSecret<{
      username: string;
      password: string;
      host: string;
      port: string;
      database: string;
    }>('prod/database/credentials');
  }

  /**
   * Obtener claves de Stripe
   */
  async getStripeKeys() {
    return this.getSecret<{
      apiKey: string;
      webhookSecret: string;
    }>('prod/stripe/api-keys');
  }

  /**
   * Obtener secreto de JWT
   */
  async getJwtSecret() {
    return this.getSecret<{
      secret: string;
      expiresIn: string;
    }>('prod/jwt/secret');
  }
}
```

### 3. Usar en tu aplicación

#### Ejemplo: Obtener credenciales de DB al iniciar

```typescript
// src/main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { SecretsService } from './config/secrets.service';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Obtener credenciales de la base de datos
  const secretsService = app.get(SecretsService);
  const dbCredentials = await secretsService.getDatabaseCredentials();

  console.log('DB Host:', dbCredentials.host);
  console.log('DB Port:', dbCredentials.port);

  await app.listen(3000);
}
bootstrap();
```

#### Ejemplo: Usar Stripe keys

```typescript
// src/payments/payments.service.ts
import { Injectable, OnModuleInit } from '@nestjs/common';
import { SecretsService } from '../config/secrets.service';
import Stripe from 'stripe';

@Injectable()
export class PaymentsService implements OnModuleInit {
  private stripe: Stripe;

  constructor(private readonly secretsService: SecretsService) {}

  async onModuleInit() {
    // Obtener las claves de Stripe desde Secrets Manager
    const stripeKeys = await this.secretsService.getStripeKeys();

    this.stripe = new Stripe(stripeKeys.apiKey, {
      apiVersion: '2023-10-16',
    });

    console.log('Stripe initialized with secret key');
  }

  async createPaymentIntent(amount: number) {
    return this.stripe.paymentIntents.create({
      amount,
      currency: 'usd',
    });
  }
}
```

#### Ejemplo: Configurar JWT con secreto

```typescript
// src/auth/auth.module.ts
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { SecretsService } from '../config/secrets.service';

@Module({
  imports: [
    JwtModule.registerAsync({
      inject: [SecretsService],
      useFactory: async (secretsService: SecretsService) => {
        const jwtConfig = await secretsService.getJwtSecret();
        return {
          secret: jwtConfig.secret,
          signOptions: { expiresIn: jwtConfig.expiresIn },
        };
      },
    }),
  ],
})
export class AuthModule {}
```

---

## 🎯 Ejemplo completo: Variable de entorno vs Secrets Manager

### ❌ Antes (inseguro - hardcoded)

```typescript
// .env
DATABASE_PASSWORD=super-secret-123
STRIPE_API_KEY=sk_test_1234567890
```

### ✅ Después (seguro - Secrets Manager)

```typescript
// No hay secretos en .env
// Todo se obtiene de Secrets Manager

const dbCreds = await secretsService.getDatabaseCredentials();
const stripeKeys = await secretsService.getStripeKeys();
```

---

## 🔒 Mejores prácticas

### 1. **Nunca hardcodear secretos**
```typescript
// ❌ MAL
const apiKey = 'sk_test_1234567890';

// ✅ BIEN
const { apiKey } = await secretsService.getStripeKeys();
```

### 2. **Usar diferentes secretos por entorno**
```
dev/database/credentials
staging/database/credentials
prod/database/credentials
```

### 3. **Rotar secretos regularmente**
```bash
# Actualizar contraseña cada X días
awslocal secretsmanager rotate-secret \
  --secret-id prod/database/credentials
```

### 4. **Cachear secretos en memoria**
```typescript
private secretsCache = new Map<string, any>();

async getSecret<T>(secretName: string): Promise<T> {
  if (this.secretsCache.has(secretName)) {
    return this.secretsCache.get(secretName);
  }

  const secret = await this.fetchSecret<T>(secretName);
  this.secretsCache.set(secretName, secret);
  return secret;
}
```

---

## 🐛 Troubleshooting

### Error: "Secret not found"

Verifica que el secreto existe:
```bash
awslocal secretsmanager list-secrets
```

### Error: "Cannot connect to LocalStack"

Verifica que LocalStack esté corriendo:
```bash
docker-compose ps localstack
curl http://localhost:4566/_localstack/health
```

### Error: "Invalid JSON in secret"

El secreto debe ser un JSON válido:
```bash
# ❌ MAL
awslocal secretsmanager create-secret --secret-string "mi-password"

# ✅ BIEN
awslocal secretsmanager create-secret --secret-string '{"password":"mi-password"}'
```

---

## 📚 Recursos

- [Documentación de AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
- [SDK de AWS para JavaScript](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/clients/client-secrets-manager/)
- [LocalStack Secrets Manager](https://docs.localstack.cloud/user-guide/aws/secretsmanager/)

---

## 💡 Caso de uso: Migrar de .env a Secrets Manager

### Paso 1: Exportar secretos desde .env

```bash
# Script para migrar
./scripts/migrate-to-secrets.sh
```

### Paso 2: Crear script de migración

```bash
#!/bin/bash
# scripts/migrate-to-secrets.sh

# Leer del .env
source .env

# Crear secreto en Secrets Manager
awslocal secretsmanager create-secret \
  --name prod/app/config \
  --secret-string "{
    \"databaseUrl\": \"$DATABASE_URL\",
    \"stripeKey\": \"$STRIPE_API_KEY\",
    \"jwtSecret\": \"$JWT_SECRET\"
  }"

echo "✅ Secretos migrados a Secrets Manager"
```

### Paso 3: Actualizar código para usar Secrets Manager

```typescript
// Antes
const dbUrl = process.env.DATABASE_URL;

// Después
const config = await secretsService.getSecret('prod/app/config');
const dbUrl = config.databaseUrl;
```
