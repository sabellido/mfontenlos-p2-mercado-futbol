# Reto práctico de datos (Proyecto 2)
## Fútbol — Ingesta en Snowflake + Modelo Silver/Gold + Power BI

### Dataset
- Kaggle: https://www.kaggle.com/datasets/davidcariboo/player-scores  
- GitHub: https://github.com/dcaribou/transfermarkt-datasets  

---

## Objetivo
Construir un mini sistema analítico en Snowflake (RAW → SILVER → GOLD) a partir de CSVs del dataset, con **tablas materializadas** (no vistas) y un **Power BI** conectado a GOLD para responder a preguntas básicas de negocio.

---

## 1) Ingesta de CSV en Snowflake (RAW)

> 🔐 **Credenciales**: Las credenciales de Snowflake deben gestionarse como variables de entorno o en un fichero `.env` (nunca subir al repositorio). Para la carga desde Python, se puede usar `snowflake-connector-python` o `snowflake-sqlalchemy`. Añadir `.env` al `.gitignore`.

### Requisitos
- Descargar el dataset y cargar los CSV en Snowflake:
  - Crear **STAGE** (interno o externo).
  - Definir **FILE FORMAT** para CSV.
  - Cargar a tablas **RAW** con `COPY INTO`.
- Tablas RAW esperadas (según dataset):
  - `raw.players`
  - `raw.clubs`
  - `raw.competitions`
  - `raw.player_scores`
  - `raw.player_valuations`
  - `raw.appearances` *(requerido; se utiliza en la capa SILVER)*

### Controles mínimos
- Conteo de filas por tabla (antes/después).
- Detección básica de duplicados por ID.
- Tipos de dato correctos (fechas, números).

---

## 2) Limpieza y estandarización (SILVER) — SOLO SQL
### Requisitos
- Crear tablas SILVER (no vistas) con:
  - Normalización de tipos:
    - Fechas a `DATE`
    - Importes / valores a `NUMBER`
  - Limpieza:
    - Nulos y valores inválidos
    - Duplicados (reglas claras)
  - Claves consistentes (`player_id`, `club_id`, `competition_id`)
- Tablas SILVER recomendadas:
  - `silver.dim_player` (desde `raw.players`)
  - `silver.dim_club` (desde `raw.clubs`)
  - `silver.dim_competition` (desde `raw.competitions`)
  - `silver.fct_player_season` (combinación/agrupación desde `raw.player_scores` + `raw.player_valuations` + `raw.appearances`)

📌 Nota: `silver.fct_player_season` debe quedar a una granularidad clara (p.ej. **jugador-temporada-club-competición**), con métricas agregadas y justificando el criterio (media, último valor del año, etc.).

---

## 3) Modelo analítico (GOLD) — Tablas listas para Power BI
### Requisitos
- Crear tablas GOLD (no vistas) orientadas a consumo BI:
  - `gold.fact_player_season` (hechos)
  - `gold.dim_player`, `gold.dim_club`, `gold.dim_competition`, `gold.dim_season`
  - `gold.dim_date` *(tabla de fechas construida en SQL a partir de las fechas presentes en los datos; incluir al menos: fecha, año, mes, trimestre)*
- Deben estar preparadas para:
  - Relacionarse en estrella
  - Rendimiento correcto en Power BI
  - Medidas básicas (suma, media, ranking)

---

---

## 4) Power BI (conectado a GOLD)
### Requisitos del informe
- Conectar Power BI a Snowflake (schema GOLD).
- 1 página “Overview” con KPIs:
  - Nº jugadores (según filtros)
  - Valor total de mercado (o agregado elegido)
  - Score medio
- Visualizaciones mínimas:
  - Top jugadores por score
  - Evolución temporal (score y/o valor) por temporada
  - Top clubs / ligas por valor agregado
  - Scatter: score vs valor (segmentado por posición/liga)
- Filtros: temporada, liga/competición, club, posición.

---

## 5) Preguntas básicas (insights de negocio)
El dashboard debe responder, al menos, a:
- ¿Qué jugadores destacan por score en una temporada?
- ¿Qué clubs/lígas concentran mayor valor de mercado?
- ¿Cómo evoluciona el valor y el rendimiento por temporada?
- ¿Existen jugadores con score alto pero valor bajo (posibles “oportunidades”)?
- ¿Qué posiciones tienen mayor valor medio?

---

## Entregables
- Repositorio GitHub con:
  - SQL de RAW/SILVER/GOLD
  - README con arquitectura + ejecución
  - `requirements.txt` o `pyproject.toml` con las dependencias Python
  - `.gitignore` adecuado (incluir `.env`)
- Modelo Snowflake creado y ejecutable
- Power BI (`.pbix`) conectado a GOLD

---

## Criterios de evaluación

La evaluación se divide en dos partes iguales:

| Bloque | Peso | Descripción |
|---|---|---|
| **Corrección automática (IA)** | 50% | Revisión del enunciado vs. lo entregado: cobertura de requisitos, calidad del código y SQL, estructura del repositorio. |
| **Percepción personal** | 50% | Claridad en la presentación, criterio técnico demostrado, capacidad de defender las decisiones. |

**Aspectos técnicos valorados:**
- Ingesta robusta (COPY INTO, formatos, controles).
- Limpieza y tipado correctos en SILVER (SQL).
- Modelo GOLD en estrella listo para BI (tablas, no vistas).
- Dashboard claro y capaz de responder preguntas de negocio.

---

## 🎤 Presentación del proyecto

El proyecto se presentará en una sesión de **30 minutos**:

1. **Storytelling (15 min)**: Contexto del dataset de fútbol, qué datos analizaste y cuál es el insight principal. Narrativa orientada a audiencia no técnica.
2. **Arquitectura y código (15 min)**: Recorrido por la pipeline RAW→SILVER→GOLD, decisiones técnicas y dificultades encontradas.

📌 *No se trata de leer diapositivas: se valora la capacidad de explicar con claridad y defender las decisiones.*