# Recursos para mejorar Veyra

Revisión realizada el 7 de septiembre de 2026. Estos proyectos se usan como
referencia de arquitectura, interacción y validación. No se copia código, marca,
iconografía ni fórmulas propietarias de otras aplicaciones.

## Repositorios recomendados

| Repositorio | Licencia / estado | Qué aporta a Veyra | Decisión |
| --- | --- | --- | --- |
| [SleepChartKit](https://github.com/DanielJamesTronca/SleepChartKit) | MIT, activo | Línea temporal de sueño con fases, selección y leyenda de duraciones | Ya se ha reproducido el patrón con Swift Charts nativo para evitar una dependencia externa |
| [Whoordan](https://github.com/W4rd2/whoordan) | Apache-2.0 | Separación `Core`/`Features`/`DesignSystem`, procedencia por fuente, confianza, BLE y pruebas | Adoptar sus límites de arquitectura y trazabilidad; no adoptar su puerta Supabase ni sus logos |
| [GenieMax Core](https://github.com/satayutata/geniemax-core) | MIT | Paquete Swift puro, fórmulas escritas, golden vectors y pruebas de HRV, sueño, carga y edad | Revisar como material didáctico; comparar vectores, sin sustituir `PulseCore` automáticamente |
| [Soma](https://github.com/heisenbuggs/Soma) | Código local-only; comprobar `LICENSE` antes de reutilizar | Cuatro puntuaciones, zonas cardíacas, datos inyectables y refresco en segundo plano | Útil para casos límite y nomenclatura; Veyra mantiene sus propios pesos y etiquetas |
| [Steps](https://github.com/brittanyarima/Steps) | MIT, archivado | Permisos HealthKit, MVVM, Swift Charts, widgets y notificaciones | Referencia de integración; no se incorpora por estar archivado |
| [Health Dashboard Export](https://github.com/baccula/health-dashboard-export) | Revisar licencia del repositorio | Exportación incremental, Keychain y `BGTaskScheduler` | Aplicar únicamente el patrón de sincronización programada local |
| [SwiftUICharts](https://github.com/sanjaynela/SwiftUICharts) | Ejemplo educativo; revisar licencia antes de reutilizar | `RuleMark`, anotaciones, bandas objetivo, área + línea y `ImageRenderer` | Usar los patrones visuales en componentes propios |
| [IronPath](https://github.com/Gabriel-Hollenbeck22/IronPath) | MIT | Rutinas, progresión, recetas, Open Food Facts, widgets y estructura de fitness | Referencia para Fitness/Nutrición; revisar cada dependencia antes de añadirla |
| [Aura Health](https://github.com/madebysan/aura-health) | MIT | SwiftData local, biomarcadores, informes PDF/foto revisables y asistente con clave propia | Adoptar el flujo “extraer → revisar → guardar” para documentos; IA sigue desactivada por defecto |

## Qué debe mejorar el diseño

Las referencias de plataforma son [Materials de Apple](https://developer.apple.com/design/human-interface-guidelines/materials),
[SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
y [Motion](https://developer.apple.com/design/human-interface-guidelines/motion):
materiales para profundidad, símbolos jerárquicos o multicolor y animaciones
breves que expliquen un cambio de estado. La app no debe usar un efecto solo por
su color ni animar todo de forma permanente.

1. Mantener un único `DesignSystem` para fondos, tarjetas, radios, sombras,
   tipografía, estados vacío/cargando y colores semánticos. Cada pantalla debe
   componerse de esas piezas, no de colores ad-hoc.
2. Aplicar el patrón de gráficos de [SwiftUI Charts](https://developer.apple.com/documentation/charts):
   área suave para el contexto, línea de lectura, regla al tocar, banda de
   referencia y resumen numérico encima. Los valores deben conservar unidades,
   fecha y fuente.
3. En modo claro usar fondo marfil frío con aurora turquesa/azul de baja opacidad;
   en oscuro usar azul petróleo con glow turquesa. El contraste de texto se
   comprueba con Dynamic Type y VoiceOver, sin depender solo del color.
4. Cada tarjeta de métrica debe mostrar valor, rango personal, tendencia,
   confianza y explicación breve. “Sin datos” y “calibrando” son estados de
   primera clase y no se deben rellenar con ceros.
5. Animar solo cambios de estado y selección de datos (`opacity`, `scaleEffect`,
   `interpolatingSpring`). No animar continuamente las gráficas ni bloquear el
   hilo principal durante una sincronización.

## Referencias para calcular los datos

### Sueño

- [HealthKit sleep analysis](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)
  define las categorías de sueño y permite combinar muestras de “en cama” con
  fases detalladas. Las muestras pueden solaparse y una noche puede carecer de
  los límites exactos; por eso Veyra debe unir intervalos, dar prioridad a la
  fase detallada y marcar la confianza cuando falten extremos.
- [WWDC22: sleep stages](https://developer.apple.com/videos/play/wwdc2022/10005/)
  muestra el modelo de muestras continuas por fase. La duración dormida,
  latencia, eficiencia, despertares y porcentaje de fases deben salir de esos
  intervalos normalizados, respetando zona horaria y cambios DST.
- El consenso [AASM/SRS](https://pmc.ncbi.nlm.nih.gov/articles/PMC4442216/)
  recomienda para adultos dormir al menos 7 horas de forma regular y recuerda
  que la calidad también incluye horario, regularidad y ausencia de
  interrupciones. Es una referencia de contexto, no un objetivo rígido para
  todas las personas.

### HRV, frecuencia cardíaca y estrés

- [HealthKit HRV SDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn)
  representa SDNN en milisegundos a partir de intervalos entre latidos. No se
  debe tratar como RMSSD ni convertir una muestra de BPM en HRV.
- Las [normas de la Task Force de HRV](https://pubmed.ncbi.nlm.nih.gov/8598068/)
  sirven para documentar unidades, ventanas y límites de interpretación. Veyra
  usa una línea base personal robusta (mediana/MAD), excluye ejercicio del
  estrés y devuelve baja confianza con pocas observaciones.
- El estrés de Veyra es activación fisiológica estimada. No diagnostica estrés
  psicológico: si no hay línea base o datos suficientes, muestra calibración y
  no fabrica una puntuación.

### Carga y esfuerzo

- La revisión de [Session-RPE](https://pmc.ncbi.nlm.nih.gov/articles/PMC5673663/)
  documenta la carga como `RPE × duración en minutos` y describe TRIMP y las
  zonas de Edwards. La revisión también advierte que TRIMP, zonas y sRPE no son
  intercambiables.
- Veyra conserva una carga por zonas cardíacas con límites explícitos y la
  acota a 0–100 para presentación. Las duraciones entre muestras pasivas se
  limitan para no convertir un hueco de HealthKit en esfuerzo ficticio. Para
  fuerza se muestra carga de series y RPE separado; el pulso por sí solo no
  estima carga muscular.
- Cualquier evolución a TRIMP individual, sRPE, CTL/ATL/TSB o monotony debe
  entrar como algoritmo versionado con vectores de prueba y etiqueta
  experimental. No se presenta como “la fórmula de Bevel”.

### Energía / batería corporal y edad biológica

- La batería corporal de Veyra es una estimación local 0–100 basada en sueño,
  recuperación, estrés observado y carga. Cada punto conserva versión,
  contribuyentes, ausencias y confianza; sin datos suficientes no hay score.
- La edad biológica es experimental y transparente: solo se calcula con inputs
  reales, se muestran los contribuyentes y el intervalo de incertidumbre. No se
  presenta como una medición clínica ni como una réplica del algoritmo de otra
  app.

## Plan de incorporación

1. Convertir los estilos de gráfico anteriores en componentes reutilizables:
   `MetricHeader`, `ReferenceBand`, `TrendChart`, `SleepStageTimeline` y
   `ConfidenceBadge`.
2. Añadir golden vectors para sueño fragmentado, cambio horario, duplicados,
   huecos de frecuencia cardíaca, valores extremos y sensores ausentes.
3. Medir primero con datos sintéticos y después contrastar con una exportación
   propia de Apple Health. Los datos reales no se guardan en el repositorio.
4. Registrar en cada resultado la versión del algoritmo y recalcular solo las
   fechas afectadas por una nueva muestra o una eliminación.
5. Revisar licencias y atribuciones antes de incluir cualquier paquete. Las
   dependencias visuales externas no son necesarias mientras Swift Charts cubra
   el producto.
