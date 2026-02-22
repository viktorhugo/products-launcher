# 📡 Guía de AWS EventBridge (Event Bus) con LocalStack

## ¿Qué es EventBridge?

AWS EventBridge es un **bus de eventos** que permite comunicación entre servicios mediante eventos. Es perfecto para arquitecturas **event-driven** (basadas en eventos).

### ¿Por qué usar EventBridge?

- ✅ Desacopla servicios (no necesitan conocerse entre sí)
- ✅ Escalable (maneja millones de eventos)
- ✅ Asíncrono (no bloquea tu aplicación)
- ✅ Filtros poderosos (enruta eventos basándose en patrones)

---

## 🎯 Eventos creados automáticamente

El script `localstack-setup.sh` crea estas reglas:

| Regla | Source | Event Type | Descripción |
|-------|--------|------------|-------------|
| `order-created-rule` | `orders.service` | `OrderCreated` | Se dispara cuando se crea una orden |
| `payment-completed-rule` | `payments.service` | `PaymentCompleted` | Se dispara cuando se completa un pago |
| `user-registered-rule` | `auth.service` | `UserRegistered` | Se dispara cuando se registra un usuario |

---

## 💻 Comandos básicos

### Ver todas las reglas

```bash
awslocal events list-rules
```

### Ver detalles de una regla

```bash
awslocal events describe-rule --name order-created-rule
```

### Crear una nueva regla

```bash
awslocal events put-rule \
  --name product-created-rule \
  --event-pattern '{
    "source": ["products.service"],
    "detail-type": ["ProductCreated"]
  }' \
  --description "Evento de producto creado"
```

### Eliminar una regla

```bash
# Primero remover targets
awslocal events remove-targets --rule order-created-rule --ids "1"

# Luego eliminar la regla
awslocal events delete-rule --name order-created-rule
```

---

## 🔧 Usar EventBridge en NestJS

### 1. Instalar dependencias

```bash
pnpm add @aws-sdk/client-eventbridge
```

### 2. Crear servicio de EventBridge

Crea `src/events/eventbridge.service.ts`:

```typescript
import { Injectable, Logger } from '@nestjs/common';
import {
  EventBridgeClient,
  PutEventsCommand,
  PutEventsCommandInput,
} from '@aws-sdk/client-eventbridge';

@Injectable()
export class EventBridgeService {
  private readonly logger = new Logger(EventBridgeService.name);
  private readonly client: EventBridgeClient;

  constructor() {
    const isLocal = process.env.NODE_ENV === 'development';

    this.client = new EventBridgeClient({
      endpoint: isLocal ? 'http://localstack:4566' : undefined,
      region: process.env.AWS_REGION || 'us-east-1',
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID || 'test',
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || 'test',
      },
    });
  }

  /**
   * Publicar un evento en EventBridge
   */
  async publishEvent<T = any>(params: {
    source: string;
    detailType: string;
    detail: T;
  }): Promise<void> {
    const { source, detailType, detail } = params;

    const input: PutEventsCommandInput = {
      Entries: [
        {
          Source: source,
          DetailType: detailType,
          Detail: JSON.stringify(detail),
          EventBusName: 'default', // Usa el bus por defecto
        },
      ],
    };

    try {
      const command = new PutEventsCommand(input);
      const response = await this.client.send(command);

      if (response.FailedEntryCount && response.FailedEntryCount > 0) {
        this.logger.error('Failed to publish event:', response.Entries);
        throw new Error('Failed to publish event');
      }

      this.logger.log(`Event published: ${source} - ${detailType}`);
    } catch (error) {
      this.logger.error('Error publishing event:', error);
      throw error;
    }
  }
}
```

### 3. Crear módulo de eventos

Crea `src/events/events.module.ts`:

```typescript
import { Module, Global } from '@nestjs/common';
import { EventBridgeService } from './eventbridge.service';

@Global() // Hace que el servicio esté disponible en toda la app
@Module({
  providers: [EventBridgeService],
  exports: [EventBridgeService],
})
export class EventsModule {}
```

### 4. Registrar en AppModule

```typescript
// src/app.module.ts
import { Module } from '@nestjs/common';
import { EventsModule } from './events/events.module';

@Module({
  imports: [EventsModule, /* otros módulos */],
})
export class AppModule {}
```

---

## 📤 Publicar eventos

### Ejemplo 1: Publicar evento cuando se crea una orden

```typescript
// src/orders/orders.service.ts
import { Injectable } from '@nestjs/common';
import { EventBridgeService } from '../events/eventbridge.service';

@Injectable()
export class OrdersService {
  constructor(private readonly eventBridge: EventBridgeService) {}

  async createOrder(orderDto: CreateOrderDto) {
    // Crear orden en la base de datos
    const order = await this.prisma.order.create({
      data: orderDto,
    });

    // Publicar evento de orden creada
    await this.eventBridge.publishEvent({
      source: 'orders.service',
      detailType: 'OrderCreated',
      detail: {
        orderId: order.id,
        userId: order.userId,
        totalPrice: order.totalPrice,
        items: order.items,
        createdAt: order.createdAt,
      },
    });

    return order;
  }
}
```

### Ejemplo 2: Publicar evento cuando se completa un pago

```typescript
// src/payments/payments.service.ts
import { Injectable } from '@nestjs/common';
import { EventBridgeService } from '../events/eventbridge.service';

@Injectable()
export class PaymentsService {
  constructor(private readonly eventBridge: EventBridgeService) {}

  async handleWebhook(stripeEvent: any) {
    // Procesar el webhook de Stripe
    const payment = await this.processPayment(stripeEvent);

    // Publicar evento de pago completado
    await this.eventBridge.publishEvent({
      source: 'payments.service',
      detailType: 'PaymentCompleted',
      detail: {
        paymentId: payment.id,
        orderId: payment.orderId,
        amount: payment.amount,
        status: 'succeeded',
        completedAt: new Date(),
      },
    });

    return payment;
  }
}
```

### Ejemplo 3: Publicar evento cuando se registra un usuario

```typescript
// src/auth/auth.service.ts
import { Injectable } from '@nestjs/common';
import { EventBridgeService } from '../events/eventbridge.service';

@Injectable()
export class AuthService {
  constructor(private readonly eventBridge: EventBridgeService) {}

  async register(registerDto: RegisterDto) {
    // Crear usuario
    const user = await this.usersService.create(registerDto);

    // Publicar evento de usuario registrado
    await this.eventBridge.publishEvent({
      source: 'auth.service',
      detailType: 'UserRegistered',
      detail: {
        userId: user.id,
        email: user.email,
        name: user.name,
        registeredAt: user.createdAt,
      },
    });

    return user;
  }
}
```

---

## 📥 Consumir eventos

EventBridge puede enviar eventos a diferentes destinos (targets):

### Target 1: Cola SQS

```bash
# Conectar la regla a una cola SQS
QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/orders-queue \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

awslocal events put-targets \
  --rule order-created-rule \
  --targets "Id"="1","Arn"="$QUEUE_ARN"
```

Luego consume desde SQS:

```typescript
// src/workers/order-worker.service.ts
@Injectable()
export class OrderWorkerService {
  async processOrderCreatedEvent(message: any) {
    const event = JSON.parse(message.Body);
    console.log('Order Created:', event.detail);

    // Procesar el evento (enviar email, actualizar inventario, etc.)
  }
}
```

### Target 2: Lambda Function (simulado con endpoint HTTP)

```bash
awslocal events put-targets \
  --rule order-created-rule \
  --targets "Id"="2","Arn"="arn:aws:lambda:us-east-1:000000000000:function:process-order"
```

### Target 3: Otro Event Bus (cross-account)

```bash
awslocal events put-targets \
  --rule order-created-rule \
  --targets "Id"="3","Arn"="arn:aws:events:us-east-1:123456789012:event-bus/default"
```

---

## 🎯 Patrones de eventos

### Patrón básico: Match exacto

```json
{
  "source": ["orders.service"],
  "detail-type": ["OrderCreated"]
}
```

### Patrón con filtros en detail

```json
{
  "source": ["orders.service"],
  "detail-type": ["OrderCreated"],
  "detail": {
    "totalPrice": [{ "numeric": [">", 100] }]
  }
}
```

Esto solo dispara si el precio es mayor a 100.

### Patrón con múltiples sources

```json
{
  "source": ["orders.service", "payments.service"],
  "detail-type": ["OrderCreated", "PaymentCompleted"]
}
```

### Patrón con prefix matching

```json
{
  "detail-type": [{ "prefix": "Order" }]
}
```

Esto matchea `OrderCreated`, `OrderUpdated`, `OrderCancelled`, etc.

---

## 🔄 Arquitectura Event-Driven completa

### Flujo de ejemplo: Procesar una orden

```
1. Usuario crea orden
   ↓
2. OrdersService publica "OrderCreated"
   ↓
3. EventBridge enruta el evento a:
   - Cola SQS (para procesar inventario)
   - Lambda (para enviar email de confirmación)
   - DynamoDB (para analytics)
```

### Código completo del flujo

#### 1. Publicar evento

```typescript
// orders.service.ts
await this.eventBridge.publishEvent({
  source: 'orders.service',
  detailType: 'OrderCreated',
  detail: { orderId, items, totalPrice },
});
```

#### 2. Worker procesa desde SQS

```typescript
// order-worker.service.ts
@Injectable()
export class OrderWorkerService implements OnModuleInit {
  async onModuleInit() {
    // Escuchar mensajes de la cola
    this.startPolling();
  }

  private async startPolling() {
    while (true) {
      const messages = await this.sqsService.receiveMessages('orders-queue');

      for (const message of messages) {
        const event = JSON.parse(message.Body);

        if (event.detailType === 'OrderCreated') {
          await this.processOrderCreated(event.detail);
        }

        await this.sqsService.deleteMessage(message);
      }
    }
  }

  private async processOrderCreated(detail: any) {
    // Actualizar inventario
    await this.inventoryService.decrementStock(detail.items);

    // Enviar email
    await this.emailService.sendOrderConfirmation(detail);
  }
}
```

---

## 📊 Monitorear eventos

### Ver eventos en CloudWatch (LocalStack)

```bash
awslocal logs tail /aws/events/rule/order-created-rule --follow
```

### Logs en tu aplicación

```typescript
this.logger.log(`Event published: ${source} - ${detailType}`);
this.logger.log(`Event detail: ${JSON.stringify(detail)}`);
```

---

## 🐛 Troubleshooting

### No se están publicando eventos

Verifica que EventBridge esté habilitado en LocalStack:
```bash
docker-compose logs localstack | grep "events"
```

### Los eventos no llegan a los targets

Verifica que los targets estén configurados:
```bash
awslocal events list-targets-by-rule --rule order-created-rule
```

### Error: "Event pattern is invalid"

El patrón debe ser JSON válido:
```bash
# ❌ MAL
--event-pattern "source: orders.service"

# ✅ BIEN
--event-pattern '{"source": ["orders.service"]}'
```

---

## 📚 Recursos

- [Documentación de EventBridge](https://docs.aws.amazon.com/eventbridge/)
- [Event Patterns](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html)
- [LocalStack EventBridge](https://docs.localstack.cloud/user-guide/aws/events/)

---

## 💡 Mejores prácticas

### 1. Usar nombres descriptivos para eventos

```typescript
// ❌ MAL
detailType: 'created'

// ✅ BIEN
detailType: 'OrderCreated'
```

### 2. Incluir metadata útil

```typescript
detail: {
  orderId: '123',
  timestamp: new Date().toISOString(),
  version: '1.0',
  // ... datos del evento
}
```

### 3. Versionar tus eventos

```typescript
detailType: 'OrderCreated.v2'
```

### 4. Idempotencia

Asegúrate de que procesar el mismo evento múltiples veces no cause problemas:

```typescript
async processEvent(event) {
  // Verificar si ya se procesó
  if (await this.wasProcessed(event.id)) {
    return;
  }

  // Procesar evento
  await this.process(event);

  // Marcar como procesado
  await this.markAsProcessed(event.id);
}
```
