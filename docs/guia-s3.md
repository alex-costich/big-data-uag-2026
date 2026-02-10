Guia Hands-On: S3, AWS Glue y Athena — De la Teoria a la Practica

Esta guia es un **puente** entre las slides teoricas del modulo "Design Principles and Patterns for Data Pipelines" y el lab "Querying Data by Using Athena". El problema con saltar directo al lab es que combina tres servicios (S3, Glue, Athena) sin que el estudiante haya interactuado con cada uno por separado.

**Prerequisitos:**

- Acceso a AWS Academy Learner Lab activo
- AWS CLI configurado (`aws configure` con las credenciales del Learner Lab)
- Python 3.8+ con boto3 instalado (`pip install boto3`)
- Conocimiento basico de SQL (SELECT, WHERE, GROUP BY)

**Duracion estimada:** 2.5 - 3 horas (sin contar el lab final)

**Estructura:**

1. **Ejercicio 1 — Amazon S3:** Crear un data lake con zonas (40 min)
2. **Ejercicio 2 — AWS Glue:** Catalogar datos y entender schemas (40 min)
3. **Ejercicio 3 — Amazon Athena:** Consultar datos con SQL (40 min)
4. **Ejercicio Integrador:** Combinar los tres servicios en un mini-pipeline (30 min)
5. **Conexion con el Lab:** Como lo que aprendiste aqui se aplica al lab de Athena

---

## Antes de Comenzar: Preparar el Entorno

### Verificar que AWS CLI funciona

```bash
# Verificar identidad (debe mostrar tu cuenta de Learner Lab)
aws sts get-caller-identity

# Salida esperada (los numeros varian):
# {
#     "UserId": "AROA3EXAMPLE:user123",
#     "Account": "123456789012",
#     "Arn": "arn:aws:sts::123456789012:assumed-role/voclabs/user123"
# }
```

Si obtienes un error de credenciales, regresa a la consola de Learner Lab, haz clic en "AWS Details" y copia las credenciales al archivo `~/.aws/credentials`.

### Verificar que Python y boto3 funcionan

```python
# Guardar como test_boto3.py y ejecutar: python test_boto3.py
import boto3

sts = boto3.client('sts')
identity = sts.get_caller_identity()
print(f"Cuenta AWS: {identity['Account']}")
print(f"ARN: {identity['Arn']}")
print("boto3 configurado correctamente.")
```

### Crear el dataset de ejemplo

Vamos a usar un dataset de viajes en taxi simplificado. Esto simula lo que el lab real usa pero a menor escala para que los ejercicios sean rapidos.

```python
# Guardar como crear_dataset.py y ejecutar: python crear_dataset.py
import csv
import random
from datetime import datetime, timedelta

# Generar 500 registros de viajes en taxi
# Esto es un SUBSET del dataset real del lab (que tiene millones de registros)
header = ['vendor', 'pickup', 'dropoff', 'count', 'distance',
          'ratecode', 'storeflag', 'pulocid', 'dolocid',
          'paytype', 'fare', 'extra', 'mta_tax', 'tip',
          'tolls', 'surcharge', 'total']

random.seed(42)  # Semilla fija para resultados reproducibles

def generar_viaje(mes):
    """Genera un registro de viaje aleatorio para un mes dado."""
    vendor = random.choice(['1', '2'])
    dia = random.randint(1, 28)
    hora = random.randint(0, 23)
    minuto = random.randint(0, 59)

    pickup = datetime(2017, mes, dia, hora, minuto, 0)
    duracion = random.randint(5, 60)  # minutos
    dropoff = pickup + timedelta(minutes=duracion)

    distance = random.randint(1, 25)
    fare = round(2.50 + distance * 2.50, 2)
    tip = round(fare * random.uniform(0, 0.30), 2)
    # paytype: 1=tarjeta, 2=efectivo, 3=sin cargo, 4=disputa
    paytype = random.choices(['1', '2', '3', '4'], weights=[50, 40, 5, 5])[0]
    # Si paga en efectivo, la propina registrada suele ser 0
    if paytype == '2':
        tip = 0.00
    total = round(fare + tip + 0.50 + 0.30, 2)  # fare + tip + mta_tax + surcharge

    return [vendor, pickup.strftime('%Y-%m-%d %H:%M:%S'),
            dropoff.strftime('%Y-%m-%d %H:%M:%S'),
            random.randint(1, 4), distance, '1', 'Y',
            str(random.randint(1, 265)), str(random.randint(1, 265)),
            paytype, fare, 0.00, 0.50, tip, 0.00, 0.30, total]


# Dataset completo: enero a marzo 2017
with open('taxi_full.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(header)
    for mes in [1, 2, 3]:
        for _ in range(200):
            writer.writerow(generar_viaje(mes))

# Dataset solo enero (para ejercicio de bucketizacion)
with open('taxi_enero.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(header)
    for _ in range(200):
        writer.writerow(generar_viaje(1))

# Dataset solo pagos con tarjeta (para ejercicio de particiones)
with open('taxi_tarjeta.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(header)
    with open('taxi_full.csv', 'r') as full:
        reader = csv.DictReader(full)
        for row in reader:
            if row['paytype'] == '1':
                writer.writerow([row[h] for h in header])

print("Archivos creados:")
print("  taxi_full.csv     - 600 registros (ene-mar 2017)")
print("  taxi_enero.csv    - 200 registros (solo enero)")
print("  taxi_tarjeta.csv  - ~300 registros (solo pagos con tarjeta)")
```

Ejecutar el script:

```bash
python crear_dataset.py
# Verificar los archivos
wc -l taxi_*.csv
head -3 taxi_full.csv
```

---

## Ejercicio 1: Amazon S3 como Data Lake

### Objetivo

Entender S3 como almacenamiento para un data lake. Las slides (diapositiva 26) muestran zonas de datos (landing, raw, trusted, curated) como un diagrama abstracto. Aqui vas a **implementar** esas zonas.

### Concepto Clave

S3 no tiene carpetas reales. Todo son objetos con un nombre (key) que puede incluir `/` para simular una jerarquia. Cuando ves `s3://mi-bucket/landing/taxis/enero.csv`, el objeto completo se llama `landing/taxis/enero.csv` y esta almacenado de forma plana dentro del bucket.

Esto es diferente a un sistema de archivos tradicional. No existe un directorio `landing/` como entidad separada. Es simplemente una convencion de nomenclatura que los servicios de AWS (y la consola) interpretan visualmente como carpetas.

### 1.1 Crear el bucket (Consola AWS)

1. Ir a la consola de S3: https://console.aws.amazon.com/s3/
2. Click en "Create bucket"
3. Nombre: `datalake-taxi-TUAPELLIDO-2017` (debe ser unico globalmente)
4. Region: `us-east-1` (misma region que el Learner Lab)
5. Dejar todas las opciones por defecto (Block all public access: ON)
6. Click "Create bucket"

**Pregunta para reflexionar:** Por que el nombre del bucket debe ser unico en TODA la plataforma de AWS, no solo en tu cuenta? Piensa en como funciona la URL de un bucket: `https://nombre-bucket.s3.amazonaws.com/`. Si dos personas pudieran usar el mismo nombre, las URLs colisionarian.

### 1.2 Crear el bucket (AWS CLI)

```bash
# Reemplazar TUAPELLIDO con tu apellido real
BUCKET_NAME="datalake-taxi-TUAPELLIDO-2017"

# Crear el bucket
# NOTA: en us-east-1 NO se usa --create-bucket-configuration
# En cualquier OTRA region, debes agregar:
#   --create-bucket-configuration LocationConstraint=us-west-2
aws s3 mb s3://$BUCKET_NAME

# Verificar que existe
aws s3 ls | grep datalake-taxi
```

### 1.3 Crear el bucket (Python boto3)

```python
# Guardar como crear_bucket.py
import boto3
from botocore.exceptions import ClientError

s3 = boto3.client('s3', region_name='us-east-1')

bucket_name = 'datalake-taxi-TUAPELLIDO-2017'  # CAMBIAR

try:
    # En us-east-1 no se especifica LocationConstraint
    s3.create_bucket(Bucket=bucket_name)
    print(f"Bucket creado: {bucket_name}")
except ClientError as e:
    error_code = e.response['Error']['Code']
    if error_code == 'BucketAlreadyOwnedByYou':
        print(f"El bucket {bucket_name} ya existe en tu cuenta.")
    elif error_code == 'BucketAlreadyExists':
        print(f"ERROR: El nombre {bucket_name} ya esta en uso por otra cuenta.")
        print("Cambia TUAPELLIDO por algo unico.")
    else:
        raise
```

### 1.4 Crear la estructura de zonas del data lake

Las slides muestran cuatro zonas. Aqui las implementamos como prefijos en S3:

```
s3://datalake-taxi-TUAPELLIDO-2017/
  ├── landing/       ← Datos tal cual llegan, sin modificar
  │   └── taxis/
  │       └── 2017/
  ├── raw/           ← Datos limpios (sin duplicados, sin corrupciones)
  │   └── taxis/
  │       └── 2017/
  ├── trusted/       ← Datos validados contra un schema definido
  │   └── taxis/
  │       └── 2017/
  └── curated/       ← Datos listos para analisis, enriquecidos
      └── taxis/
          └── 2017/
```

**Con AWS CLI:**

```bash
BUCKET_NAME="datalake-taxi-TUAPELLIDO-2017"

# Subir el dataset completo a la zona landing
aws s3 cp taxi_full.csv s3://$BUCKET_NAME/landing/taxis/2017/taxi_full.csv

# Subir el dataset de enero a una subcarpeta separada (esto simula bucketizacion)
aws s3 cp taxi_enero.csv s3://$BUCKET_NAME/landing/taxis/2017/enero/taxi_enero.csv

# Subir el dataset de tarjetas (esto simula una particion por paytype)
aws s3 cp taxi_tarjeta.csv s3://$BUCKET_NAME/landing/taxis/2017/paytype_1/taxi_tarjeta.csv

# Verificar la estructura
aws s3 ls s3://$BUCKET_NAME/ --recursive
```

**Con Python boto3:**

```python
# Guardar como subir_datos.py
import boto3
import os

s3 = boto3.client('s3')
bucket_name = 'datalake-taxi-TUAPELLIDO-2017'  # CAMBIAR

# Definir que archivo va a que zona y ruta
uploads = {
    'taxi_full.csv': 'landing/taxis/2017/taxi_full.csv',
    'taxi_enero.csv': 'landing/taxis/2017/enero/taxi_enero.csv',
    'taxi_tarjeta.csv': 'landing/taxis/2017/paytype_1/taxi_tarjeta.csv',
}

for local_file, s3_key in uploads.items():
    file_size = os.path.getsize(local_file)
    print(f"Subiendo {local_file} ({file_size:,} bytes) -> s3://{bucket_name}/{s3_key}")
    s3.upload_file(local_file, bucket_name, s3_key)

print("\nVerificando objetos en S3:")
response = s3.list_objects_v2(Bucket=bucket_name)
for obj in response.get('Contents', []):
    print(f"  {obj['Key']}  ({obj['Size']:,} bytes)")
```

### 1.5 Entender el modelo de costos de S3

Esto es relevante porque en el lab de Athena, el costo de las queries depende del volumen de datos escaneados en S3.

```python
# Guardar como costos_s3.py
import boto3

s3 = boto3.client('s3')
bucket_name = 'datalake-taxi-TUAPELLIDO-2017'  # CAMBIAR

# Listar todos los objetos y calcular el tamano total
response = s3.list_objects_v2(Bucket=bucket_name)
total_bytes = 0
objects = response.get('Contents', [])

print("Objetos en el bucket:")
print(f"{'Key':<60} {'Tamano':>12}")
print("-" * 74)
for obj in objects:
    print(f"{obj['Key']:<60} {obj['Size']:>10,} B")
    total_bytes += obj['Size']

print("-" * 74)
print(f"{'TOTAL':<60} {total_bytes:>10,} B")
print(f"{'TOTAL':<60} {total_bytes/1024:>10,.1f} KB")

# Calcular costo estimado de almacenamiento
# S3 Standard: $0.023 por GB/mes (us-east-1, primeros 50 TB)
costo_mensual = (total_bytes / (1024**3)) * 0.023
print(f"\nCosto estimado S3 Standard: ${costo_mensual:.6f} USD/mes")

# Calcular costo estimado de un scan completo en Athena
# Athena: $5.00 por TB escaneado
costo_scan = (total_bytes / (1024**4)) * 5.00
print(f"Costo estimado por query Athena (scan completo): ${costo_scan:.8f} USD")
print("\nNOTA: Con el dataset real del lab (~9 GB), cada query scan completo")
print("costaria aproximadamente $0.05 USD. Por eso las particiones importan.")
```

### 1.6 Ejercicio de Validacion

Antes de continuar, verifica que tu bucket tiene esta estructura:

```bash
aws s3 ls s3://$BUCKET_NAME/ --recursive --human-readable
```

Salida esperada (tamanos aproximados):

```
2017-01-15 10:30:00   45.2 KiB  landing/taxis/2017/enero/taxi_enero.csv
2017-01-15 10:30:00   25.1 KiB  landing/taxis/2017/paytype_1/taxi_tarjeta.csv
2017-01-15 10:30:00   55.8 KiB  landing/taxis/2017/taxi_full.csv
```

**Pregunta de reflexion:** En un escenario real con terabytes de datos, por que NO subiriamos todo como un solo archivo CSV gigante? Piensa en tres razones considerando: costo de queries, tiempo de procesamiento, y que pasa si necesitas reprocesar solo un mes.

---

## Ejercicio 2: AWS Glue como Catalogo de Metadatos

### Objetivo

Entender que AWS Glue funciona como un **diccionario** de tus datos. No almacena los datos (esos estan en S3), sino que almacena la **descripcion** de los datos: que columnas tienen, de que tipo son, donde estan ubicados.

Las slides (diapositiva 27) mencionan el "AWS Glue Data Catalog" y los "crawlers" pero no muestran como se usan. Aqui vas a crear un catalogo manualmente y entender cada componente.

### Concepto Clave: La Triada de Glue

```
AWS Glue Data Catalog
  └── Database (agrupacion logica, como un schema en SQL)
       └── Table (metadata de un dataset: columnas, tipos, ubicacion en S3)
            └── Partitions (subdivisiones de una tabla por valores de una columna)
```

Esto es EXACTAMENTE lo mismo que veras en el lab cuando Athena te pide seleccionar una "Database" y crea tablas. Athena no tiene su propia base de datos; usa el catalogo de Glue.

### 2.1 Crear una base de datos en Glue (Consola AWS)

1. Ir a AWS Glue: https://console.aws.amazon.com/glue/
2. En el menu izquierdo, bajo "Data Catalog", click en "Databases"
3. Click "Add database"
4. Nombre: `taxidata_practica`
5. Descripcion: `Base de datos de practica con datos de taxi NYC 2017`
6. Click "Create database"

### 2.2 Crear una base de datos en Glue (AWS CLI)

```bash
# Crear la base de datos
aws glue create-database --database-input '{
    "Name": "taxidata_practica",
    "Description": "Base de datos de practica con datos de taxi NYC 2017"
}'

# Verificar que se creo
aws glue get-database --name taxidata_practica

# Listar todas las bases de datos disponibles
aws glue get-databases --query 'DatabaseList[].Name'
```

### 2.3 Crear una base de datos en Glue (Python boto3)

```python
# Guardar como crear_glue_db.py
import boto3
from botocore.exceptions import ClientError

glue = boto3.client('glue')

try:
    glue.create_database(
        DatabaseInput={
            'Name': 'taxidata_practica',
            'Description': 'Base de datos de practica con datos de taxi NYC 2017'
        }
    )
    print("Base de datos 'taxidata_practica' creada exitosamente.")
except ClientError as e:
    if e.response['Error']['Code'] == 'AlreadyExistsException':
        print("La base de datos ya existe. Continuando.")
    else:
        raise

# Verificar
response = glue.get_database(Name='taxidata_practica')
db = response['Database']
print(f"\nNombre: {db['Name']}")
print(f"Descripcion: {db.get('Description', 'N/A')}")
print(f"Creada: {db['CreateTime']}")
```

### 2.4 Crear una tabla con schema en Glue

Aqui es donde defines la ESTRUCTURA de tus datos. Esto es lo que el lab hace automaticamente cuando usas "Bulk add columns" en Athena, pero es importante entender que ocurre por debajo.

**Con Python boto3 (mas claro que CLI para este caso):**

```python
# Guardar como crear_glue_tabla.py
import boto3

glue = boto3.client('glue')

bucket_name = 'datalake-taxi-TUAPELLIDO-2017'  # CAMBIAR

# Definir el schema de la tabla
# Cada columna tiene nombre y tipo, exactamente como en una base de datos relacional.
# La diferencia es que aqui el schema se aplica SOBRE LECTURA (schema-on-read),
# no al momento de insertar datos (schema-on-write como en MySQL/PostgreSQL).
columnas = [
    {'Name': 'vendor',    'Type': 'string',    'Comment': 'Proveedor del taxi (1 o 2)'},
    {'Name': 'pickup',    'Type': 'timestamp',  'Comment': 'Fecha y hora de recogida'},
    {'Name': 'dropoff',   'Type': 'timestamp',  'Comment': 'Fecha y hora de llegada'},
    {'Name': 'count',     'Type': 'int',        'Comment': 'Numero de pasajeros'},
    {'Name': 'distance',  'Type': 'int',        'Comment': 'Distancia en millas'},
    {'Name': 'ratecode',  'Type': 'string',     'Comment': 'Codigo de tarifa'},
    {'Name': 'storeflag', 'Type': 'string',     'Comment': 'Flag de almacenamiento'},
    {'Name': 'pulocid',   'Type': 'string',     'Comment': 'ID ubicacion de recogida'},
    {'Name': 'dolocid',   'Type': 'string',     'Comment': 'ID ubicacion de destino'},
    {'Name': 'paytype',   'Type': 'string',     'Comment': '1=tarjeta, 2=efectivo, 3=gratis, 4=disputa'},
    {'Name': 'fare',      'Type': 'decimal',    'Comment': 'Tarifa base'},
    {'Name': 'extra',     'Type': 'decimal',    'Comment': 'Cargos extra'},
    {'Name': 'mta_tax',   'Type': 'decimal',    'Comment': 'Impuesto MTA'},
    {'Name': 'tip',       'Type': 'decimal',    'Comment': 'Propina'},
    {'Name': 'tolls',     'Type': 'decimal',    'Comment': 'Peajes'},
    {'Name': 'surcharge', 'Type': 'decimal',    'Comment': 'Recargo'},
    {'Name': 'total',     'Type': 'decimal',    'Comment': 'Total cobrado'},
]

# Crear la tabla que apunta al dataset COMPLETO en S3
glue.create_table(
    DatabaseName='taxidata_practica',
    TableInput={
        'Name': 'yellow',
        'Description': 'Datos de viajes en taxi amarillo NYC 2017',
        'StorageDescriptor': {
            'Columns': columnas,
            'Location': f's3://{bucket_name}/landing/taxis/2017/',
            'InputFormat': 'org.apache.hadoop.mapred.TextInputFormat',
            'OutputFormat': 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
            'SerdeInfo': {
                'SerializationLibrary': 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe',
                'Parameters': {
                    'serialization.format': ',',
                    'field.delim': ','
                }
            }
        },
        'TableType': 'EXTERNAL_TABLE',
        'Parameters': {
            'has_encrypted_data': 'false',
            'skip.header.line.count': '1'  # Ignorar la fila de encabezados del CSV
        }
    }
)
print("Tabla 'yellow' creada en la base de datos 'taxidata_practica'")

# Ahora crear una tabla para solo los datos de enero (bucketizacion)
glue.create_table(
    DatabaseName='taxidata_practica',
    TableInput={
        'Name': 'enero',
        'Description': 'Datos de viajes en taxi - solo enero 2017 (bucket)',
        'StorageDescriptor': {
            'Columns': columnas,
            'Location': f's3://{bucket_name}/landing/taxis/2017/enero/',
            'InputFormat': 'org.apache.hadoop.mapred.TextInputFormat',
            'OutputFormat': 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
            'SerdeInfo': {
                'SerializationLibrary': 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe',
                'Parameters': {
                    'serialization.format': ',',
                    'field.delim': ','
                }
            }
        },
        'TableType': 'EXTERNAL_TABLE',
        'Parameters': {
            'has_encrypted_data': 'false',
            'skip.header.line.count': '1'
        }
    }
)
print("Tabla 'enero' creada en la base de datos 'taxidata_practica'")

# Verificar las tablas creadas
response = glue.get_tables(DatabaseName='taxidata_practica')
print(f"\nTablas en 'taxidata_practica':")
for table in response['TableList']:
    location = table['StorageDescriptor']['Location']
    num_cols = len(table['StorageDescriptor']['Columns'])
    print(f"  - {table['Name']}: {num_cols} columnas -> {location}")
```

### 2.5 Inspeccionar el catalogo

```python
# Guardar como inspeccionar_catalogo.py
import boto3
import json

glue = boto3.client('glue')

# Obtener detalle completo de una tabla
response = glue.get_table(
    DatabaseName='taxidata_practica',
    Name='yellow'
)

table = response['Table']
print(f"=== Tabla: {table['Name']} ===")
print(f"Base de datos: {table['DatabaseName']}")
print(f"Ubicacion S3: {table['StorageDescriptor']['Location']}")
print(f"Formato: {table['StorageDescriptor']['SerdeInfo']['SerializationLibrary']}")
print(f"Tipo: {table['TableType']}")
print(f"\nColumnas ({len(table['StorageDescriptor']['Columns'])}):")
print(f"{'Nombre':<15} {'Tipo':<12} {'Comentario'}")
print("-" * 60)
for col in table['StorageDescriptor']['Columns']:
    print(f"{col['Name']:<15} {col['Type']:<12} {col.get('Comment', '')}")

# Punto importante:
# Este schema NO valida los datos en S3. Solo DESCRIBE como deben leerse.
# Si el CSV tiene un campo de texto donde el schema dice "int",
# obtendras errores al hacer queries, no al crear la tabla.
print("\n--- CONCEPTO CLAVE ---")
print("Este schema es 'schema-on-read': se aplica cuando LEES los datos,")
print("no cuando los escribes. Si los datos no coinciden con el schema,")
print("Athena devolvera NULL o errores en tiempo de consulta.")
```

### 2.6 (Opcional) Usar un Crawler para auto-descubrir el schema

Los crawlers son procesos que leen los datos en S3 y DEDUCEN el schema automaticamente. En produccion esto es util cuando tienes cientos de datasets y no quieres definir cada schema a mano.

```python
# Guardar como crear_crawler.py
import boto3
import time

glue = boto3.client('glue')
iam = boto3.client('iam')

bucket_name = 'datalake-taxi-TUAPELLIDO-2017'  # CAMBIAR

# NOTA: En Learner Lab, el rol de IAM para Glue ya existe.
# Si no existe, este paso fallara y deberas crear el crawler
# desde la consola web de AWS Glue donde puedes seleccionar el rol.
# El nombre del rol varia segun tu Learner Lab.

# Obtener el ARN del rol de lab
# En Learner Lab tipicamente es 'LabRole'
try:
    role = iam.get_role(RoleName='LabRole')
    role_arn = role['Role']['Arn']
    print(f"Usando rol: {role_arn}")
except Exception as e:
    print(f"No se encontro 'LabRole'. Error: {e}")
    print("Intenta crear el crawler desde la consola de AWS Glue.")
    exit(1)

# Crear el crawler
try:
    glue.create_crawler(
        Name='taxi-crawler-practica',
        Role=role_arn,
        DatabaseName='taxidata_practica',
        Targets={
            'S3Targets': [
                {'Path': f's3://{bucket_name}/landing/taxis/2017/'}
            ]
        },
        Description='Crawler que descubre automaticamente el schema de los datos de taxi'
    )
    print("Crawler 'taxi-crawler-practica' creado.")
except glue.exceptions.AlreadyExistsException:
    print("Crawler ya existe. Continuando.")

# Ejecutar el crawler
print("Ejecutando crawler (esto puede tardar 1-3 minutos)...")
glue.start_crawler(Name='taxi-crawler-practica')

# Esperar a que termine
while True:
    response = glue.get_crawler(Name='taxi-crawler-practica')
    state = response['Crawler']['State']
    print(f"  Estado: {state}")
    if state == 'READY':
        break
    time.sleep(15)

print("\nCrawler finalizado. Revisando tablas descubiertas:")
response = glue.get_tables(DatabaseName='taxidata_practica')
for table in response['TableList']:
    cols = table['StorageDescriptor']['Columns']
    print(f"  - {table['Name']}: {len(cols)} columnas")
    for col in cols[:5]:
        print(f"      {col['Name']}: {col['Type']}")
    if len(cols) > 5:
        print(f"      ... y {len(cols) - 5} columnas mas")
```

### 2.7 Ejercicio de Validacion

```bash
# Verificar desde CLI que las tablas existen en Glue
aws glue get-tables --database-name taxidata_practica \
    --query 'TableList[].{Nombre:Name, Columnas:length(StorageDescriptor.Columns), Ubicacion:StorageDescriptor.Location}' \
    --output table
```

Salida esperada:

```
-------------------------------------------------------------
|                        GetTables                          |
+---------+-------------------+-----------------------------+
| Columnas|      Nombre       |         Ubicacion           |
+---------+-------------------+-----------------------------+
|  17     |  yellow           |  s3://datalake-taxi-.../... |
|  17     |  enero            |  s3://datalake-taxi-.../... |
+---------+-------------------+-----------------------------+
```

**Pregunta de reflexion:** Cual es la diferencia entre crear el schema manualmente (como hicimos con `create_table`) y usar un crawler? Piensa en los trade-offs: el crawler es mas rapido, pero puede deducir tipos incorrectos. Por ejemplo, un campo que contiene `1` y `2` podria ser `int` o `string` — el crawler no sabe que `1` significa "tarjeta de credito".

---

## Ejercicio 3: Amazon Athena como Motor de Consultas SQL

### Objetivo

Usar Athena para consultar datos en S3 usando SQL estandar. Athena **no almacena datos**; los lee directamente de S3 usando el schema definido en Glue.

Las slides (diapositiva 33) muestran a Athena como herramienta de "Interactive SQL" pero no muestran queries reales. Aqui vas a ejecutar queries progresivamente mas complejos.

### Concepto Clave: Athena es Serverless

Athena no requiere servidores, no hay clusters que configurar, no hay procesos corriendo permanentemente. Envias una query SQL, Athena la ejecuta contra los datos en S3, y pagas solo por los datos escaneados ($5 USD por TB).

```
[Tu query SQL] --> [Athena] --> [Lee schema de Glue] --> [Escanea datos en S3] --> [Resultados]
```

### 3.1 Configurar Athena (Consola AWS)

1. Ir a Athena: https://console.aws.amazon.com/athena/
2. Click "Explore the query editor"
3. Ir a la pestana "Settings" > "Manage"
4. En "Location of query result", click "Browse S3" y seleccionar tu bucket
    - Athena necesita un lugar donde guardar los resultados de las queries
    - Usa: `s3://datalake-taxi-TUAPELLIDO-2017/athena-results/`
5. Click "Save"
6. Regresar a la pestana "Editor"
7. En el panel izquierdo, seleccionar Database: `taxidata_practica`

### 3.2 Configurar Athena (AWS CLI)

```bash
BUCKET_NAME="datalake-taxi-TUAPELLIDO-2017"

# Crear un workgroup con la configuracion de resultados
aws athena create-work-group \
    --name "practica-workgroup" \
    --configuration "{
        \"ResultConfiguration\": {
            \"OutputLocation\": \"s3://$BUCKET_NAME/athena-results/\"
        }
    }" \
    --description "Workgroup para ejercicios de practica"

echo "Workgroup creado. Resultados se guardaran en s3://$BUCKET_NAME/athena-results/"
```

### 3.3 Queries Progresivos — De Basico a Avanzado

Estos queries se pueden ejecutar en la consola de Athena O con Python boto3 (mostrado al final).

**Query 1: Explorar los datos (vista rapida)**

```sql
-- Primero, ver los primeros 10 registros para entender la estructura
-- Esto es equivalente a hacer head -10 en un archivo CSV
SELECT * FROM taxidata_practica.yellow LIMIT 10;
```

**Query 2: Contar registros totales**

```sql
-- Cuantos viajes hay en el dataset completo?
SELECT COUNT(*) AS total_viajes FROM taxidata_practica.yellow;

-- Cuantos hay por mes?
-- NOTA: usamos la funcion month() para extraer el mes del timestamp
SELECT
    month(pickup) AS mes,
    COUNT(*) AS total_viajes
FROM taxidata_practica.yellow
GROUP BY month(pickup)
ORDER BY mes;
```

**Query 3: Analisis basico de ingresos**

```sql
-- Total de ingresos por tipo de pago
-- Recuerda: 1=tarjeta, 2=efectivo, 3=gratis, 4=disputa
SELECT
    paytype,
    CASE paytype
        WHEN '1' THEN 'Tarjeta de credito'
        WHEN '2' THEN 'Efectivo'
        WHEN '3' THEN 'Sin cargo'
        WHEN '4' THEN 'Disputa'
        ELSE 'Desconocido'
    END AS tipo_pago,
    COUNT(*) AS cantidad_viajes,
    ROUND(SUM(total), 2) AS ingresos_totales,
    ROUND(AVG(total), 2) AS ingreso_promedio,
    ROUND(AVG(tip), 2) AS propina_promedio
FROM taxidata_practica.yellow
GROUP BY paytype
ORDER BY ingresos_totales DESC;
```

**Query 4: Comparar dataset completo vs. bucketizado (CONCEPTO CLAVE DEL LAB)**

```sql
-- QUERY A: Buscar viajes de enero en el dataset COMPLETO
-- Athena escaneara TODOS los datos (3 meses) para encontrar los de enero
SELECT
    COUNT(*) AS viajes_enero,
    ROUND(SUM(total), 2) AS ingresos_enero
FROM taxidata_practica.yellow
WHERE pickup BETWEEN TIMESTAMP '2017-01-01 00:00:00'
                 AND TIMESTAMP '2017-02-01 00:00:00';

-- Anotar: tiempo de ejecucion y datos escaneados
-- (se muestran debajo de los resultados en la consola de Athena)
```

```sql
-- QUERY B: La misma consulta pero en la tabla BUCKETIZADA (solo enero)
-- Athena escaneara SOLO los datos de enero
SELECT
    COUNT(*) AS viajes_enero,
    ROUND(SUM(total), 2) AS ingresos_enero
FROM taxidata_practica.enero;

-- Anotar: tiempo de ejecucion y datos escaneados
-- DEBERIA ser significativamente menor que Query A
```

**Analisis de la comparacion:**

|Metrica|Query A (dataset completo)|Query B (solo enero)|
|---|---|---|
|Datos escaneados|~55 KB (todos los meses)|~18 KB (solo enero)|
|Resultado|Mismo|Mismo|
|Costo proporcional|3x|1x|

Con el dataset real del lab (~9 GB), esta diferencia se amplifica enormemente. El lab reporta ~9.32 GB escaneados para el dataset completo vs. ~3 GB para el bucketizado.

**Query 5: Crear una vista (simplificar queries complejos)**

```sql
-- Las vistas NO almacenan datos. Son queries guardados que puedes reutilizar.
-- Esto es exactamente lo que haras en la Tarea 4 del lab.

-- Vista para ingresos por tarjeta de credito
CREATE VIEW taxidata_practica.v_ingresos_tarjeta AS
SELECT
    ROUND(SUM(fare), 2) AS tarifa_total,
    ROUND(SUM(tip), 2) AS propinas_total,
    ROUND(SUM(total), 2) AS ingreso_total,
    COUNT(*) AS cantidad_viajes
FROM taxidata_practica.yellow
WHERE paytype = '1';

-- Vista para ingresos en efectivo
CREATE VIEW taxidata_practica.v_ingresos_efectivo AS
SELECT
    ROUND(SUM(fare), 2) AS tarifa_total,
    ROUND(SUM(total), 2) AS ingreso_total,
    COUNT(*) AS cantidad_viajes
FROM taxidata_practica.yellow
WHERE paytype = '2';

-- Consultar las vistas como si fueran tablas
SELECT * FROM taxidata_practica.v_ingresos_tarjeta;
SELECT * FROM taxidata_practica.v_ingresos_efectivo;
```

**Query 6: Unir datos de multiples vistas (vista compuesta)**

```sql
-- Esta es la version simplificada de lo que haras en la Tarea 4 del lab
-- (la vista comparepay)
CREATE VIEW taxidata_practica.v_comparar_pagos AS
WITH
    tarjeta AS (
        SELECT SUM(fare) AS total_tarjeta, vendor
        FROM taxidata_practica.yellow
        WHERE paytype = '1'
        GROUP BY vendor
    ),
    efectivo AS (
        SELECT SUM(fare) AS total_efectivo, vendor
        FROM taxidata_practica.yellow
        WHERE paytype = '2'
        GROUP BY vendor
    )
SELECT
    t.vendor,
    ROUND(t.total_tarjeta, 2) AS ingresos_tarjeta,
    ROUND(e.total_efectivo, 2) AS ingresos_efectivo,
    ROUND(t.total_tarjeta - e.total_efectivo, 2) AS diferencia
FROM tarjeta t
JOIN efectivo e ON t.vendor = e.vendor;

-- Ejecutar la vista
SELECT * FROM taxidata_practica.v_comparar_pagos;
```

### 3.4 Ejecutar Queries desde Python boto3

En produccion, rara vez se ejecutan queries manualmente desde la consola. Se automatizan con scripts:

```python
# Guardar como ejecutar_athena.py
import boto3
import time

athena = boto3.client('athena')

bucket_name = 'datalake-taxi-TUAPELLIDO-2017'  # CAMBIAR
database = 'taxidata_practica'
output_location = f's3://{bucket_name}/athena-results/'


def ejecutar_query(sql, descripcion=""):
    """Ejecuta un query en Athena y espera el resultado."""
    print(f"\n{'='*60}")
    if descripcion:
        print(f"  {descripcion}")
    print(f"{'='*60}")
    print(f"SQL: {sql[:100]}{'...' if len(sql) > 100 else ''}")

    # Iniciar la ejecucion (asincrona)
    response = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={'Database': database},
        ResultConfiguration={'OutputLocation': output_location}
    )
    query_id = response['QueryExecutionId']
    print(f"Query ID: {query_id}")

    # Esperar a que termine (polling)
    while True:
        status = athena.get_query_execution(QueryExecutionId=query_id)
        state = status['QueryExecution']['Status']['State']

        if state == 'SUCCEEDED':
            # Obtener metricas
            stats = status['QueryExecution']['Statistics']
            scan_bytes = stats.get('DataScannedInBytes', 0)
            exec_time = stats.get('EngineExecutionTimeInMillis', 0)
            print(f"Estado: EXITOSO")
            print(f"Tiempo de ejecucion: {exec_time} ms")
            print(f"Datos escaneados: {scan_bytes:,} bytes ({scan_bytes/1024:.1f} KB)")
            print(f"Costo estimado: ${(scan_bytes / (1024**4)) * 5:.8f} USD")
            break

        elif state in ('FAILED', 'CANCELLED'):
            reason = status['QueryExecution']['Status'].get('StateChangeReason', 'Desconocido')
            print(f"Estado: {state}")
            print(f"Razon: {reason}")
            return None

        print(f"  Esperando... (estado: {state})")
        time.sleep(2)

    # Obtener resultados
    results = athena.get_query_results(QueryExecutionId=query_id)
    rows = results['ResultSet']['Rows']

    if len(rows) > 1:  # Primera fila son los encabezados
        headers = [col['VarCharValue'] for col in rows[0]['Data']]
        print(f"\nResultados ({len(rows)-1} filas):")
        print(f"  {' | '.join(headers)}")
        print(f"  {'-' * (len(' | '.join(headers)))}")
        for row in rows[1:6]:  # Mostrar max 5 filas
            values = [col.get('VarCharValue', 'NULL') for col in row['Data']]
            print(f"  {' | '.join(values)}")
        if len(rows) > 6:
            print(f"  ... y {len(rows) - 6} filas mas")

    return query_id


# Ejecutar los queries progresivos
ejecutar_query(
    "SELECT COUNT(*) AS total_viajes FROM yellow",
    "Query 1: Total de viajes"
)

ejecutar_query(
    """SELECT paytype,
        COUNT(*) AS cantidad,
        ROUND(SUM(total), 2) AS ingresos
    FROM yellow
    GROUP BY paytype
    ORDER BY ingresos DESC""",
    "Query 2: Ingresos por tipo de pago"
)

# Comparacion de rendimiento: completo vs. bucketizado
ejecutar_query(
    """SELECT COUNT(*) AS viajes, ROUND(SUM(total),2) AS ingresos
    FROM yellow
    WHERE pickup BETWEEN TIMESTAMP '2017-01-01 00:00:00'
                     AND TIMESTAMP '2017-02-01 00:00:00'""",
    "Query 3a: Enero desde dataset COMPLETO (mas datos escaneados)"
)

ejecutar_query(
    """SELECT COUNT(*) AS viajes, ROUND(SUM(total),2) AS ingresos
    FROM enero""",
    "Query 3b: Enero desde dataset BUCKETIZADO (menos datos escaneados)"
)
```

### 3.5 Ejercicio de Validacion

Ejecutar el script de Python y anotar las metricas de los queries 3a y 3b. Completar esta tabla:

|Metrica|Query 3a (completo)|Query 3b (bucketizado)|
|---|---|---|
|Datos escaneados (bytes)|_____|_____|
|Tiempo ejecucion (ms)|_____|_____|
|Costo estimado (USD)|_____|_____|

**Pregunta de reflexion:** Si tu dataset crece a 1 TB y ejecutas 1,000 queries diarios, cual seria la diferencia de costo mensual entre consultar el dataset completo vs. particionado? Haz el calculo:

- Sin particion: 1 TB x $5/TB x 1,000 queries x 30 dias = $___/mes
- Con particion al 33% del scan: 0.33 TB x $5/TB x 1,000 queries x 30 dias = $___/mes

---

## Ejercicio 4: Mini-Pipeline Integrador

### Objetivo

Combinar los tres servicios en un flujo completo que simula lo que haras en el lab pero con control total del proceso.

```
[Datos CSV] --subir--> [S3 landing/] --catalogar--> [Glue Database/Table] --consultar--> [Athena SQL]
     |                                                                                        |
     |                     [S3 curated/]  <--guardar resultado--  [Athena CTAS]  <-----+------+
```

### 4.1 Pipeline completo en Python

```python
# Guardar como pipeline_completo.py
import boto3
import time
import csv
import io

# --- CONFIGURACION ---
bucket_name = 'datalake-taxi-TUAPELLIDO-2017'  # CAMBIAR
database = 'taxidata_practica'
output_location = f's3://{bucket_name}/athena-results/'

s3 = boto3.client('s3')
glue = boto3.client('glue')
athena = boto3.client('athena')


def esperar_query(query_id):
    """Espera a que un query de Athena termine y retorna el resultado."""
    while True:
        status = athena.get_query_execution(QueryExecutionId=query_id)
        state = status['QueryExecution']['Status']['State']
        if state == 'SUCCEEDED':
            stats = status['QueryExecution']['Statistics']
            print(f"  OK - {stats.get('EngineExecutionTimeInMillis', 0)}ms, "
                  f"{stats.get('DataScannedInBytes', 0):,} bytes escaneados")
            return status
        elif state in ('FAILED', 'CANCELLED'):
            reason = status['QueryExecution']['Status'].get('StateChangeReason', '')
            print(f"  ERROR: {state} - {reason}")
            return None
        time.sleep(2)


def ejecutar(sql, desc=""):
    """Ejecuta SQL en Athena y espera resultado."""
    if desc:
        print(f"\n[PASO] {desc}")
    response = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={'Database': database},
        ResultConfiguration={'OutputLocation': output_location}
    )
    return esperar_query(response['QueryExecutionId'])


# ============================
# PASO 1: Verificar datos en S3
# ============================
print("=" * 60)
print("PASO 1: Verificar datos en S3")
print("=" * 60)
response = s3.list_objects_v2(Bucket=bucket_name, Prefix='landing/')
objects = response.get('Contents', [])
total_size = sum(obj['Size'] for obj in objects)
print(f"  Objetos en landing/: {len(objects)}")
print(f"  Tamano total: {total_size:,} bytes")

# ============================
# PASO 2: Verificar catalogo en Glue
# ============================
print(f"\n{'='*60}")
print("PASO 2: Verificar catalogo en Glue")
print("=" * 60)
tables = glue.get_tables(DatabaseName=database)
for t in tables['TableList']:
    print(f"  Tabla: {t['Name']} -> {t['StorageDescriptor']['Location']}")

# ============================
# PASO 3: Consultas analiticas en Athena
# ============================
print(f"\n{'='*60}")
print("PASO 3: Ejecutar consultas analiticas")
print("=" * 60)

ejecutar(
    "SELECT COUNT(*) AS total FROM yellow",
    "Conteo total de registros"
)

ejecutar("""
    SELECT
        vendor,
        paytype,
        COUNT(*) AS viajes,
        ROUND(SUM(total), 2) AS ingresos,
        ROUND(AVG(distance), 1) AS distancia_promedio
    FROM yellow
    GROUP BY vendor, paytype
    ORDER BY vendor, ingresos DESC
""", "Analisis por proveedor y tipo de pago")

# ============================
# PASO 4: Crear tabla curada con CTAS (Create Table As Select)
# ============================
print(f"\n{'='*60}")
print("PASO 4: Crear tabla curada en formato Parquet")
print("=" * 60)
print("  CTAS convierte CSV a Parquet y guarda en una nueva ubicacion S3.")
print("  Parquet es columnar y comprimido, lo que reduce costos de queries.")

# Primero eliminar la tabla si ya existe (para poder re-ejecutar)
try:
    ejecutar("DROP TABLE IF EXISTS curated_tarjeta", "Limpiar tabla anterior si existe")
except:
    pass

ejecutar(f"""
    CREATE TABLE curated_tarjeta
    WITH (
        format = 'PARQUET',
        external_location = 's3://{bucket_name}/curated/taxis/2017/tarjeta/'
    ) AS
    SELECT
        vendor,
        pickup,
        dropoff,
        count,
        distance,
        fare,
        tip,
        total
    FROM yellow
    WHERE paytype = '1'
""", "Crear tabla curada: solo pagos con tarjeta, formato Parquet")

# ============================
# PASO 5: Comparar rendimiento CSV vs. Parquet
# ============================
print(f"\n{'='*60}")
print("PASO 5: Comparar CSV original vs. Parquet curado")
print("=" * 60)

ejecutar(
    "SELECT SUM(total) AS ingresos_tarjeta FROM yellow WHERE paytype = '1'",
    "Query sobre CSV original (escanea todo)"
)

ejecutar(
    "SELECT SUM(total) AS ingresos_tarjeta FROM curated_tarjeta",
    "Query sobre Parquet curado (escanea menos datos)"
)

# ============================
# PASO 6: Verificar datos curados en S3
# ============================
print(f"\n{'='*60}")
print("PASO 6: Verificar datos curados en S3")
print("=" * 60)
response = s3.list_objects_v2(Bucket=bucket_name, Prefix='curated/')
if 'Contents' in response:
    for obj in response['Contents']:
        print(f"  {obj['Key']}  ({obj['Size']:,} bytes)")
    curated_size = sum(obj['Size'] for obj in response['Contents'])
    print(f"\n  Tamano datos curados (Parquet): {curated_size:,} bytes")
    print(f"  Tamano datos originales (CSV): {total_size:,} bytes")
    if total_size > 0:
        ratio = (1 - curated_size / total_size) * 100
        print(f"  Reduccion: {ratio:.1f}%")

print(f"\n{'='*60}")
print("PIPELINE COMPLETO")
print("=" * 60)
print("""
Flujo ejecutado:
  1. S3 (landing/)     -> Datos CSV crudos almacenados
  2. Glue (catalogo)   -> Schema definido sobre los datos
  3. Athena (queries)  -> Consultas SQL ejecutadas
  4. Athena (CTAS)     -> Datos transformados a Parquet
  5. S3 (curated/)     -> Datos optimizados almacenados

Este es el mismo flujo que ejecutaras en el lab, pero a mayor escala.
""")
```

---

## Ejercicio 5: Limpieza de Recursos

Siempre limpiar los recursos al terminar para evitar costos inesperados:

```python
# Guardar como limpiar_recursos.py
import boto3

bucket_name = 'datalake-taxi-TUAPELLIDO-2017'  # CAMBIAR
database = 'taxidata_practica'

s3 = boto3.resource('s3')
glue = boto3.client('glue')
athena = boto3.client('athena')

print("=== LIMPIEZA DE RECURSOS ===\n")

# 1. Eliminar vistas y tablas de Athena/Glue
print("1. Eliminando tablas y vistas del catalogo de Glue...")
tables_response = glue.get_tables(DatabaseName=database)
for table in tables_response['TableList']:
    glue.delete_table(DatabaseName=database, Name=table['Name'])
    print(f"   Tabla eliminada: {table['Name']}")

# 2. Eliminar la base de datos de Glue
print("\n2. Eliminando base de datos de Glue...")
glue.delete_database(Name=database)
print(f"   Base de datos eliminada: {database}")

# 3. Vaciar y eliminar el bucket de S3
print(f"\n3. Vaciando bucket S3: {bucket_name}...")
bucket = s3.Bucket(bucket_name)
bucket.objects.all().delete()
print("   Objetos eliminados.")
bucket.delete()
print(f"   Bucket eliminado: {bucket_name}")

# 4. Eliminar workgroup de Athena (si se creo)
print("\n4. Eliminando workgroup de Athena...")
try:
    athena.delete_work_group(
        WorkGroup='practica-workgroup',
        RecursiveDeleteOption=True
    )
    print("   Workgroup eliminado: practica-workgroup")
except:
    print("   No se encontro workgroup practica-workgroup (OK)")

# 5. Eliminar crawler de Glue (si se creo)
print("\n5. Eliminando crawler de Glue...")
try:
    glue.delete_crawler(Name='taxi-crawler-practica')
    print("   Crawler eliminado: taxi-crawler-practica")
except:
    print("   No se encontro crawler (OK)")

print("\n=== LIMPIEZA COMPLETA ===")
```

---

## Conexion con el Lab: Que Esperar

Ahora que completaste los ejercicios individuales, el lab "Querying Data by Using Athena" deberia ser mucho mas claro. Aqui esta el mapeo directo:

|Lo que practicaste|Tarea del Lab|Diferencia en el Lab|
|---|---|---|
|Crear bucket y subir CSV a S3|Pre-configurado|El bucket y datos ya existen; no los creas tu|
|Crear base de datos en Glue|Tarea 1|Lo haces con `CREATE DATABASE` en Athena (que crea la DB en Glue)|
|Definir schema de tabla|Tarea 1|Usas "Bulk add columns" en Athena (interfaz visual de Glue)|
|Comparar queries completo vs. bucketizado|Tarea 2|Dataset real: ~9 GB completo vs. ~3 GB enero|
|Crear tabla curada con CTAS en Parquet|Tarea 3|Crean tabla `creditcard` con formato Parquet particionado por paytype|
|Crear vistas SQL|Tarea 4|Crean `cctrips`, `cashtrips`, y `comparepay`|
|(No cubierto aqui)|Tarea 5|Crear Athena named queries con CloudFormation|
|(No cubierto aqui)|Tareas 6-7|IAM policies para controlar acceso|

### Conceptos que ahora deberias poder explicar:

1. **Por que Athena cobra por datos escaneados:** Athena lee los datos directamente de S3. Menos datos = menos costo.
2. **Que es schema-on-read:** El schema en Glue se aplica cuando lees, no cuando escribes. Los datos en S3 son archivos planos.
3. **Cuando usar buckets vs. particiones:** Buckets para alta cardinalidad (fechas, timestamps), particiones para baja cardinalidad (tipo de pago, region).
4. **Por que Parquet reduce costos:** Es columnar y comprimido. Si tu query solo necesita 3 de 17 columnas, Athena solo lee esas 3.
5. **Que hace AWS Glue:** Es un catalogo de metadatos. No almacena datos, almacena la descripcion de los datos.

---

## Preguntas de Discusion para Clase

1. **Escenario:** Una empresa de e-commerce tiene 500 GB de logs de clickstream diarios. Quieren analizar patrones de compra por region y por categoria de producto. Disenar la estructura de zonas en S3 y decidir que columnas usar para particionar.
    
2. **Trade-off:** Un data engineer propone convertir todos los CSV a Parquet inmediatamente al llegar a la zona landing. Un data scientist se opone porque quiere acceso al CSV original para validacion. Quien tiene razon y como resolver el conflicto?
    
3. **Costo real:** Con el dataset del lab (9.32 GB), cada query sobre la tabla `yellow` cuesta aproximadamente $0.05 USD. Si un equipo de 10 analistas ejecuta 50 queries diarios cada uno, cual es el costo mensual? Que estrategias de las que aprendiste aplicarias para reducirlo?
    
4. **Seguridad:** En la Tarea 7 del lab, Mary puede ejecutar named queries pero no crear buckets nuevos. Por que es esto una buena practica? Relacionar con el principio de least privilege del Well-Architected Framework (slides 6-9).