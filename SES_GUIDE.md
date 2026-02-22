# 📧 Guía de AWS SES (Simple Email Service) con LocalStack

## ¿Qué es SES?

AWS Simple Email Service es un servicio para **enviar emails** desde tu aplicación. Soporta emails transaccionales, notificaciones y campañas de marketing.

---

## ⚠️ Concepto clave: Verificación de emails

Antes de enviar cualquier email con SES, **debes verificar** el email remitente. Esto aplica tanto en LocalStack como en AWS real.

```bash
# Sin verificar → ❌ Error "Email address is not verified"
# Con verificar  → ✅ Funciona correctamente
```

---

## 🎯 Templates creados automáticamente

El script `localstack-setup.sh` crea estos templates:

| Template | Asunto | Variables |
|----------|--------|-----------|
| `OrderConfirmation` | Orden #{{orderId}} confirmada | `name`, `orderId`, `total` |
| `WelcomeEmail` | Bienvenido a ECommerce, {{name}}! | `name` |
| `PasswordReset` | Recuperar contraseña | `name`, `resetUrl` |

Y verifica estos emails remitentes:

- `noreply@ecommerce.com`
- `admin@ecommerce.com`

---

## 💻 Comandos básicos

### Verificar un email

```bash
awslocal ses verify-email-identity \
  --email-address noreply@miapp.com
```

### Ver emails verificados

```bash
awslocal ses list-identities
```

### Enviar email simple

```bash
awslocal ses send-email \
  --from noreply@ecommerce.com \
  --to victor@example.com \
  --subject "Hola desde SES" \
  --text "Este es un email de prueba"
```

### Enviar email con template

```bash
awslocal ses send-templated-email \
  --source noreply@ecommerce.com \
  --destination '{"ToAddresses": ["victor@example.com"]}' \
  --template "OrderConfirmation" \
  --template-data '{"name": "Victor", "orderId": "123", "total": "99.99"}'
```

### Ver templates creados

```bash
awslocal ses list-templates
```

### Ver detalle de un template

```bash
awslocal ses get-template --template-name OrderConfirmation
```

### Actualizar un template

```bash
awslocal ses update-template \
  --template '{
    "TemplateName": "OrderConfirmation",
    "SubjectPart": "Tu orden #{{orderId}} esta lista!",
    "TextPart": "Hola {{name}}, tu orden esta lista.",
    "HtmlPart": "<h1>Orden lista!</h1>"
  }'
```

### Eliminar un template

```bash
awslocal ses delete-template --template-name OrderConfirmation
```

---

## 🔧 Usar SES en NestJS

### 1. Instalar dependencias

```bash
pnpm add @aws-sdk/client-ses
```

### 2. Crear servicio de SES

Crea `src/email/ses.service.ts`:

```typescript
import { Injectable, Logger } from '@nestjs/common';
import {
  SESClient,
  SendEmailCommand,
  SendTemplatedEmailCommand,
} from '@aws-sdk/client-ses';

@Injectable()
export class SesService {
  private readonly logger = new Logger(SesService.name);
  private readonly client: SESClient;
  private readonly fromEmail = 'noreply@ecommerce.com';

  constructor() {
    const isLocal = process.env.NODE_ENV === 'development';

    this.client = new SESClient({
      endpoint: isLocal ? 'http://localstack:4566' : undefined,
      region: process.env.AWS_REGION || 'us-east-1',
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID || 'test',
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || 'test',
      },
    });
  }

  /**
   * Enviar email simple con HTML
   */
  async sendEmail(params: {
    to: string | string[];
    subject: string;
    html: string;
    text?: string;
  }): Promise<void> {
    const { to, subject, html, text } = params;
    const toAddresses = Array.isArray(to) ? to : [to];

    const command = new SendEmailCommand({
      Source: this.fromEmail,
      Destination: { ToAddresses: toAddresses },
      Message: {
        Subject: { Data: subject },
        Body: {
          Html: { Data: html },
          Text: { Data: text ?? subject },
        },
      },
    });

    try {
      await this.client.send(command);
      this.logger.log(`Email sent to: ${toAddresses.join(', ')}`);
    } catch (error) {
      this.logger.error('Error sending email:', error);
      throw error;
    }
  }

  /**
   * Enviar email usando un template
   */
  async sendTemplatedEmail(params: {
    to: string | string[];
    templateName: string;
    templateData: Record<string, string>;
  }): Promise<void> {
    const { to, templateName, templateData } = params;
    const toAddresses = Array.isArray(to) ? to : [to];

    const command = new SendTemplatedEmailCommand({
      Source: this.fromEmail,
      Destination: { ToAddresses: toAddresses },
      Template: templateName,
      TemplateData: JSON.stringify(templateData),
    });

    try {
      await this.client.send(command);
      this.logger.log(`Templated email [${templateName}] sent to: ${toAddresses.join(', ')}`);
    } catch (error) {
      this.logger.error(`Error sending templated email [${templateName}]:`, error);
      throw error;
    }
  }
}
```

### 3. Crear módulo de email

Crea `src/email/email.module.ts`:

```typescript
import { Module, Global } from '@nestjs/common';
import { SesService } from './ses.service';

@Global()
@Module({
  providers: [SesService],
  exports: [SesService],
})
export class EmailModule {}
```

### 4. Registrar en AppModule

```typescript
// src/app.module.ts
import { Module } from '@nestjs/common';
import { EmailModule } from './email/email.module';

@Module({
  imports: [EmailModule],
})
export class AppModule {}
```

---

## 📤 Ejemplos de uso

### Email de bienvenida al registrarse

```typescript
// src/auth/auth.service.ts
@Injectable()
export class AuthService {
  constructor(private readonly sesService: SesService) {}

  async register(dto: RegisterDto) {
    const user = await this.usersService.create(dto);

    await this.sesService.sendTemplatedEmail({
      to: user.email,
      templateName: 'WelcomeEmail',
      templateData: { name: user.name },
    });

    return user;
  }
}
```

### Email de confirmación de orden

```typescript
// src/orders/orders.service.ts
@Injectable()
export class OrdersService {
  constructor(private readonly sesService: SesService) {}

  async create(dto: CreateOrderDto) {
    const order = await this.prisma.order.create({ data: dto });

    await this.sesService.sendTemplatedEmail({
      to: dto.userEmail,
      templateName: 'OrderConfirmation',
      templateData: {
        name: dto.userName,
        orderId: order.id,
        total: order.totalPrice.toFixed(2),
      },
    });

    return order;
  }
}
```

### Email de recuperación de contraseña

```typescript
// src/auth/auth.service.ts
async forgotPassword(email: string) {
  const token = this.generateResetToken();
  const resetUrl = `https://myapp.com/reset-password?token=${token}`;

  await this.sesService.sendTemplatedEmail({
    to: email,
    templateName: 'PasswordReset',
    templateData: {
      name: user.name,
      resetUrl,
    },
  });
}
```

### Email personalizado con HTML

```typescript
await this.sesService.sendEmail({
  to: 'victor@example.com',
  subject: 'Factura generada',
  html: `
    <h1>Tu factura esta lista</h1>
    <p>Puedes descargarla <a href="${invoiceUrl}">aqui</a></p>
  `,
});
```

### Email a multiples destinatarios

```typescript
await this.sesService.sendEmail({
  to: ['user1@example.com', 'user2@example.com'],
  subject: 'Notificacion importante',
  html: '<p>Este es un mensaje grupal</p>',
});
```

---

## 📊 Verificar envios en LocalStack

### Ver estadisticas de envio

```bash
awslocal ses get-send-statistics
```

### Ver quota de envio

```bash
awslocal ses get-send-quota
```

---

## 🐛 Troubleshooting

### Error: "Email address is not verified"

El email remitente no esta verificado:

```bash
awslocal ses verify-email-identity \
  --email-address noreply@ecommerce.com
```

### Error: "Template does not exist"

El template no existe o tiene un nombre incorrecto:

```bash
# Verificar que el template existe
awslocal ses list-templates
```

### Error: "Missing required key 'name' in params"

Las variables del template no coinciden con el `templateData`:

```typescript
// Template tiene: {{name}}, {{orderId}}
// templateData debe tener exactamente esas keys
templateData: {
  name: 'Victor',     // ✅
  orderId: '123',     // ✅
  // total: '99.99', // ❌ Variable no usada en el template
}
```

### Los emails no llegan en LocalStack

En LocalStack los emails **no se envian realmente**, solo se simulan. Para verlos:

```bash
# Ver logs de SES
docker-compose logs localstack | grep -i ses
```

---

## 💡 Mejores practicas

### 1. Siempre usar templates para emails recurrentes

```typescript
// ❌ MAL - HTML hardcodeado
html: '<h1>Hola Victor!</h1>'

// ✅ BIEN - Template reutilizable
templateName: 'WelcomeEmail',
templateData: { name: 'Victor' }
```

### 2. Separar el from email por tipo

```typescript
const FROM_EMAILS = {
  transactional: 'noreply@ecommerce.com',   // Ordenes, pagos
  support: 'support@ecommerce.com',          // Soporte
  marketing: 'promo@ecommerce.com',          // Promociones
};
```

### 3. Manejar errores sin bloquear el flujo

```typescript
async create(dto: CreateOrderDto) {
  const order = await this.prisma.order.create({ data: dto });

  // No bloquear si el email falla
  this.sesService.sendTemplatedEmail({ ... }).catch((err) => {
    this.logger.error('Email failed but order was created:', err);
  });

  return order;
}
```

---

## 📚 Recursos

- [Documentacion oficial de SES](https://docs.aws.amazon.com/ses/)
- [SDK de AWS para JavaScript](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/clients/client-ses/)
- [LocalStack SES](https://docs.localstack.cloud/user-guide/aws/ses/)
