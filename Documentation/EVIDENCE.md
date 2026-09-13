# Auditoría de fundamento científico

Revisión del 13 de septiembre de 2026. Para cada cálculo: qué está respaldado
por literatura publicada, qué es una decisión de diseño, y qué falta.

La distinción importa. Una app de salud que presenta un juicio propio como si
fuera un hallazgo publicado engaña, aunque el juicio sea razonable.

| Nivel | Significado |
| --- | --- |
| **Publicado** | La fórmula o el umbral viene de literatura revisada por pares y se cita |
| **Derivado** | La dirección y la escala vienen de literatura; la combinación concreta es nuestra |
| **Diseño** | Decisión nuestra, sin equivalente publicado. Etiquetada como estimación en la app |

---

## Publicado

### Zonas cardíacas y carga de esfuerzo
Reserva de frecuencia cardíaca (Karvonen) y carga de Edwards por zonas:
`minutos × nivel de zona`. La revisión de
[Session-RPE](https://pmc.ncbi.nlm.nih.gov/articles/PMC5673663/) documenta TRIMP,
zonas de Edwards y sRPE, y advierte de que no son intercambiables — por eso
Veyra no los mezcla.

### Estrés: activación por reserva cardíaca
`reserva = (FC − reposo) / (máxima − reposo)`. Acotado por construcción, mismo
significado para un corazón entrenado y uno no entrenado. El umbral del 45% de
reserva como activación plena es **derivado**.

### Edad de forma física
Curvas normativas de VO₂máx por edad y sexo
([ACSM, 11.ª ed.](https://openspiro.com/knowledge/vo2max-reference-values/),
registro [FRIEND](https://www.mayoclinicproceedings.org/article/S0025-6196(15)00642-4/pdf)),
invertidas para obtener una edad. Es la única parte de la estimación con una
referencia externa verificable.

### Índice de regularidad del sueño (SRI)
`SRI = −100 + 200 × P(mismo estado 24 h después)`. Phillips et al. lo
introdujeron; el análisis de
[UK Biobank sobre 60 000 personas](https://academic.oup.com/sleep/article/47/1/zsad253/7280269)
lo encontró **mejor predictor de mortalidad que la duración del sueño**.
Sustituye a la desviación circular de horarios, que solo mide dispersión
alrededor de tu propia media y no ve una racha de noches alternas.

### Recuperación cardíaca al minuto
Una caída de ≤12 lpm en el primer minuto es el punto de corte clásico
([Cole et al., NEJM 1999](https://www.nejm.org/doi/full/10.1056/NEJM199910283411804)),
asociado a unas cuatro veces el riesgo de mortalidad a seis años.

### Escalas de composición corporal
IMC de la OMS (18,5 / 25 / 30) y bandas de grasa corporal de ACE, específicas
por sexo. Son escalas de población, no objetivos personales, y el IMC no
distingue músculo de grasa — por eso se muestra junto al porcentaje de grasa.

### Arquitectura del sueño
N3 15–25% y REM 20–25% del tiempo dormido en adultos; eficiencia ≥80% normal,
>90% en adultos jóvenes sanos
([JCSM, datos normativos](https://pmc.ncbi.nlm.nih.gov/articles/PMC5886429/)).

### Línea base personal
Mediana y desviación absoluta mediana × 1,4826, z acotada a ±3. Estadística
robusta estándar; resiste valores extremos como no lo hace una media con
desviación típica.

---

## Derivado

### Carga aguda/crónica
Medias móviles exponenciales a 7 y 42 días. El marco es de
[Gabbett](https://pubmed.ncbi.nlm.nih.gov/26758673/) y está **discutido**: las
críticas metodológicas posteriores son serias. Veyra lo presenta como tendencia
de entrenamiento y dice explícitamente que no predice lesiones.

### Necesidad y deuda de sueño
El consenso [AASM/SRS](https://pmc.ncbi.nlm.nih.gov/articles/PMC4442216/)
recomienda ≥7 h regulares para adultos. Que la necesidad suba con la deuda
acumulada y con el esfuerzo del día anterior es razonable y no está cuantificado
en la literatura: los coeficientes (0,35 y 0,4) son **nuestros**.

### Edad biológica: correcciones
Cada señal tiene dirección respaldada — FC en reposo alta peor, VFC baja peor,
150 min/semana de la OMS, 7 500 pasos donde la curva de mortalidad se aplana.
**Los pesos concretos (35/15/12/10/10/8/5/5) son una decisión nuestra.** No
existe un modelo publicado que combine estas señales de wearable en una edad.

---

## Diseño

### Reservas de energía (batería corporal)
**No tiene equivalente publicado.** Es un modelo de balance: el sueño recarga,
la vigilia gasta, el estrés y el ejercicio aceleran el gasto. Los coeficientes
son nuestros y están escritos en `ALGORITHMS.md`. La app la etiqueta como
estimación experimental.

### Puntuación de recuperación
Los pesos (VFC 30, FC reposo 20, sueño 25, respiración 10, temperatura 10,
SpO₂ 5) **no salen de ningún artículo**. Cada componente tiene dirección
respaldada, pero la combinación es un juicio. Es la parte menos fundamentada de
la app y conviene saberlo.

### Puntuación de sueño
Los componentes tienen referencia; los pesos (35/20/15/15/10/5) son nuestros.

---

## Revisado (algoritmo v4)

Los cuatro puntos donde el sueño era discutiblemente generoso, y en qué han
quedado. Cada curva tiene un vector de prueba en `SleepScoreTests`.

1. **Fases del sueño.** Antes puntuaban 85 por ser *tu propia media*: alguien con
   arquitectura pobre pero constante sacaba buena nota. Ahora se miden contra los
   rangos publicados del adulto — N3 15–25% y REM 20–25% del sueño total — con
   penalización fuerte por defecto (la mitad del límite inferior da cero) y suave
   por exceso, porque el exceso de sueño restaurador no es en sí un problema. Una
   noche que la fuente entrega sin fases devuelve nil en vez de inventar.
2. **Eficiencia.** Antes se mapeaba directa y 80% — el límite inferior de lo
   normal — daba 80 puntos, un notable. Ahora la escala se estira entre 65% y 95%,
   así que ese mismo 80% queda en 50: un aprobado.
3. **Continuidad.** Antes perdonaba 10 minutos de vigilia y penalizaba 0,8 por
   minuto. Los datos normativos de WASO en adultos sanos llegan a unos 30 minutos,
   así que ahora se perdonan 20 y la pendiente sube a 1,2: una hora despierto pasa
   de 60 puntos a 52.
4. **Duración.** Antes saturaba en 100 y trataba igual 8 horas que 12. Ahora hace
   pico en la necesidad estimada y decae a partir del 115% de ella, porque dormir
   mucho de más se asocia con peores desenlaces y casi siempre señala deuda o
   enfermedad.

También cambia el dip de frecuencia cardíaca nocturna: antes cualquier caída del
20% ya saturaba el componente; ahora la escala va de 5% a 20%, que es el rango en
el que el descenso nocturno discrimina.

---

## Implementado a partir de la lista anterior

Todas las métricas que faltaban están calculadas. Ninguna inventa un umbral: o la
banda es de la literatura, o el umbral lo publica Apple y se lee de HealthKit.

| Métrica | Referencia | Dónde se ve |
| --- | --- | --- |
| **Desviación de temperatura de muñeca** | Derivada: línea base propia de ≥5 noches. No hay umbral clínico para temperatura de muñeca de consumo, y las bandas se expresan como tales | Biología → Signos de alerta |
| **Alteraciones respiratorias al dormir** | El umbral de "elevada" se lee de `HKAppleSleepingBreathingDisturbancesClassification`, no se fija aquí | Biología → Signos de alerta |
| **Punto medio del sueño / cronotipo** | Cortes del MCTQ (Roenneberg). Es el punto medio sin corregir: MSFsc necesita separar días libres de laborables, que no distinguimos con fiabilidad | Biología → Signos de alerta |
| **Carga de fibrilación auricular** | Terciles de KP-RHYTHM (Go et al., JAMA Cardiol 2018); el corte alto en 11,4% | Biología → Signos de alerta |
| **Notificaciones de ritmo irregular** | Recuento de eventos de los últimos 90 días | Biología → Signos de alerta |
| **Estabilidad al caminar** | Umbrales de `HKAppleWalkingSteadinessClassification` | Biología → Signos de alerta |
| **Presión arterial** | ACC/AHA 2017 y, en paralelo, ESC/ESH 2023, que discrepan: 135/85 es grado 1 en Estados Unidos y normal-alta en Europa. Se muestran ambas. Clasifica sobre la mediana de varias tomas, nunca sobre una | Biología → Signos de alerta |
| **Percentil de VO₂máx** | Mediana de la misma curva ACSM que usa la edad de bienestar, con aproximación normal a la dispersión del registro FRIEND (DE 7 hombres, 6 mujeres). Es una cifra derivada: no leer más de unos pocos puntos de precisión | Fitness → Frente a la población |
| **Tiempo en zonas por semana** | OMS 2020: 150–300 min moderados o 75–150 vigorosos; los vigorosos cuentan doble. Intensidad por reserva cardíaca según ACSM. Estimación conservadora: andar rápido por debajo del 50% de reserva no se cuenta | Fitness → Frente a la población |

---

## Registro de fuerza

El registro de entrenamiento no estima nada: guarda lo que levantaste. Las dos
cifras derivadas son estas.

| Cálculo | Nivel | Fundamento |
| --- | --- | --- |
| **Volumen** | Publicado | `repeticiones × peso`, sumado solo sobre las series marcadas. Es la definición estándar de volumen de carga en la literatura de entrenamiento de fuerza |
| **1RM estimado** | Publicado | Fórmula de Epley, `peso × (1 + reps/30)`, limitada a 1–12 repeticiones porque su error crece deprisa por encima |
| **Volumen por grupo muscular** | Diseño | Cada serie cuenta entera para su músculo primario y nada para los secundarios. Repartirla implicaría una precisión que el catálogo no tiene |
| **Peso sugerido** | — | No es una estimación: es lo que levantaste la última vez en ese ejercicio. Un ejercicio sin historial abre en blanco. Veyra no propone un peso "normal para tu peso corporal": esas tablas no son fiables y un número inventado en un campo es peor que un campo vacío |

Las series con peso corporal aportan cero al volumen, porque la app no sabe qué
fracción de tu peso levanta cada movimiento.

---

## Detalle de un entrenamiento

| Cálculo | Nivel | Fundamento |
| --- | --- | --- |
| **Zonas de frecuencia cardíaca** | Publicado | Reserva cardíaca (Karvonen). Z1 empieza en el 50% y cada zona abarca un 10%. Z0 es todo lo que queda por debajo: calentamiento y descansos |
| **Carga cardíaca de la sesión** | Publicado | Carga de Edwards: minutos en cada zona por el número de zona. El tiempo en Z0 no suma, que es justamente el punto del método |
| **Intensidad** | Publicado | La media de la sesión expresada como porcentaje de reserva cardíaca, que es la forma comparable entre personas y sesiones |
| **Foco cardiovascular** | Derivado | Modelo de tres zonas (Seiler): por debajo del primer umbral ventilatorio, entre los dos, y por encima del segundo. Sobre reserva cardíaca, VT1 ronda el 70% y VT2 el 90%, así que Z0–Z2 es aeróbico bajo, Z3–Z4 alto y Z5 anaeróbico. **Los umbrales son individuales**: estos son medias poblacionales y la app lo dice en la propia tarjeta |
| **Recuperación cardíaca** | Publicado | La medición del propio reloj (`heartRateRecoveryOneMinute`), asociada al entrenamiento que la precede. Las bandas siguen a Cole et al., NEJM 1999, con 12 lpm como umbral |
| **Comparación con lo habitual** | Derivado | Carga de esta sesión contra la mediana de las anteriores. Necesita al menos cuatro sesiones previas; por debajo de eso devuelve nada en vez de un número sin sentido |

La serie de pulso se submuestrea a un punto por minuto quedándose con el
**máximo** de cada intervalo, no con la media: promediar borra los picos, que
son justo lo que se quiere ver.

Cuando el reloj registró pulso durante menos del 80% de la sesión, la pantalla
lo advierte: el reparto por zonas solo cubre ese tramo.

---

## Catálogo de ejercicios

268 ejercicios con ilustraciones, músculos, material e instrucciones, derivados
del [dataset de Everkinetic](https://github.com/everkinetic/data) (CC BY-SA 4.0).

Se descartó `free-exercise-db`, más conocido y con más ejercicios, porque la
procedencia de sus imágenes está sin aclarar en
[varias](https://github.com/yuhonas/free-exercise-db/issues/2)
[incidencias](https://github.com/yuhonas/free-exercise-db/issues/12) sin
respuesta. Una licencia que no se puede verificar no es una licencia.

La clasificación por grupo muscular y patrón de movimiento es **derivada**: se
normaliza a partir de los campos del origen y del nombre del ejercicio. Los
nombres y las instrucciones están traducidos al español por reglas revisadas y,
donde las reglas no llegaban, a mano.
