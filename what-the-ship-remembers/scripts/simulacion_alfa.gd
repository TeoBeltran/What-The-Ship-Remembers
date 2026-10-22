extends Control
## Paso 2: simulación por consola de los turnos 1 a 12 del Alfa con el núcleo de reglas (estado.gd).
## Sigue un recorrido posible (03 y 06) con energía y luz reales, y verifica que la taza,
## la pinza, el destornillador y la nota aparezcan cuando corresponde. Resultado en pantalla y en la pestaña Salida.
## También se puede correr sin ventana: godot --headless --path . res://escenas/simulacion_alfa.tscn

var e  # el núcleo de reglas
var log_lineas: Array[String] = []
var fallas: Array[String] = []


func _ready() -> void:
	e = preload("res://scripts/estado.gd").new()
	add_child(e)
	e.texto_mostrado.connect(func(_id, lineas):
		for l in lineas:
			_log("      %s: %s" % [l["hablante"], l["texto"]]))
	e.objeto_activado.connect(func(id): if not e.objetos[id]["condiciones"].is_empty() or e.objetos[id]["turno_min"] > 1: _log("      + aparece %s (%s)" % [id, e.objetos[id]["descripcion"]]))
	e.objeto_usado.connect(func(id): _log("  · %s (%s) → energía %d" % [id, e.objetos[id]["descripcion"], e.energia]))
	e.sala_cambiada.connect(func(sala): if e.turno > 0 and sala != "MAN" or e.visitadas_turno.size() > 1: _log("  > entro a %s (luz %d) → energía %d" % [sala, e.luz[sala], e.energia]))
	e.item_agregado.connect(func(id): _log("      [item] %s" % id))
	e.anotacion_agregada.connect(func(_id): _log("      [Añadido a las anotaciones]"))
	e.evento_especial.connect(func(id): _log("      [evento] %s" % id))
	e.turno_empezado.connect(func(t):
		_log("")
		_log("=== TURNO %d === COM: %s · SCO: %s · PTA: %s" % [t, e.tiempo_de("COM"), e.tiempo_de("SCO"), e.tiempo_de("PTA")]))

	e.nueva_partida()
	_recorrido()
	_resumen()


# ------------------------------------------------------------
# Recorrido turno por turno
# ------------------------------------------------------------

func _recorrido() -> void:
	# T1 · tutorial, todo en presente. NORA N1–N4 forzadas, el panel roto (objetivo) y el destornillador.
	chequear(e.obj["MAN_N1"]["usado"] and e.obj["MAN_N2"]["usado"] and e.obj["MAN_N3"]["usado"] and e.obj["MAN_N4"]["usado"],
		"T1: las conversaciones N1 a N4 con NORA son obligatorias y en cadena")
	chequear(e.obj["MAN_A"]["usado"], "T1: después de N4 va solo al panel roto: «voy a necesitar herramientas»")
	chequear(e.energia == 14 and e.energia_maxima() == 14, "el traje arranca con 14 de energía")
	chequear(e.luz_maxima("MAN") == 2 and e.luz_maxima("COM") == 2, "sin el arreglo, mando y comunicaciones llegan a luz 2")
	chequear(not e.set_luz("MAN", 3), "la sala de mando no puede pasar a luz máxima sin arreglar el panel")
	ir("COM")
	chequear(e.inventario.has("destornillador"), "T1: al entrar a comunicaciones agarra solo el destornillador («me falta una pinza»)")
	chequear(not e.obj["MAN_B"]["activo"], "con solo el destornillador todavía no se puede arreglar el panel")
	usar("COM_E"); usar("COM_H")
	chequear(not e.se_puede_usar("COM_G"), "sin energía suficiente no se puede interactuar (quedan %d)" % e.energia)
	chequear(e.obj["COM_L"]["activo"], "radio + registro en el presente activan la nota del futuro (COM_L)")

	# T2 · abrir la sala común y la sala de la puerta.
	turno()
	chequear(e.obj["MAN_N15"]["usado"], "T2: NORA explica cómo llegar a la sala común (forzada)")
	usar("MAN_N12")
	ir("COM")
	chequear(e.motivo_no_movible("SCO") != "", "la sala común está bloqueada antes de abrirla")
	usar("COM_Q")
	chequear(e.desbloqueadas.has("SCO") and e.luz["SCO"] == 0, "la sala común se desbloquea y queda apagada")
	ir("PTA")
	usar("PTA_A")

	# T3 · repartir la luz y entrar a la sala común.
	turno()
	usar("MAN_N5")
	luz("SCO", 2)
	chequear(e.capacidad_libre() == 1, "capacidad de luz: 9 de 10 (mando en 2, comunicaciones 2, sala común 2, puerta 3)")
	chequear(not e.set_luz("SCO", 3), "la sala común no puede pasar de luz media en el Alfa")
	ir("COM"); ir("SCO")
	usar("SCO_G"); usar("SCO_H"); usar("SCO_S")
	chequear(e.costo_mover("COM") == 0, "volver de la sala común a comunicaciones no cuesta energía")

	# T4 · sala común en pasado: la taza.
	turno()
	ir("COM"); ir("SCO")
	usar("SCO_D")
	chequear(e.obj["SCO_I"]["desdibujado"], "la taza colgada del presente (SCO_I) se desdibuja")
	chequear(e.obj["SCO_J"]["activo"] and e.obj["SCO_O"]["activo"], "aparecen la taza en la mesa (presente) y rota (futuro)")
	usar("SCO_C")

	# T5 · comunicaciones en pasado, sala común en presente.
	turno()
	usar("MAN_N10")
	ir("COM")
	chequear(not e.se_ve("COM_D"), "con luz media no se ve la lista de turnos (luz 3) del pasado")
	usar("COM_C")
	ir("SCO")
	usar("SCO_J")

	# T6 · sala común en futuro.
	turno()
	usar("MAN_N13"); usar("MAN_N11")
	ir("COM")
	chequear(e.obj["COM_R"]["usado"], "T6: al entrar a comunicaciones (presente) sale solo «Juraría que acá había una pinza»")
	usar("COM_G")
	ir("SCO")
	usar("SCO_O")
	chequear(e.se_ve("SCO_R"), "la silla que levanté en el presente está en pie en el futuro (SCO_R)")

	# T7 · comunicaciones en futuro: la pinza. Al volver a la sala de mando, el arreglo del panel.
	turno()
	ir("COM")
	chequear(e.se_ve("COM_P"), "la hoja que rompí en el presente está en el futuro (COM_P)")
	chequear(e.inventario.has("pinza"), "T7 (primer futuro): la pinza está en la mesa y se guarda sola en el bolsillo")
	chequear(e.obj["COM_O"]["desdibujado"], "la pinza del futuro ya no se dibuja")
	chequear(e.obj["MAN_B"]["activo"] and not e.obj["MAN_B"]["usado"], "con las dos herramientas el arreglo espera a volver a la sala de mando")
	usar("COM_L"); usar("COM_J")
	ir("PTA")
	usar("PTA_C")
	var antes: int = e.energia
	ir("COM"); ir("MAN")
	chequear(e.obj["MAN_B"]["usado"], "T7: al volver a la sala de mando arregla solo el panel (cinemática)")
	chequear(e.luz_maxima("MAN") == 3 and e.luz_maxima("COM") == 3, "con el arreglo, mando y comunicaciones pueden llegar a luz máxima")
	chequear(e.luz["MAN"] == 3, "la sala de mando sube sola a luz máxima (alcanza la capacidad)")
	chequear(e.energia == antes + 1 and e.energia_maxima() == 15, "el arreglo suma 1 de energía ahora y el traje pasa a 15 por turno")

	# T8 · comunicaciones otra vez en futuro: la pinza ya no está.
	turno()
	chequear(e.energia == 15, "T8: el turno arranca con 15 de energía")
	usar("MAN_N8"); usar("MAN_N14")
	ir("COM")
	chequear(e.tiempo_de("COM") == "futuro" and not e.se_ve("COM_O"), "T8 (futuro otra vez): la pinza ya no está porque la agarré")
	ir("SCO")
	usar("SCO_K")

	# T9 · comunicaciones en pasado: la pinza está otra vez. Investigarla es opcional (acá NO se investiga).
	turno()
	luz("SCO", 0)
	luz("COM", 3)
	ir("COM")
	chequear(e.se_ve("COM_M") and not e.obj["COM_M"]["usado"], "T9 (pasado): la pinza está en la mesa y no sale ningún diálogo solo")
	chequear(e.se_ve("COM_D"), "con luz máxima en comunicaciones ya se ve la lista de turnos del pasado")
	usar("COM_D"); usar("COM_B")

	# T10 · comunicaciones en presente: la pinza en la mesa y en el bolsillo.
	turno()
	usar("MAN_N9")
	ir("COM")
	chequear(e.obj["COM_S"]["usado"] and e.se_ve("COM_N") and e.inventario.has("pinza"),
		"T10 (presente): como no la investigó en el pasado, sale solo «acá está la pinza… pero la tengo en el bolsillo»")
	chequear(not e.se_puede_usar("COM_N"), "la pinza del presente queda a la vista pero no se puede usar")
	usar("COM_F")
	ir("PTA")
	usar("PTA_D"); usar("PTA_E")
	chequear(e.costo_mover("COM") == 0, "volver de la sala de la puerta a comunicaciones no cuesta energía")

	# T11 · comunicaciones en futuro: la pinza sigue sin estar.
	turno()
	usar("MAN_N6")
	ir("COM")
	chequear(not e.se_ve("COM_O"), "T11 (futuro): la pinza no vuelve a aparecer en el futuro")
	chequear(e.costo_mover("MAN") == 0, "volver de comunicaciones a mando no cuesta energía")

	# T12 · la paradoja y el cierre.
	turno()
	ir("COM")
	chequear(e.obj["COM_T"]["usado"] and e.se_ve("COM_N") and e.inventario.has("pinza"),
		"PARADOJA: compara la pinza de la mesa con la del bolsillo (COM_T) y empieza el cierre")
	_log("")
	_log(">>> Acá el juego hace el cierre del Alfa (camina solo hasta NORA, diálogos T_CIERRE_*).")
	_rama_pinza_en_el_pasado()


## Otra partida: si en el T9 se investiga la pinza del pasado, en el T10 no sale el diálogo obligatorio.
func _rama_pinza_en_el_pasado() -> void:
	_log("")
	_log("=== RAMA ALTERNATIVA: investigar la pinza en el pasado (T9) ===")
	var principal = e
	e = preload("res://scripts/estado.gd").new()
	add_child(e)
	e.nueva_partida()
	while e.turno < 7:
		e.empezar_turno()
	ir("COM")
	chequear(e.inventario.has("pinza") and not e.inventario.has("destornillador"),
		"T7: agarra la pinza en el futuro (en esta partida nunca entró a comunicaciones en presente)")
	ir("MAN")
	chequear(not e.obj["MAN_B"]["usado"], "sin el destornillador no se arregla el panel")
	e.empezar_turno(); e.empezar_turno()  # T9
	ir("COM")
	usar("COM_M")
	chequear(e.se_ve("COM_M") and not e.se_puede_usar("COM_M") and e.inventario.count("pinza") == 1,
		"T9: la investiga (confusión), no se la lleva y queda a la vista sin poder usarse")
	e.empezar_turno()  # T10
	ir("COM")
	chequear(e.se_ve("COM_N") and not e.obj["COM_S"]["usado"], "T10: la pinza está en la mesa pero NO sale el diálogo obligatorio")
	chequear(e.inventario.has("destornillador"), "T10: el destornillador sigue esperando en comunicaciones (presente)")
	ir("MAN")
	chequear(e.obj["MAN_B"]["usado"] and e.energia_maxima() == 15, "con las dos herramientas, al volver a mando arregla el panel")
	e.queue_free()
	e = principal


# ------------------------------------------------------------
# Ayudas
# ------------------------------------------------------------

func usar(id: String) -> void:
	var motivo: String = e.motivo_no_usable(id)
	if not e.interactuar(id):
		_falla("T%d no se pudo usar %s: %s" % [e.turno, id, motivo])


func ir(sala: String) -> void:
	var motivo: String = e.motivo_no_movible(sala)
	if not e.mover_a(sala):
		_falla("T%d no se pudo ir a %s: %s" % [e.turno, sala, motivo])


func luz(sala: String, nivel: int) -> void:
	var motivo: String = e.motivo_no_luz(sala, nivel)
	if e.set_luz(sala, nivel):
		_log("  * luz de %s en %d (capacidad %d/%d)" % [sala, nivel, e.capacidad_usada(), e.cfg("capacidad_luz")])
	else:
		_falla("T%d no se pudo poner luz %d en %s: %s" % [e.turno, nivel, sala, motivo])


func turno() -> void:
	_log("  (fin del turno con %d de energía sin usar)" % e.energia)
	e.empezar_turno()


func chequear(condicion: bool, texto: String) -> void:
	if condicion:
		_log("  ✓ " + texto)
	else:
		_falla("T%d: %s" % [e.turno, texto])


func _falla(texto: String) -> void:
	fallas.append(texto)
	_log("  ✗ FALLA: " + texto)


func _log(texto: String) -> void:
	log_lineas.append(texto)
	print(texto)


func _resumen() -> void:
	_log("")
	if fallas.is_empty():
		_log("SIMULACIÓN OK: T1–T12 sin fallas. La taza, la nota, el destornillador, la pinza y el arreglo del panel aparecen cuando corresponde (y la rama alternativa de la pinza).")
	else:
		_log("SIMULACIÓN CON %d FALLAS:" % fallas.size())
		for f in fallas:
			_log("  ✗ " + f)
	$Scroll/Texto.text = "\n".join(log_lineas)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if fallas.is_empty() else 1)
