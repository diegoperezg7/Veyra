# Fuentes de datos e integraciones

## Renpho Health

La conexión recomendada es **Renpho Health → Apple Health → Veyra**. Renpho documenta que su app puede compartir peso y composición con Apple Health. Veyra ya lee los tipos públicos que llegan a Salud: peso, porcentaje de grasa, masa magra, IMC y perímetro de cintura cuando el dispositivo y Renpho lo publiquen. No inicia sesión en Renpho ni accede a sus servidores.

1. En Renpho Health, conectar Apple Health y permitir las categorías de composición corporal.
2. En Salud → Compartir → Apps → Veyra, permitir la lectura.
3. Abrir Veyra → Biología y sincronizar. Se conserva la fecha de la última medición y no se convierte un campo ausente en cero.

Renpho puede mostrar indicadores propios que HealthKit no expone como tipos públicos. Esos se mantienen en Renpho hasta que exista una vía oficial compatible.

## 1byone Health

La conexión recomendada es **1byone Health → Apple Health → Veyra**. La ficha pública de 1byone Health indica que la aplicación puede sincronizar los datos con Apple Health y Fitbit: [App Store](https://apps.apple.com/es/app/1byone-health/id1374132894). Los manuales de sus básculas también describen la sincronización con Apple Health.

Veyra no necesita iniciar sesión en 1byone ni consultar sus servidores. Cuando la usuaria activa la exportación a Apple Health y acepta el permiso de lectura de Veyra, se incorporan las muestras que Apple Health expone para ese modelo:

- peso (`bodyMass`)
- porcentaje de grasa (`bodyFatPercentage`)
- masa magra (`leanBodyMass`)
- IMC (`bodyMassIndex`)

Apple HealthKit no ofrece tipos públicos para agua corporal, masa muscular o masa ósea en el SDK actual. Esos indicadores permanecen en 1byone salvo que el fabricante los publique mediante un tipo oficial compatible.

Los valores se muestran con su unidad y fecha de origen. Si un modelo solo mantiene un indicador dentro de 1byone, ese indicador no se puede leer de forma fiable desde Veyra: no hay una API pública de 1byone documentada para importar la cuenta directamente. En ese caso se conserva el dato en 1byone y se usa únicamente lo que llegue legítimamente a Apple Health.

### Configuración para la usuaria

1. En 1byone Health, activar la sincronización con Apple Health y permitir los indicadores de composición corporal.
2. En Salud → Compartir → Apps → Veyra, activar la lectura de los indicadores deseados.
3. Abrir Veyra → Biología → Fuentes de datos y sincronizar. Veyra no escribe ni modifica mediciones de la báscula.

La disponibilidad de cada campo depende del modelo, la versión de 1byone y los permisos elegidos. Un permiso denegado se representa como dato ausente, nunca como cero inventado.

## Otras conexiones viables

La integración nativa común es [HealthKit](https://developer.apple.com/documentation/healthkit), el repositorio local de Apple para datos de salud. Las apps o accesorios que escriban en HealthKit pueden alimentar Veyra después de conceder permisos. Para servicios que no publiquen en HealthKit se necesitaría una API oficial, credenciales y un conector separado.

| Fuente | Datos útiles | Ruta recomendada | Estado |
| --- | --- | --- | --- |
| Apple Watch / Fitness | sueño, frecuencia cardíaca, HRV, entrenamientos, actividad | HealthKit | Integrado |
| 1byone Health | peso, grasa, masa magra, IMC y composición disponible | 1byone → HealthKit | Integrado |
| Withings Health Mate | peso, grasa, masa magra y presión arterial según dispositivo | HealthKit; API Withings opcional | Compatible por HealthKit |
| Oura | sueño, temperatura, recuperación | [Integración Apple Health de Oura](https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration) | Compatible por HealthKit |
| Garmin Connect | actividades, entrenamientos y algunas métricas | [Compartir Garmin Connect con Apple Health](https://support.garmin.com/en-NZ/?faq=lK5FPB9iPF5PXFkIpFlFPA&productID=125677) | Compatible por HealthKit / pendiente API |
| Strava | sesiones, distancia, ritmo y potencia | [Apple Health y Strava](https://support.strava.com/en-us/articles/15402024-apple-health-and-strava) | Compatible por HealthKit |
| Polar Flow / COROS | entrenamientos y frecuencia cardíaca | HealthKit; API del proveedor opcional | Candidato por HealthKit |
| Fitbit | actividad y peso según permisos y modelo | HealthKit cuando la app lo exporta; API Fitbit requiere OAuth | Compatible por HealthKit / pendiente API |
| Dexcom / One Drop | glucosa | HealthKit | Compatible por HealthKit si la app exporta el dato |
| Qardio | presión arterial y peso | HealthKit | Compatible por HealthKit si la app exporta el dato |
| Flo / Clue | ciclo y síntomas | HealthKit | Compatible por HealthKit si la app exporta el dato |

## Límites y privacidad

HealthKit aplica permisos independientes por tipo de dato y el usuario puede revocarlos en cualquier momento. Veyra solo solicita lectura de los tipos que necesita para los cálculos y mantiene el procesamiento local. Las integraciones directas futuras se activarán solo con consentimiento explícito, claves en Keychain y el alcance mínimo de datos.
