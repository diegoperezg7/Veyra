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

## Pendiente de revisar

Puntos donde el cálculo actual es discutiblemente generoso:

1. **Fases del sueño** puntúan 85 por ser *tu propia media*, no por acercarse a
   los rangos publicados. Alguien con arquitectura pobre pero constante obtiene
   una nota alta. Debería medirse contra N3 15–25% y REM 20–25%.
2. **Eficiencia** se mapea directa: 80% (el límite inferior de lo normal) da 80
   puntos. La banda útil debería ocupar más escala.
3. **Continuidad** perdona hasta 10 minutos de vigilia y penaliza 0,8 por minuto
   después; los datos normativos de WASO sugieren ser más estricto.
4. **Duración** satura en 100 al alcanzar la necesidad y no distingue dormir de
   más, que se asocia con peores desenlaces.

---

## Lo que un usuario podría querer y no calculamos

| Métrica | Por qué interesa | Viabilidad |
| --- | --- | --- |
| **Desviación de temperatura de muñeca** | Enfermedad, alcohol y fase del ciclo la mueven antes que otros signos | Alta: ya leemos el tipo, falta la línea base |
| **Alteraciones respiratorias durante el sueño** | Apple publica el tipo desde iOS 18; es un cribado de apnea | Alta: añadir el tipo al catálogo |
| **Punto medio del sueño / cronotipo** | Explica el desfase social y la somnolencia diurna | Alta: derivable de las sesiones |
| **Notificaciones de ritmo irregular / fibrilación** | HealthKit expone la carga de FA | Media: tipo aparte |
| **Estabilidad al caminar** | Apple la calcula y predice riesgo de caída | Media |
| **Presión arterial con bandas** | La leemos pero no la clasificamos | Alta: bandas de la ESC/AHA |
| **Percentil de VO₂máx** | Más informativo que la cifra suelta | Alta: ya tenemos las curvas |
| **Tiempo en zonas por semana** | Contrasta con las guías de la OMS | Alta |

Ninguna de estas requiere inventar nada: todas tienen una referencia publicada o
las expone Apple directamente.
