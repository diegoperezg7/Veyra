# Veyra — revisión del 13 de septiembre de 2026

## Alcance de esta revisión

Rediseño de modo claro, gráficas, motores de cálculo, ajustes, sincronización y
widgets. Eliminación del chat de inteligencia y del apartado de nutrición.

## Eliminado

- **Chat de inteligencia**: `CoachView`, `ChatMessage`, `AppModel.ask/summary/localAdvice`,
  `RemoteCoachingProvider` y `KeychainStore` completo (solo servía a la IA). Los
  ajustes de IA, el estilo de coaching y la memoria editable desaparecen de
  `UserPreferences`.
- **Nutrición**: `NutritionView`, `FoodItem`, `OpenFoodFactsProvider`,
  `OCRService.nutrients`, `HealthCatalog.nutrition`, `writeNutrition`, los
  objetivos nutricionales, la tarjeta de inicio y el registro de agua del reloj.
  `OCRService` se conserva porque lo usa la importación de informes médicos.
- Permisos ya innecesarios: cámara y fototeca.

## Pestañas

`Inicio · Fitness · Biología · Tendencias`. Tendencias es nueva y reúne la
evolución de las cinco puntuaciones, la edad de bienestar y las correlaciones de
hábitos que antes estaban enterradas en una sección del diario.

## Paleta

Se mantiene el verde del logo (`#27F6CC`). Sobre blanco puro da 1.39:1 y es
ilegible, así que texto e iconos usan `#0A7F68` (4.94:1) y los rellenos grandes
`#0E9C7F` (3.45:1, por encima del 3:1 exigido a gráficos). Fondo blanco puro en
claro y negro puro en oscuro; las superficies se separan con borde y elevación.

El acento es verde, así que la escala de estado de los gauges evita esa familia:
verde bosque → ámbar → naranja → rojo, y el acento queda reservado a la marca.

## Corregido

- `DaySignalCard`, `BodyBatteryCard`, `SleepHeroCard` y `BiologyHero` estaban
  pintadas con degradados oscuros fijos y texto blanco: en modo claro eran
  manchas negras. Ahora usan escenas con versión clara y oscura.
- `PageAtmosphere` teñía el fondo de gris azulado con tres manchas de color.
  Eliminado.
- `ScoreRing` usaba un degradado angular terminado en blanco (invisible en
  claro) y una sombra que difuminaba el trazo.
- `HealthTrendChart` generaba una serie de Swift Charts por cada par de puntos
  consecutivos: 364 series para un año.
- FC máxima fija en 185 bpm al calcular zonas cardíacas.
- FC en reposo de referencia tomada como mediana de toda la ventana importada.
- Contribuyente de movimiento del estrés alimentado siempre con cero.
- Contribuyente `hrDip` del sueño (peso 5) recibía siempre `nil`.
- La carga de fuerza no entraba en el esfuerzo.
- `publish()` enviaba `history.last` al reloj y a los widgets en vez del día actual.
- `CardioLoadEngine` en Fitness se alimentaba de `zoneMinutes` mientras el
  esfuerzo usaba `rawLoad`.
- Aviso vivo de código inalcanzable en `Shared/Connectivity.swift`.

## Nuevo

- `ConfidenceEngine`: confianza en porcentaje con cobertura, madurez y recencia,
  y las razones concretas de la penalización mostradas al usuario.
- `MetricScenes`: cinco escenas vectoriales, una por métrica, con versión clara
  y oscura del mismo paisaje. Sin imágenes de terceros ni dependencias.
- `MetricGauge`: velocímetro abierto por abajo para el estrés.
- `BatteryPill` + desglose: recarga por sueño y descanso, gasto por estrés,
  ejercicio y vigilia.
- `MetricNarrator`: resumen local y determinista por métrica, en claves de
  localización, que sustituye al chat.
- Edad de bienestar desde el primer día, con margen y confianza que se estrechan.
- `BGTaskScheduler` y observadores de HealthKit ampliados a nueve tipos.
- Píldora de sincronización con progreso determinado, fase y confirmación.
- Widgets con anillo, pila de batería y resumen de tres puntuaciones.

## Compatibilidad de datos

`LocalStore.load` borra los registros que no decodifican, así que un campo nuevo
obligatorio destruiría el historial. Todos los campos añadidos son opcionales y
`UserPreferences` tiene un `init(from:)` explícito con `decodeIfPresent`. Hay
tests que decodifican preferencias y snapshots del formato anterior.

## Validación ejecutada

- Compilación de Veyra con Watch y las dos extensiones de widgets: correcta.
- PulseCore: 18 pruebas, 0 fallos.
- Suite de la app en simulador: ver sección siguiente.

## Límites

HealthKit no funciona en el simulador, así que **nada de lo siguiente está
verificado con datos reales**: los cálculos con sensores, la sincronización con
el Apple Watch, la entrega en segundo plano, `BGTaskScheduler`, las
complicaciones y la alarma inteligente. Eso solo queda comprobado al instalar en
un iPhone y un Apple Watch reales.

Tampoco se han revisado todos los tamaños de Dynamic Type ni todas las pantallas
secundarias, y las escenas ilustradas no se han contrastado con capturas reales
de Bevel: son una interpretación del patrón descrito, no una réplica.

La batería corporal y la edad de bienestar siguen siendo estimaciones
experimentales de confianza baja, no medidas clínicas ni algoritmos de Bevel.
