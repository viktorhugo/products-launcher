# ⚙️ Guía de AWS Systems Manager Parameter Store

## ¿Qué es Parameter Store?

AWS Systems Manager Parameter Store es un servicio para **almacenar parámetros de configuración** de tu aplicación. Es como tener variables de entorno en la nube.

---

## 🎯 ¿Cuándo usar Parameter Store vs Secrets Manager?

| Caso de uso | Usar |
|-------------|------|
| Contraseñas de base de datos | **Secrets Manager** 🔐 |
| API keys de Stripe | **Secrets Manager** 🔐 |
| Tokens de autenticación | **Secrets Manager** 🔐 |
| URL del API | **Parameter Store** ⚙️ |
| Feature flags | **Parameter Store** ⚙️ |
| Límites de negocio | **Parameter Store** ⚙️ |
| Configuraciones públicas | **Parameter Store** ⚙️ |

**Regla simple**: Si es sensible (no debe verse), usa Secrets Manager. Si es configuración, usa Parameter Store.

---

## 📦 Parámetros creados automáticamente

El script `localstack-setup.sh` crea estos parámetros:

| Parámetro | Valor | Uso |
|-----------|-------|-----|
| `/app/api/base-url` | `http://localhost:5000` | URL del API Gateway |
| `/app/features/enable-notifications` | `true` | Activar notificaciones |
| `/app/features/enable-analytics` | `false` | Activar analytics |
| `/app/limits/max-items-per-order` | `50` | Máximo items por orden |
| `/app/limits/free-shipping-threshold` | `75.00` | Envío gratis desde |
| `/app/email/sender-address` | `noreply@ecommerce.com` | Email remitente |
| `/app/s3/images-bucket` | `products-images` | Bucket de imágenes |
| `/app/config/admin-email` | `admin@ecommerce.com` | Email admin (encriptado) |

---

## 💻 Comandos básicos

### Ver todos los parámetros

```bash
awslocal ssm describe-parameters
```

### Obtener un parámetro

```bash
awslocal ssm get-parameter \
  --name "/app/api/base-url"
```

### Obtener valor directamente

```bash
awslocal ssm get-parameter \
  --name "/app/api/base-url" \
  --query "Parameter.Value" \
  --output text
```

### Crear un parámetro

```bash
awslocal ssm put-parameter \
  --name "/app/config/timeout" \
  --value "30000" \
  --type "String" \
  --description "Timeout en milisegundos"
```

### Actualizar un parámetro

```bash
awslocal ssm put-parameter \
  --name "/app/config/timeout" \
  --value "60000" \
  --overwrite
```

### Eliminar un parámetro

```bash
awslocal ssm delete-parameter \
  --name "/app/config/timeout"
```

### Obtener múltiples parámetros por ruta

```bash
# Obtener todos los parámetros bajo /app/features/
awslocal ssm get-parameters-by-path \
  --path "/app/features/" \
  --recursive
```

---

## 🔧 Usar Parameter Store en NestJS

### 1. Instalar dependencias

```bash
pnpm add @aws-sdk/client-ssm
```

### 2. Crear servicio de Parameter Store

Crea `src/config/parameter-store.service.ts`:

```typescript
import { Injectable, Logger } from '@nestjs/common';
import {
  SSMClient,
  GetParameterCommand,
  GetParametersCommand,
  GetParametersByPathCommand,
} from '@aws-sdk/client-ssm';

@Injectable()
export class ParameterStoreService {
  private readonly logger = new Logger(ParameterStoreService.name);
  private readonly client: SSMClient;
  private cache = new Map<string, any>();

  constructor() {
    const isLocal = process.env.NODE_ENV === 'development';

    this.client = new SSMClient({
      endpoint: isLocal ? 'http://localstack:4566' : undefined,
      region: process.env.AWS_REGION || 'us-east-1',
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID || 'test',
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || 'test',
      },
    });
  }

  /**
   * Obtener un parámetro por nombre
   */
  async getParameter(name: string): Promise<string> {
    // Verificar cache
    if (this.cache.has(name)) {
      return this.cache.get(name);
    }

    try {
      const command = new GetParameterCommand({
        Name: name,
        WithDecryption: true, // Desencripta SecureString
      });

      const response = await this.client.send(command);

      if (!response.Parameter?.Value) {
        throw new Error(`Parameter ${name} not found`);
      }

      const value = response.Parameter.Value;
      this.cache.set(name, value);
      this.logger.log(`Parameter ${name} retrieved`);

      return value;
    } catch (error) {
      this.logger.error(`Error getting parameter ${name}:`, error);
      throw error;
    }
  }

  /**
   * Obtener múltiples parámetros por ruta
   */
  async getParametersByPath(path: string): Promise<Record<string, string>> {
    try {
      const command = new GetParametersByPathCommand({
        Path: path,
        Recursive: true,
        WithDecryption: true,
      });

      const response = await this.client.send(command);
      const parameters: Record<string, string> = {};

      response.Parameters?.forEach((param) => {
        if (param.Name && param.Value) {
          parameters[param.Name] = param.Value;
        }
      });

      this.logger.log(`Retrieved ${Object.keys(parameters).length} parameters from ${path}`);
      return parameters;
    } catch (error) {
      this.logger.error(`Error getting parameters by path ${path}:`, error);
      throw error;
    }
  }

  /**
   * Feature Flags
   */
  async isFeatureEnabled(featureName: string): Promise<boolean> {
    const value = await this.getParameter(`/app/features/${featureName}`);
    return value.toLowerCase() === 'true';
  }

  /**
   * Limpiar cache (útil para recargar configuración)
   */
  clearCache() {
    this.cache.clear();
    this.logger.log('Parameter cache cleared');
  }
}
```

### 3. Registrar en módulo

```typescript
// src/config/config.module.ts
import { Module, Global } from '@nestjs/common';
import { ParameterStoreService } from './parameter-store.service';

@Global()
@Module({
  providers: [ParameterStoreService],
  exports: [ParameterStoreService],
})
export class ConfigModule {}
```

---

## 📤 Ejemplos de uso

### Ejemplo 1: Feature Flags

```typescript
// src/notifications/notifications.service.ts
import { Injectable } from '@nestjs/common';
import { ParameterStoreService } from '../config/parameter-store.service';

@Injectable()
export class NotificationsService {
  constructor(private readonly params: ParameterStoreService) {}

  async sendNotification(userId: string, message: string) {
    // Verificar si las notificaciones están habilitadas
    const isEnabled = await this.params.isFeatureEnabled('enable-notifications');

    if (!isEnabled) {
      console.log('Notifications disabled, skipping...');
      return;
    }

    // Enviar notificación
    await this.emailService.send(userId, message);
  }
}
```

### Ejemplo 2: Límites de negocio

```typescript
// src/orders/orders.service.ts
import { Injectable, BadRequestException } from '@nestjs/common';
import { ParameterStoreService } from '../config/parameter-store.service';

@Injectable()
export class OrdersService {
  constructor(private readonly params: ParameterStoreService) {}

  async validateOrder(items: any[]) {
    // Obtener límite máximo de items
    const maxItems = await this.params.getParameter('/app/limits/max-items-per-order');

    if (items.length > parseInt(maxItems)) {
      throw new BadRequestException(
        `Cannot order more than ${maxItems} items`
      );
    }

    // Verificar si aplica envío gratis
    const freeShippingThreshold = await this.params.getParameter(
      '/app/limits/free-shipping-threshold'
    );

    const total = this.calculateTotal(items);
    const hasFreeShipping = total >= parseFloat(freeShippingThreshold);

    return { hasFreeShipping, total };
  }
}
```

### Ejemplo 3: URLs de servicios

```typescript
// src/payments/payments.service.ts
import { Injectable } from '@nestjs/common';
import { ParameterStoreService } from '../config/parameter-store.service';
import axios from 'axios';

@Injectable()
export class PaymentsService {
  constructor(private readonly params: ParameterStoreService) {}

  async processPayment(orderId: string) {
    // Obtener URL base del API
    const baseUrl = await this.params.getParameter('/app/api/base-url');

    // Llamar al API de órdenes
    const response = await axios.get(`${baseUrl}/orders/${orderId}`);

    return response.data;
  }
}
```

### Ejemplo 4: Configurar S3 dinámicamente

```typescript
// src/uploads/uploads.service.ts
import { Injectable, OnModuleInit } from '@nestjs/common';
import { ParameterStoreService } from '../config/parameter-store.service';
import { S3Client } from '@aws-sdk/client-s3';

@Injectable()
export class UploadsService implements OnModuleInit {
  private bucketName: string;

  constructor(private readonly params: ParameterStoreService) {}

  async onModuleInit() {
    // Cargar el nombre del bucket desde Parameter Store
    this.bucketName = await this.params.getParameter('/app/s3/images-bucket');
    console.log(`Using S3 bucket: ${this.bucketName}`);
  }

  async uploadFile(file: Express.Multer.File) {
    // Usar this.bucketName
  }
}
```

---

## 🔄 Recargar configuración sin reiniciar

```typescript
// src/config/config.controller.ts
import { Controller, Post } from '@nestjs/common';
import { ParameterStoreService } from './parameter-store.service';

@Controller('config')
export class ConfigController {
  constructor(private readonly params: ParameterStoreService) {}

  @Post('reload')
  async reloadConfig() {
    // Limpiar cache para recargar parámetros
    this.params.clearCache();

    return {
      message: 'Configuration reloaded successfully',
    };
  }
}
```

---

## 🎯 Tipos de parámetros

### String (normal)

```bash
awslocal ssm put-parameter \
  --name "/app/config/version" \
  --value "1.0.0" \
  --type "String"
```

### StringList (lista separada por comas)

```bash
awslocal ssm put-parameter \
  --name "/app/config/allowed-origins" \
  --value "http://localhost:3000,https://app.com" \
  --type "StringList"
```

### SecureString (encriptado)

```bash
awslocal ssm put-parameter \
  --name "/app/config/admin-token" \
  --value "super-secret-token" \
  --type "SecureString"
```

---

## 📁 Organización de parámetros

### Por ambiente

```
/dev/database/host
/staging/database/host
/prod/database/host
```

### Por servicio

```
/app/orders/max-items
/app/payments/timeout
/app/auth/session-duration
```

### Por categoría

```
/app/features/dark-mode
/app/limits/max-file-size
/app/urls/api-gateway
```

---

## 🔐 Mejores prácticas

### 1. Usar jerarquías claras

```
✅ /app/service/config-name
❌ /random_name
```

### 2. Cachear valores

```typescript
// ✅ BIEN - Cachear en memoria
private cache = new Map<string, string>();

// ❌ MAL - Consultar en cada request
await params.getParameter('/app/config/value');
```

### 3. Valores por defecto

```typescript
const timeout = await params.getParameter('/app/timeout').catch(() => '30000');
```

### 4. Versionado

```
/app/config/api-version/v1
/app/config/api-version/v2
```

---

## 🆚 Comparación completa

| Feature | Parameter Store | Secrets Manager |
|---------|----------------|-----------------|
| **Costo** | Gratis (< 10,000) | $0.40/secreto/mes |
| **Rotación automática** | ❌ No | ✅ Sí |
| **Encriptación** | Opcional | Siempre |
| **Versionado** | ✅ Sí | ✅ Sí |
| **Auditoría (CloudTrail)** | ✅ Sí | ✅ Sí |
| **Integración con RDS** | ❌ No | ✅ Sí |
| **Límite de tamaño** | 8 KB | 64 KB |

---

## 🐛 Troubleshooting

### Parámetro no encontrado

```bash
# Verificar que existe
awslocal ssm describe-parameters --filters "Key=Name,Values=/app/config/timeout"
```

### Error de permisos

Verifica las credenciales en LocalStack:
```bash
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
```

### Cache desactualizado

```typescript
// Limpiar cache manualmente
parameterStore.clearCache();
```

---

## 📚 Recursos

- [Documentación de Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [SDK de AWS](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/clients/client-ssm/)
- [LocalStack SSM](https://docs.localstack.cloud/user-guide/aws/ssm/)
