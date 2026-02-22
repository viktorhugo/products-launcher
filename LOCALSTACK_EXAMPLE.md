# 🎯 Ejemplo Práctico: Subir Imágenes de Productos a S3

## Paso a paso para usar LocalStack con tu microservicio de productos

---

## 1️⃣ Instalar dependencias

```bash
cd products
pnpm add @aws-sdk/client-s3 @aws-sdk/s3-request-presigner
```

---

## 2️⃣ Crear configuración de AWS

Crea el archivo `products/src/config/aws.config.ts`:

```typescript
import { S3Client } from '@aws-sdk/client-s3';

// Detectar si estamos en desarrollo (LocalStack) o producción (AWS real)
const isLocal = process.env.NODE_ENV === 'development';

export const s3Client = new S3Client({
  endpoint: isLocal ? 'http://localstack:4566' : undefined,
  region: process.env.AWS_REGION || 'us-east-1',
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || 'test',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || 'test',
  },
  forcePathStyle: isLocal, // Solo para LocalStack
});

export const BUCKET_NAME = 'products-images';
```

---

## 3️⃣ Crear servicio de S3

Crea `products/src/s3/s3.service.ts`:

```typescript
import { Injectable, Logger } from '@nestjs/common';
import {
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { s3Client, BUCKET_NAME } from '../config/aws.config';

@Injectable()
export class S3Service {
  private readonly logger = new Logger(S3Service.name);

  /**
   * Sube una imagen a S3
   */
  async uploadImage(
    productId: string,
    fileName: string,
    fileBuffer: Buffer,
    contentType: string,
  ): Promise<string> {
    const key = `products/${productId}/${fileName}`;

    const command = new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      Body: fileBuffer,
      ContentType: contentType,
    });

    try {
      await s3Client.send(command);
      this.logger.log(`Image uploaded: ${key}`);

      // Retornar URL pública (LocalStack)
      return `http://localhost:4566/${BUCKET_NAME}/${key}`;
    } catch (error) {
      this.logger.error('Error uploading to S3:', error);
      throw error;
    }
  }

  /**
   * Genera una URL firmada temporal (válida por 1 hora)
   */
  async getSignedUrl(productId: string, fileName: string): Promise<string> {
    const key = `products/${productId}/${fileName}`;

    const command = new GetObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
    });

    return getSignedUrl(s3Client, command, { expiresIn: 3600 });
  }

  /**
   * Elimina una imagen de S3
   */
  async deleteImage(productId: string, fileName: string): Promise<void> {
    const key = `products/${productId}/${fileName}`;

    const command = new DeleteObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
    });

    try {
      await s3Client.send(command);
      this.logger.log(`Image deleted: ${key}`);
    } catch (error) {
      this.logger.error('Error deleting from S3:', error);
      throw error;
    }
  }
}
```

---

## 4️⃣ Actualizar el módulo de productos

Edita `products/src/products/products.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { ProductsController } from './products.controller';
import { ProductsService } from './products.service';
import { S3Service } from '../s3/s3.service';

@Module({
  controllers: [ProductsController],
  providers: [ProductsService, S3Service],
})
export class ProductsModule {}
```

---

## 5️⃣ Usar S3 en tu servicio de productos

Edita `products/src/products/products.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { S3Service } from '../s3/s3.service';

@Injectable()
export class ProductsService {
  constructor(private readonly s3Service: S3Service) {}

  async createProduct(productData: any, imageFile?: Express.Multer.File) {
    // Crear producto en la base de datos
    const product = await this.prisma.product.create({
      data: {
        name: productData.name,
        price: productData.price,
        // ... otros campos
      },
    });

    // Si hay imagen, subirla a S3
    if (imageFile) {
      const imageUrl = await this.s3Service.uploadImage(
        product.id,
        imageFile.originalname,
        imageFile.buffer,
        imageFile.mimetype,
      );

      // Actualizar producto con URL de imagen
      await this.prisma.product.update({
        where: { id: product.id },
        data: { image: imageUrl },
      });
    }

    return product;
  }
}
```

---

## 6️⃣ Probar LocalStack

### Iniciar LocalStack

```bash
docker-compose up -d localstack
```

### Verificar que el bucket existe

```bash
# Instalar awslocal (si no lo tienes)
pip install awscli-local

# Listar buckets
awslocal s3 ls

# Debería mostrar: products-images
```

### Probar subida de archivo

```bash
# Crear archivo de prueba
echo "Hola desde LocalStack" > test.txt

# Subir a S3
awslocal s3 cp test.txt s3://products-images/test.txt

# Verificar que se subió
awslocal s3 ls s3://products-images/
```

---

## 7️⃣ Ejemplo de Request HTTP

### Con Postman/Thunder Client

```
POST http://localhost:3000/api/products
Content-Type: multipart/form-data

name: "Camiseta Nike"
price: 29.99
image: [seleccionar archivo]
```

### Respuesta

```json
{
  "id": "123",
  "name": "Camiseta Nike",
  "price": 29.99,
  "image": "http://localhost:4566/products-images/products/123/camiseta.jpg"
}
```

---

## 8️⃣ Ver archivos en la Web UI

Abre: http://localhost:8080

1. Ve a la sección **S3**
2. Busca el bucket `products-images`
3. Verás todas las imágenes subidas
4. Puedes descargarlas, eliminarlas o ver metadatos

---

## 🎉 ¡Listo!

Ahora puedes:
- ✅ Subir imágenes de productos a S3 (LocalStack)
- ✅ Generar URLs firmadas temporales
- ✅ Eliminar imágenes cuando eliminas productos
- ✅ Todo funciona local sin AWS real
- ✅ En producción, solo cambias el endpoint a AWS real
