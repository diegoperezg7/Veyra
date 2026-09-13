# Créditos de imágenes

Las cinco escenas de cabecera son fotografías de paisaje en **dominio público**,
obtenidas de Wikimedia Commons y verificadas archivo por archivo antes de
incorporarlas (`LicenseShortName` = Public domain). No se ha usado ninguna
imagen con licencia que exija atribución o compartir-igual, ni ninguna que
muestre personas.

| Escena | Archivo | Licencia | Origen |
| --- | --- | --- | --- |
| Recuperación | Wildflower Meadow (6997737191).jpg | Dominio público | [Commons](https://commons.wikimedia.org/wiki/File:Wildflower_Meadow_(6997737191).jpg) |
| Esfuerzo | Mountain Landscape at Sunset (50299037338).jpg | Dominio público | [Commons](https://commons.wikimedia.org/wiki/File:Mountain_Landscape_at_Sunset_(50299037338).jpg) |
| Sueño | Milky Way over the Garden of Eden (21135225700).jpg | Dominio público | [Commons](https://commons.wikimedia.org/wiki/File:Milky_Way_over_the_Garden_of_Eden_(21135225700).jpg) |
| Estrés | Clouds and fog over Lost Horse Valley (50863680453).jpg | Dominio público | [Commons](https://commons.wikimedia.org/wiki/File:Clouds_and_fog_over_Lost_Horse_Valley_(50863680453).jpg) |
| Energía | Clouds and Mt Rainier with sunrise light. 101979. slide | Dominio público | [Commons](https://commons.wikimedia.org/wiki/File:Clouds_and_Mt_Rainier_with_sunrise_light._101979._slide_(b02bbd126f28405ca4d223ddd24e149e).jpg) |

Las imágenes se redimensionaron a 1200 px de ancho y se recomprimieron para
limitar el tamaño del binario. No se han recortado ni alterado de otro modo.

Si en el futuro se sustituyen por imágenes propias o con licencia comprada,
basta con reemplazar los `imageset` `SceneRecovery`, `SceneStrain`, `SceneSleep`,
`SceneStress` y `SceneEnergy` en `Resources/Assets.xcassets` y actualizar esta
tabla.

---

## Ilustraciones de ejercicios

Las 537 ilustraciones de `Resources/ExerciseArt/`, junto con los nombres,
músculos, material e instrucciones de `Resources/exercises.json`, derivan del
[dataset de Everkinetic](https://github.com/everkinetic/data) de Greg Priday,
bajo **CC BY-SA 4.0**.

**Qué se cambió:** los PNG originales son línea negra sobre papel blanco. Se
convirtieron a máscaras de alfa —el blanco pasa a transparente para que la app
pueda teñir el dibujo—, se recortaron a la figura y los dos fotogramas de cada
ejercicio se escalaron con un mismo factor para que la animación entre ellos no
dé saltos. Los nombres y las instrucciones se tradujeron al español.

Estas obras derivadas **siguen bajo CC BY-SA 4.0**, como exige la licencia, y
quedan por tanto **fuera de los términos de todos los derechos reservados** que
cubren el resto del repositorio. Cualquiera puede reutilizarlas bajo la misma
licencia citando a Everkinetic.

Se evaluó y descartó `free-exercise-db`: la procedencia de sus imágenes lleva
años sin aclararse en las incidencias del repositorio.
