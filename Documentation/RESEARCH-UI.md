# Referencias de producto y UI

La disposición de Inicio se alinea con la información pública de Bevel: resumen diario de Esfuerzo, Recuperación y Sueño; coaching contextual; después monitor de salud, actividad y nutrición. Bevel documenta que las puntuaciones de sueño y recuperación requieren una noche completa con HRV y frecuencia cardiaca en reposo, por lo que Veyra conserva estados de calibración cuando faltan datos.

Referencias consultadas el 7 de septiembre de 2026:

- [Catálogo oficial de funciones de Bevel](https://help.bevel.health/en/articles/11194113)
- [FAQ oficial sobre Sleep, Recovery y Strain](https://help.bevel.health/en/articles/11257601)
- [Apple Swift Charts](https://developer.apple.com/documentation/charts)
- [SleepChartKit, MIT](https://github.com/DanielJamesTronca/SleepChartKit) — referencia de interacción y etapas de sueño, no dependencia del producto.
- [health-dashboard-app-swift](https://github.com/hmnshudhmn24/health-dashboard-app-swift) — referencia de dashboard HealthKit, no código integrado.

No se han importado repositorios de terceros en el binario. Se han adoptado patrones equivalentes con Swift Charts nativo, manteniendo cálculos locales y trazabilidad de datos.
