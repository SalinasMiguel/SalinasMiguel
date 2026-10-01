# Optimizar PC: sin tirones ni congelamientos

Herramientas para **Windows 10 y 11** que encuentran y corrigen las causas más
comunes de cortes, tirones y congelamientos.

- **No tocan** el antivirus, Windows Update, los servicios ni nada que baje la seguridad.
- **Preguntan** antes de cada cambio.
- **Todo se puede deshacer** (opción 3 del menú).

## Cómo usarlo

1. Descarga esta carpeta: en GitHub, botón verde **Code > Download ZIP**.
2. Clic derecho en el ZIP > **Propiedades** > marca **Desbloquear** > Aceptar. Luego extráelo.
3. Doble clic en **`EJECUTAR.bat`** y acepta el permiso de administrador.
   Si aparece "Windows protegió su PC": **Más información > Ejecutar de todas formas**.
4. Elige **1 (Diagnóstico)**. Lee el resumen del final; también se guarda un informe en el Escritorio.
5. Elige **2 (Optimizar)**. Pulsa Enter para aceptar la opción recomendada en cada paso.
6. **Reinicia** la PC (Inicio > Reiniciar).

Si algo no te convence, vuelve a abrir `EJECUTAR.bat` y elige **3 (Deshacer)**.

## Qué revisa el diagnóstico

| Revisión | Por qué causa tirones o congelamientos |
|---|---|
| RAM instalada, en uso y número de módulos | Si se llena, Windows usa el disco como memoria y todo se congela. Un solo módulo rinde la mitad. |
| Memoria virtual (paginación) | Si está desactivada, los programas se cuelgan cuando la RAM se llena. |
| Tipo de disco, salud y espacio libre | Windows en disco mecánico (HDD) o un disco casi lleno provoca el famoso "disco al 100 %". |
| Driver de video | Un driver viejo o genérico es la causa típica de tirones en juegos. |
| Plan de energía y batería | "Economizador" o jugar sin cargador limitan el procesador. |
| Xbox Game Bar y Modo de juego | Grabar en segundo plano roba rendimiento. |
| Programas al inicio | Muchos programas abiertos en segundo plano consumen RAM y procesador. |
| Procesos que más consumen ahora | Para ver qué está gastando los recursos. |
| Errores de los últimos 30 días | Congelamientos totales, pantallazos azules, cuelgues del driver de video, fallos de disco, falta de memoria y errores de hardware. |

## Qué cambia la optimización

| Ajuste | Para qué sirve | ¿Se deshace con la opción 3? |
|---|---|---|
| Punto de restauración | Red de seguridad antes de cambiar nada. | — |
| Plan de energía "Alto rendimiento" | El procesador no baja de velocidad en mitad del juego. | Sí |
| Desactivar la captura de Xbox Game Bar | Evita la grabación en segundo plano. OBS, ShadowPlay y Discord siguen funcionando. | Sí |
| Activar el Modo de juego | Windows prioriza el juego y pausa tareas de fondo. | Sí |
| Memoria virtual automática (solo si estaba desactivada o fijada a mano) | Evita cuelgues cuando la RAM se llena. | Sí |
| Borrar archivos temporales | Libera espacio. | No hace falta |
| Optimizar discos (TRIM o desfragmentar) | Mantiene la velocidad del disco. | No hace falta |
| Reparar Windows con DISM + SFC (opcional; por defecto no) | Arregla archivos del sistema dañados. Tarda de 10 a 30 minutos. | No hace falta |

## Lo que un script no puede arreglar

Si después de esto sigue habiendo tirones, revisa esto, en este orden:

1. **Temperaturas.** Instala [HWiNFO](https://www.hwinfo.com/) (gratis), juega 15 minutos y mira
   los valores máximos: procesador por debajo de 90 °C y gráfica por debajo de 85 °C. Si te pasas,
   limpia el polvo de ventiladores y disipadores. En portátiles ayuda mucho una base refrigerante.
2. **Driver de video limpio.** Descarga el último driver de [NVIDIA](https://www.nvidia.com/Download/index.aspx),
   [AMD](https://www.amd.com/en/support/download/drivers.html) o [Intel](https://www.intel.com/content/www/us/en/support/detect.html).
   Si el diagnóstico muestra que el driver de video se cuelga, desinstala el anterior con DDU antes de instalar el nuevo.
3. **Programas al inicio.** `Ctrl + Shift + Esc` > **Aplicaciones de arranque** y deshabilita lo
   que no necesites al encender.
4. **Dentro de los juegos:**
   - Limita los FPS a la frecuencia de tu monitor (por ejemplo 60 o 144). Un framerate estable se siente más fluido que uno alto que sube y baja.
   - Si el juego se traba al girar la cámara o cambiar de zona, baja **la calidad de texturas**: suele ser que se llena la memoria de la gráfica.
   - Instala los juegos en el SSD, no en el disco mecánico.
   - Prueba a desactivar overlays: NVIDIA Instant Replay, superposición de Discord y de Steam.
5. **BIOS:** activa el perfil **XMP / EXPO** para que la RAM vaya a su velocidad real.
6. **Hardware:** las dos mejoras que más se notan contra los congelamientos son **pasar Windows a
   un SSD** y **tener 16 GB de RAM en dos módulos**.

## Uso avanzado desde PowerShell

```powershell
# Solo diagnóstico (no necesita administrador, pero da más detalle con él)
powershell -ExecutionPolicy Bypass -File .\diagnostico.ps1

# Optimizar preguntando en cada paso / aplicar lo recomendado sin preguntar
powershell -ExecutionPolicy Bypass -File .\optimizar.ps1
powershell -ExecutionPolicy Bypass -File .\optimizar.ps1 -Todo

# Incluir la reparación de Windows (DISM + SFC)
powershell -ExecutionPolicy Bypass -File .\optimizar.ps1 -Todo -RepararSistema

# Deshacer
powershell -ExecutionPolicy Bypass -File .\optimizar.ps1 -Revertir
```

Los valores originales se guardan en `%LOCALAPPDATA%\optimizar-pc\respaldo.json`.
