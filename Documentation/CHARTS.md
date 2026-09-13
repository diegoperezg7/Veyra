# Gráficas de sueño y Apple Health

## Referencias revisadas

- [SleepChartKit](https://github.com/DanielJamesTronca/SleepChartKit): paquete SwiftUI con timeline de fases, selección temporal, leyenda de duraciones y adaptación a HealthKit. Tiene licencia MIT.
- [Swift Health Dashboard](https://github.com/hmnshudhmn24/health-dashboard-app-swift): ejemplo de dashboard SwiftUI + HealthKit con tendencias de sueño, frecuencia cardíaca y actividad.
- [Apple Health Dashboard](https://github.com/nixfred/apple-health-dashboard): referencia de producto para tendencias de 30 días, composición de fases y horarios; requiere exportación local de Health Auto Export y un servidor, por lo que no se incorpora como dependencia móvil.
- [SwiftUICharts](https://github.com/sanjaynela/SwiftUICharts): ejemplo educativo de `RuleMark`, anotaciones, bandas objetivo, área + línea, temas y exportación con `ImageRenderer`; se usa como referencia de interacción.
- [Soma](https://github.com/heisenbuggs/Soma): dashboard local de recuperación, esfuerzo, sueño y estrés con datos inyectables para pruebas; se revisa para estados de calibración y categorías, no para copiar pesos.
- [GenieMax Core](https://github.com/satayutata/geniemax-core): motor Swift MIT con fórmulas y golden vectors para validar el enfoque de pruebas de `PulseCore`.
- [Apple WWDC22 — HealthKit](https://developer.apple.com/videos/play/wwdc2022/10005/): Apple recomienda crear una muestra por cada periodo continuo de una fase del sueño.

## Implementación en Veyra

Veyra mantiene el procesamiento local y usa Swift Charts del SDK. `SleepStageTimeline` presenta las muestras ya normalizadas por `SleepEngine`, evitando superposiciones entre fuentes y mostrando:

- filas separadas para despierto, REM, núcleo, profundo, sueño no especificado y en cama;
- bloques proporcionales a la duración real de cada periodo;
- ejes de hora, rejilla tenue y selección para inspeccionar una fase;
- colores diferenciados y adaptados al modo claro/oscuro;
- leyenda compacta con la duración de cada fase.

No se ha copiado código del repositorio externo. Se ha usado como referencia visual y de arquitectura, manteniendo el modelo de datos y las reglas de selección de fuente de Veyra.
