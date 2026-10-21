extends Control
## Prueba del paso 1: lee los JSON de datos/ y muestra un resumen. Se puede borrar más adelante.

const ARCHIVOS = ["objetos", "salas", "guion", "textos", "anotaciones", "items", "audios", "eventos", "config"]

func _ready() -> void:
	var lineas: Array[String] = ["PRUEBA DE DATOS (paso 1)", ""]
	var datos := {}
	var ok := true
	for nombre in ARCHIVOS:
		var ruta := "res://datos/%s.json" % nombre
		var texto := FileAccess.get_file_as_string(ruta)
		var json = JSON.parse_string(texto)
		if json == null:
			lineas.append("✗ %s.json: no se pudo leer" % nombre)
			ok = false
		else:
			datos[nombre] = json
			lineas.append("✓ %s.json: %d entradas" % [nombre, json.size()])
	if ok:
		lineas.append("")
		lineas.append("Ejemplo, objeto COM_O: " + str(datos["objetos"]["COM_O"]["descripcion"]))
		for l in datos["textos"]["T_COM_M"]:
			lineas.append("   %s: %s" % [l["hablante"], l["texto"]])
		lineas.append("Turno 9: comunicaciones en " + str(datos["guion"]["9"]["COM"]))
		lineas.append("")
		lineas.append("TODO OK: Godot lee los datos.")
	$Texto.text = "\n".join(lineas)
	print($Texto.text)
