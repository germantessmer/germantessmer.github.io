# ==============================================================================
# separa_eph.R — Separador hogar/individuo para las bases EPH-Observatorio
#                Household/individual splitter for the EPH-Observatorio datasets
# ==============================================================================
#
# QUE HACE
# --------
# Las bases EPH-Observatorio (capa 1, publicadas en el Dataverse UNR) son UN
# dataset por trimestre a nivel persona, producto de unir las bases usuarias
# de hogar e individual de INDEC, con las variables renombradas (etiquetas en
# castellano) y enriquecidas (deflactadas, NBI, etc.).
#
# Este script hace el camino inverso: separa ese dataset en sus dos bases
# constitutivas, asignando la TOTALIDAD de las variables (originales de INDEC
# y creadas por el Observatorio) a la base que les corresponde:
#
#   - Base HOGAR: una fila por hogar (CODUSU + NRO_HOGAR), con las variables
#     de vivienda, estrategias del hogar, ingresos familiares, NBI, etc.
#   - Base INDIVIDUAL: una fila por persona, con las variables demográficas,
#     educativas, laborales y de ingresos individuales.
#
# La clasificación de cada variable proviene del Diccionario de la capa 1
# (campo `base` de eph_dict_capa1.json / variables_capa1.yml) y va embebida
# en este script, por lo que NO se necesita ningún archivo ni paquete extra.
# Las variables de identificación (codusu, nro_hogar, anio, trimestre, region,
# mas_500, aglomerado, pondera, ...) se incluyen en ambas bases, replicando
# la convención de las bases usuarias de INDEC.
#
# Documentación de las variables:
#
#   Diccionario de la base EPH - Observatorio (UNR)
#   RepHip UNR: https://hdl.handle.net/2133/33195
#   Dataverse:  https://doi.org/10.57715/UNR/BL85Z8
#
# PARA QUIEN ES
# -------------
# Para usuarios de las bases EPH-Observatorio de capa 1 (.RData del
# Dataverse), que trabajan con los nombres etiquetados de las variables.
# Quien use las bases usuarias crudas de INDEC no necesita este script (ya
# las tiene separadas; ver bridge_eph.R para el puente de comparabilidad).
#
# REQUISITOS
# ----------
# R >= 3.5. No requiere ningún paquete adicional (solo R base).
#
# USO
# ---
#   source("separa_eph.R")
#
#   # 1) Un trimestre (el .RData de capa 1 descargado del Dataverse):
#   separa_eph("C:/mis_bases/EPH2025_T1.RData")
#   #    -> escribe EPH2025_T1_hogar.RData (objeto `hogar`)
#   #       y EPH2025_T1_individual.RData (objeto `individual`)
#
#   # 2) Varios trimestres:
#   separa_eph(c("C:/eph/EPH2025_T1.RData", "C:/eph/EPH2025_T2.RData"))
#
#   # 3) Una carpeta: detecta todos los EPH20AA_TN.RData presentes:
#   separa_eph("C:/mis_bases")
#
#   # 4) Sin guardar: devuelve los dos data.frames en memoria:
#   r <- separa_eph("C:/eph/EPH2025_T1.RData", guardar = FALSE)
#   r$datos[["2025-T1"]]$hogar
#   r$datos[["2025-T1"]]$individual
#
#   # 5) Con el dataset ya cargado en la sesión (objeto `datos`):
#   r <- separa_eph(datos, guardar = FALSE)
#
# PARAMETROS
# ----------
#   entrada        Ruta(s) a .RData de capa 1, una carpeta que los contenga,
#                  o directamente un data.frame de capa 1 ya cargado.
#   guardar        Si TRUE (default), escribe un .RData por base. Si FALSE,
#                  devuelve los data.frames en $datos sin escribir nada.
#   dir_salida     Carpeta de salida. Por defecto, la del archivo de entrada
#                  (o el directorio de trabajo si la entrada es un data.frame).
#   nombres_salida Nombres de los archivos de salida: vector
#                  c(hogar = "...", individual = "...") para una entrada, o
#                  una lista de esos vectores para varias. Por defecto:
#                  nombre original + sufijos.
#   sufijos        Sufijos del nombre por defecto: c("_hogar", "_individual").
#   sobrescribir   Si FALSE (default), no pisa archivos existentes.
#   diccionario    Opcional: ruta a un eph_dict_capa1.json para usar una
#                  clasificación más nueva que la embebida en este script
#                  (requiere el paquete jsonlite).
#   desconocidas   Qué hacer si el dataset tiene columnas que no figuran en la
#                  clasificación: "error" (default, detiene), "individual"
#                  (las asigna a la base individual, nivel del microdato) u
#                  "omitir" (las descarta con aviso).
#   verbose        Si TRUE (default), informa el detalle del procesamiento.
#
# SALIDA
# ------
# Con guardar = TRUE escribe, por cada entrada, dos .RData: uno con el objeto
# `hogar` (una fila por hogar) y otro con el objeto `individual` (una fila por
# persona). Los tipos, factores y etiquetas de variable (atributo `label`) se
# preservan tal como vienen en la capa 1.
#
# La función devuelve (invisible) una lista con dos elementos:
#   $resumen  data.frame con un renglón por entrada: período, filas, hogares,
#             personas, variables por base y rutas de salida.
#   $datos    NULL si guardar = TRUE. Si guardar = FALSE, lista nombrada por
#             período con $hogar y $individual.
#
# NOTAS
# -----
# - La clasificación sigue el campo `base` del Diccionario con UNA corrección
#   a nivel de registro: los montos de ingresos no laborales (V2_M, V5_M, ...,
#   V19_AM y derivadas) figuran en el Diccionario bajo la sección hogar, pero
#   son montos por PERCEPTOR (viven en el registro individual de INDEC y
#   difieren entre miembros del hogar), por lo que van a la base individual.
#   Ver .SEPARA_REASIGNA_INDIVIDUO.
# - La base hogar se obtiene tomando la primera aparición de cada hogar. El
#   script verifica antes que toda variable clasificada como "Hogar" sea
#   efectivamente constante dentro del hogar, y avisa si encuentra
#   excepciones.
# - Si el dataset trae filas de hogares sin individuos encuestados
#   (componente vacío), van a la base hogar pero se excluyen de la individual.
# - Funciona igual con trimestres de la metodología legacy (< 2024-T4) y new:
#   simplemente se asignan las columnas presentes en cada caso.
#
# ==============================================================================
#
# [EN] ENGLISH NOTES
# ==============================================================================
#
# WHAT IT DOES
# ------------
# The EPH-Observatorio datasets (layer 1, published in the UNR Dataverse) are
# ONE person-level dataset per quarter, built by merging INDEC's household
# and individual user databases, with variables renamed (Spanish labels) and
# enriched (deflated incomes, UBN/NBI, etc.).
#
# This script goes the other way: it splits that dataset back into its two
# constituent bases, assigning EVERY variable (original INDEC ones and those
# created by the Observatory) to the base it belongs to:
#
#   - HOUSEHOLD base: one row per household (CODUSU + NRO_HOGAR), with
#     dwelling characteristics, household livelihood strategies, family
#     incomes (ITF/IPCF/deciles), UBN/NBI, etc.
#   - INDIVIDUAL base: one row per person, with demographic, educational,
#     labor-market and individual income variables.
#
# Each variable's classification comes from the layer-1 Dictionary (`base`
# field of eph_dict_capa1.json / variables_capa1.yml) and is embedded in this
# script, so NO extra file or package is needed. Identification variables
# (codusu, nro_hogar, anio, trimestre, region, mas_500, aglomerado,
# pondera, ...) are included in BOTH bases, replicating the INDEC user-base
# convention. Variable documentation: Dictionary of the EPH - Observatorio
# dataset (RepHip UNR: https://hdl.handle.net/2133/33195; Dataverse:
# https://doi.org/10.57715/UNR/BL85Z8).
#
# WHO IT IS FOR
# -------------
# Users of the layer-1 EPH-Observatorio datasets (.RData from the Dataverse),
# who work with the labeled variable names. Users of the raw INDEC user
# databases do not need this script (their bases are already separate; see
# bridge_eph.R for the comparability bridge).
#
# REQUIREMENTS
# ------------
# R >= 3.5. No additional packages required (base R only). Runtime messages
# are printed in Spanish.
#
# USAGE
# -----
# Same call patterns as the Spanish examples above:
#   separa_eph("C:/my_bases/EPH2025_T1.RData")        # one quarter -> writes
#                                                     #   *_hogar.RData (object
#                                                     #   `hogar`) and
#                                                     #   *_individual.RData
#                                                     #   (object `individual`)
#   separa_eph(c(f1, f2))                             # several quarters
#   separa_eph("C:/my_bases")                         # folder: auto-detects
#   r <- separa_eph(f, guardar = FALSE)               # in-memory, no files
#   r <- separa_eph(datos, guardar = FALSE)           # already-loaded data.frame
#
# PARAMETERS
# ----------
#   entrada        Path(s) to layer-1 .RData files, a folder containing them,
#                  or a layer-1 data.frame already loaded in the session.
#   guardar        TRUE (default) writes one .RData per base. FALSE returns
#                  the data.frames in $datos without writing anything.
#   dir_salida     Output folder. Defaults to the input file's folder (or the
#                  working directory if the input is a data.frame).
#   nombres_salida Output file names: c(hogar = ..., individual = ...) for
#                  one input, or a list of those for several. Default:
#                  original name + suffixes.
#   sufijos        Suffixes for default names: c("_hogar", "_individual").
#   sobrescribir   FALSE (default) refuses to overwrite existing files.
#   diccionario    Optional: path to an eph_dict_capa1.json to use a newer
#                  classification than the embedded one (requires jsonlite).
#   desconocidas   What to do with columns missing from the classification:
#                  "error" (default, stops), "individual" (assigns them to
#                  the individual base, the microdata level) or "omitir"
#                  (drops them with a notice).
#   verbose        TRUE (default) reports processing details.
#
# OUTPUT
# ------
# With guardar = TRUE, writes two .RData per input: one with the `hogar`
# object (one row per household) and one with the `individual` object (one
# row per person). Types, factors and variable labels (`label` attribute)
# are preserved exactly as they come in layer 1. The function returns
# (invisibly) list(resumen = <one-row-per-input summary data.frame>,
# datos = <NULL if guardar = TRUE; otherwise a list named by period with
# $hogar and $individual>).
#
# NOTES
# -----
# - The classification follows the Dictionary's `base` field with ONE
#   record-level correction: the non-labor income amounts (V2_M, V5_M, ...,
#   V19_AM and their deflated twins) appear in the Dictionary under the
#   household section, but they are per-RECIPIENT amounts (they live in
#   INDEC's individual register and differ across household members), so
#   they go to the individual base. See .SEPARA_REASIGNA_INDIVIDUO.
# - The household base keeps the first occurrence of each household. The
#   script first verifies that every variable classified as "Hogar" is
#   actually constant within the household, and warns about exceptions.
# - Rows of households with no surveyed individuals (empty componente) go to
#   the household base and are excluded from the individual base.
# - Works the same with legacy (< 2024-Q4) and new-methodology quarters: the
#   columns present in each case are simply assigned.
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Clasificación de variables (generada desde dataverse/dictionary/
# eph_dict_capa1.json, campo `base`; 416 variables, version dict 2026-05-28)
# [EN] Variable classification (generated from eph_dict_capa1.json, `base`
#      field; 416 variables, dictionary version 2026-05-28)
# ------------------------------------------------------------------------------

.SEPARA_VARS_HOGAR <- c(
  "tipo_vivienda", "otro_tipo_vivienda", "nro_ambientes_vivienda",
  "tipo_piso", "otro_tipo_piso", "tipo_techo", "revestimiento_techo",
  "acceso_agua", "suministro_agua", "otro_suministro_agua", "banio",
  "lugar_banio", "caract_banio", "tipo_desague", "cercania_basural",
  "zona_inundable", "villa_emergencia", "cond_sanitarias",
  "vivienda_inconveniente", "nro_ambientes_hogar", "nro_ambientes_dormir",
  "ambientes_trabajo", "nro_ambientes_trabajo", "cocina", "lavadero",
  "garage", "otro_ambiente_dormir", "nro_otro_ambiente_dormir",
  "otro_ambiente_trabajo", "nro_otro_ambiente_trabajo", "regimen_tenencia",
  "otro_regimen_tenencia", "combustible_cocina", "otro_combustible_cocina",
  "uso_banio_hogar", "hacinamiento", "vive_trabaja", "vive_jubilacion",
  "vive_jubilacion_trabajo", "vive_jub_amacasa", "vive_otra_pension",
  "vive_aguinaldo", "vive_jubilacion_aguinaldo", "vive_jub_amacasa_aguinaldo",
  "vive_otra_pension_aguinaldo", "vive_retroactivo",
  "vive_jubilacion_retroactivo", "vive_jub_amacasa_retroactivo",
  "vive_otra_pension_retroactivo", "vive_indemnizacion", "vive_seguro",
  "vive_subsidio_dinero", "vive_subsidio_auh", "vive_subsidio_otro_gob",
  "vive_subsidio_caridad", "vive_subsidio_mercaderia", "vive_ayuda_personas",
  "vive_alquiler", "vive_ganancias_negocio", "vive_renta_financiera",
  "vive_beca", "vive_beca_gob", "vive_beca_priv", "vive_cuota_alimenticia",
  "vive_ahorros", "vive_prestamos_personas", "vive_prestamos_financieros",
  "vive_financiamiento", "vive_venta_bienes", "vive_otro_ingreso",
  "menores_trabajan", "menores_piden", "miembros_hogar", "menores10",
  "mayores10", "ingreso_familiar", "ingreso_real_familiar", "decifr",
  "idecifr", "rdecifr", "gdecifr", "pdecifr", "adecifr",
  "ingreso_capita_familiar", "ingreso_real_capita_familiar", "deccfr",
  "ideccfr", "rdeccfr", "gdeccfr", "pdeccfr", "adeccfr", "pondih",
  "realizacion_tareas_1", "realizacion_tareas_2",
  "otros_realizacion_tareas_1", "otros_realizacion_tareas_2",
  "otros_realizacion_tareas_3", "otros_realizacion_tareas_4", "tareas_hogar",
  "ingreso_jubilacion", "ingreso_real_jubilacion",
  "ingreso_jubilacion_trabajo", "ingreso_real_jubilacion_trabajo",
  "ingreso_jubilacion_ama_casa", "ingreso_real_jubilacion_ama_casa",
  "ingreso_jubilacion_otros", "ingreso_real_jubilacion_otros",
  "ingreso_aguinaldo", "ingreso_real_aguinaldo",
  "ingreso_jubilacion_aguinaldo", "ingreso_real_jubilacion_aguinaldo",
  "ingreso_jub_amacasa_aguinaldo", "ingreso_real_jub_amacasa_aguinaldo",
  "ingreso_otra_pension_aguinaldo", "ingreso_real_otra_pension_aguinaldo",
  "ingreso_retroactivo", "ingreso_real_retroactivo",
  "ingreso_jubilacion_retroactivo", "ingreso_real_jubilacion_retroactivo",
  "ingreso_jub_amacasa_retroactivo", "ingreso_real_jub_amacasa_retroactivo",
  "ingreso_otra_pension_retroactivo", "ingreso_real_otra_pension_retroactivo",
  "ingreso_indemnizacion", "ingreso_real_indemnizacion",
  "ingreso_seguro_desempleo", "ingreso_real_seguro_desempleo",
  "ingreso_subsidio", "ingreso_real_subsidio", "ingreso_subsidio_auh",
  "ingreso_real_subsidio_auh", "ingreso_subsidio_otro_gob",
  "ingreso_real_subsidio_otro_gob", "ingreso_subsidio_caridad",
  "ingreso_real_subsidio_caridad", "ingreso_alquiler",
  "ingreso_real_alquiler", "ingreso_negocio", "ingreso_real_negocio",
  "ingreso_renta", "ingreso_real_renta", "ingreso_beca", "ingreso_real_beca",
  "ingreso_beca_gob", "ingreso_real_beca_gob", "ingreso_beca_priv",
  "ingreso_real_beca_priv", "ingreso_cuota_alimentaria",
  "ingreso_real_cuota_alimentaria", "ingreso_otro", "ingreso_real_otro",
  "ingreso_menores", "ingreso_real_menores", "nbi", "nbi_2", "nbi_3", "nbi_4",
  "nbi_5"
)

.SEPARA_VARS_INDIVIDUO <- c(
  "principal_tareas_hogar", "otros_tareas_hogar", "parentesco", "sexo",
  "nacimiento", "edad", "estado_civil", "cobertura_salud", "alfabetizacion",
  "asistencia_escuela", "tipo_escuela", "nivel_educ_cursado",
  "finalizo_educacion", "anio_aprobado", "lugar_nacimiento",
  "otro_lugar_nacimiento", "pais_nacimiento", "subcontinente_nacimiento",
  "continente_nacimiento", "lugar_residencia", "otro_lugar_residencia",
  "pais_residencia", "subcontinente_residencia", "continente_residencia",
  "nivel_educ_obtenido", "condicion_actividad", "categoria_ocupacional",
  "categoria_inactivo", "imputado", "formalidad_empleo", "sector_formalidad",
  "empieza_trabajo_hipotesis", "busca_trabajo", "busca_trabajo_entrevista",
  "busca_trabajo_avisos", "busca_trabajo_presencial",
  "busca_trabajo_ctapropia", "busca_trabajo_carteles",
  "busca_trabajo_conocidos", "busca_trabajo_bolsa", "busca_trabajo_otros",
  "busca_trabajo_cta", "no_busco_trabajo", "busca_trabajo2",
  "empieza_trabajo_efectivo", "busco_trabajo_anio", "trabajo_anio",
  "subsistencia", "no_escolar", "empleos_semana", "nro_empleos_semana",
  "horas_ocupacion_principal_semana", "horas_otra_ocupacion_semana",
  "quiere_trabajar_mas_semana", "capacidad_trabajar_mas_semana",
  "quiere_trabajar_mas_mes", "busco_trabajo_adicional",
  "motivo_busco_trabajo", "intensidad_trabajo", "tipo_empresa",
  "nivel_trabajo_estatal", "codigo_actividad", "division_ocupado",
  "seccion_ocupado", "servicio_domestico", "nro_casas_servicio_domestico",
  "meses_tiempo_trabaja", "anios_tiempo_trabaja", "dias_tiempo_trabaja",
  "antiguedad_ocup_principal", "cantidad_empleados", "rango_empleados",
  "codigo_ocupacion", "caracter_ocupado", "jerarquia_ocupado",
  "tecnologia_ocupado", "calificacion_ocupado", "lugar_tareas",
  "meses_trabajo_continuo", "anios_trabajo_continuo", "dias_trabajo_continuo",
  "antiguedad_ocup_indep", "emite_facturas", "tiene_maquinas", "tiene_local",
  "tiene_vehiculo", "gasto_insumos", "variedad_clientes",
  "trabajo_continuo_indep", "aporto_como", "motivo_no_aporto",
  "emite_facturas2", "tiene_socios", "ingreso_duenio_sin_socio",
  "ingreso_real_duenio_sin_socio", "ingreso_duenio_con_socio",
  "ingreso_real_duenio_con_socio", "tipo_sociedad", "tiene_contador_ind",
  "actividad_familiar", "dedicacion_tipo_ind", "dedicacion_dia_semana_ind",
  "dedicacion_dia_mes_ind", "dedicacion_hora_dia_ind",
  "tiempo_continuo_asalariado", "cobra_plan_asalariado",
  "trabajo_concluye_asalariado", "duracion_trabajo_asalariado",
  "tipo_trabajo_asalariado", "benef_asalariado_comida",
  "benef_asalariado_vivienda", "benef_asalariado_mercaderia",
  "benef_asalariado_otro", "benef_asalariado_ninguno",
  "maquinaria_asalariado", "local_propio_asalariado",
  "vehiculo_propio_asalariado", "vacaciones_asalariado",
  "aguinaldo_asalariado", "dias_enfermedad_asalariado",
  "obra_social_asalariado", "sin_beneficio_asalariado",
  "desc_jubilatorio_asalariado", "aporte_jubilatorio_asalariado",
  "desc_jubilatorio_empleador", "emite_factura_empleador",
  "tiene_contador_empleador", "turno_trabajo_asalariado",
  "comprobante_asalariado", "parte_comprobante_asalariado",
  "prop_parte_comprobante_asalariado", "cobro_sueldo", "cobro_sueldo_real",
  "cobro_tickets", "cobro_tickets_real", "cobro_comision",
  "cobro_comision_real", "cobro_propina", "cobro_propina_real",
  "dedicacion_tipo_asalariado", "dedicacion_dia_semana_asalariado",
  "dedicacion_dia_mes_asalariado", "dedicacion_hora_dia_asalariado",
  "cobro_aguinaldo", "cobro_aguinaldo_real", "cobro_otro", "cobro_otro_real",
  "cobro_retroactivo", "cobro_retroactivo_real", "lugar_trabajo_gba",
  "lugar_trabajo_gba_esp", "lugar_trabajo_prov", "lugar_trabajo_prov_donde",
  "lugar_trabajo_prov_esp", "tiempo_busca_trabajo",
  "razon_desocupado_reciente", "razon_desocupado_edad",
  "razon_desocupado_falta_esp", "razon_desocupado_experiencia",
  "razon_desocupado_vinculos", "razon_desocupado_falta_gral",
  "razon_desocupado_recursos", "razon_desocupado_suspendido",
  "razon_desocupado_otro", "razon_desocupado_desconoce",
  "changa_busca_trabajo", "trabajo_antes", "tiempo_ultimo_trabajo",
  "tipo_organizacion_desocupado", "codigo_desocupado", "division_desocupado",
  "seccion_desocupado", "servicio_domestico_desocupado",
  "meses_trabajo_desocupado", "anios_trabajo_desocupado",
  "dias_trabajo_desocupado", "antiguedad_ocup_anterior",
  "cantidad_empleados_desocupado", "rango_empleados_desocupado",
  "codigo_ocupacion_desempleado", "caracter_desocupado",
  "jerarquia_desocupado", "tecnologia_desocupado", "calificacion_desocupado",
  "anios_trabajo_cont_desocupado", "meses_trabajo_cont_desocupado",
  "dias_trabajo_cont_desocupado", "trabajo_cont_ocupacion_anterior",
  "motivo_dejo_actividad", "estabilidad_trabajo_desocupado",
  "regularidad_trabajo_desocupado", "tipo_trabajo_desocupado",
  "descuento_jubilatorio_desocupado", "motivo_dejo_trabajo", "cerro_empresa",
  "unico_desempleado", "despido_telegrama", "despido_indemnizacion",
  "cobra_seguro_desempleo", "caracter", "jerarquia", "tecnologia",
  "calificacion", "direccion", "cta_propia", "jefe", "asalariado", "sin_maq",
  "maq_equipo", "sistemas", "org_directiva", "profesional", "tecnico",
  "operativo", "no_calificado", "ingreso_ocupacion_principal",
  "ingreso_real_ocupacion_principal", "decocur", "idecocur", "rdecocur",
  "gdecocur", "pdecocur", "adecocur", "pondiio", "ingreso_otras_ocupaciones",
  "ingreso_real_otras_ocupaciones", "ingreso_total_individual",
  "ingreso_real_total_individual", "decindr", "idecindr", "rdecindr",
  "gdecindr", "pdecindr", "adecindr", "pondii", "ingreso_no_laborable",
  "ingreso_real_no_laborable", "p_deccf", "p_ideccf", "p_rdeccf", "p_gdeccf",
  "p_pdeccf", "p_adeccf"
)

# REASIGNACIÓN A NIVEL DE REGISTRO: el campo `base` del Diccionario clasifica
# estas 55 variables como "Hogar" porque pertenecen a la sección "estrategias
# del hogar / ingresos no laborales" del cuestionario, pero en el DISEÑO DE
# REGISTRO de INDEC sus variables de origen (V2_M, V5_M, ..., V19_AM: montos
# por PERCEPTOR) viven en la base INDIVIDUAL, y sus valores difieren entre
# miembros del mismo hogar (verificado empíricamente sobre 2017-2025: no son
# constantes dentro del hogar). Se asignan a la base individual; colapsarlas
# a una fila por hogar destruiría información. `tareas_hogar` (creada) también
# es por persona. Esta reasignación se aplica sobre cualquier clasificación
# (embebida o JSON externo) y es idempotente.
# [EN] RECORD-LEVEL REASSIGNMENT: the Dictionary's `base` field classifies
#      these 55 variables as "Hogar" because they belong to the household
#      strategies / non-labor income section of the questionnaire, but in
#      INDEC's RECORD LAYOUT their source variables (V2_M, V5_M, ...,
#      V19_AM: per-RECIPIENT amounts) live in the INDIVIDUAL base, and their
#      values differ across members of the same household (verified
#      empirically over 2017-2025: not constant within households). They are
#      assigned to the individual base; collapsing them to one row per
#      household would destroy information. `tareas_hogar` (created) is also
#      person-level. This reassignment applies to any classification
#      (embedded or external JSON) and is idempotent.
.SEPARA_REASIGNA_INDIVIDUO <- c(
  "ingreso_aguinaldo", "ingreso_alquiler", "ingreso_beca", "ingreso_beca_gob",
  "ingreso_beca_priv", "ingreso_cuota_alimentaria", "ingreso_indemnizacion",
  "ingreso_jub_amacasa_aguinaldo", "ingreso_jub_amacasa_retroactivo",
  "ingreso_jubilacion", "ingreso_jubilacion_aguinaldo",
  "ingreso_jubilacion_ama_casa", "ingreso_jubilacion_otros",
  "ingreso_jubilacion_retroactivo", "ingreso_jubilacion_trabajo",
  "ingreso_menores", "ingreso_negocio", "ingreso_otra_pension_aguinaldo",
  "ingreso_otra_pension_retroactivo", "ingreso_otro",
  "ingreso_real_aguinaldo", "ingreso_real_alquiler", "ingreso_real_beca",
  "ingreso_real_beca_gob", "ingreso_real_beca_priv",
  "ingreso_real_cuota_alimentaria", "ingreso_real_indemnizacion",
  "ingreso_real_jub_amacasa_aguinaldo",
  "ingreso_real_jub_amacasa_retroactivo", "ingreso_real_jubilacion",
  "ingreso_real_jubilacion_aguinaldo", "ingreso_real_jubilacion_ama_casa",
  "ingreso_real_jubilacion_otros", "ingreso_real_jubilacion_retroactivo",
  "ingreso_real_jubilacion_trabajo", "ingreso_real_menores",
  "ingreso_real_negocio", "ingreso_real_otra_pension_aguinaldo",
  "ingreso_real_otra_pension_retroactivo", "ingreso_real_otro",
  "ingreso_real_renta", "ingreso_real_retroactivo",
  "ingreso_real_seguro_desempleo", "ingreso_real_subsidio",
  "ingreso_real_subsidio_auh", "ingreso_real_subsidio_caridad",
  "ingreso_real_subsidio_otro_gob", "ingreso_renta", "ingreso_retroactivo",
  "ingreso_seguro_desempleo", "ingreso_subsidio", "ingreso_subsidio_auh",
  "ingreso_subsidio_caridad", "ingreso_subsidio_otro_gob", "tareas_hogar"
)

# Identificación compartida (replica la convención de las bases INDEC: las
# claves y el contexto geográfico/muestral van en AMBAS bases).
# [EN] Shared identification (replicates the INDEC user-base convention:
#      keys and geographic/sampling context go in BOTH bases).
.SEPARA_IDENT_AMBAS <- c("codusu", "nro_hogar", "id_hogar", "id_hogar_trim",
                         "anio", "trimestre", "region", "mas_500",
                         "aglomerado", "pondera")
# Identificación exclusiva de la base hogar (REALIZADA es del registro hogar).
# [EN] Household-only identification (REALIZADA belongs to the household
#      register).
.SEPARA_IDENT_HOGAR <- c("realizada")
# Identificación exclusiva de la base individual.
# [EN] Individual-only identification.
.SEPARA_IDENT_INDIVIDUO <- c("componente", "entrevista", "id_individuo",
                             "id_individuo_hist")


# ------------------------------------------------------------------------------
# Función principal
# [EN] Main function
# ------------------------------------------------------------------------------
separa_eph <- function(entrada,
                       guardar = TRUE,
                       dir_salida = NULL,
                       nombres_salida = NULL,
                       sufijos = c("_hogar", "_individual"),
                       sobrescribir = FALSE,
                       diccionario = NULL,
                       desconocidas = c("error", "individual", "omitir"),
                       verbose = TRUE) {

  desconocidas <- match.arg(desconocidas)
  clasif <- .separa_clasificacion(diccionario)

  # --- Entrada: data.frame ya cargado -------------------------------------------
  # [EN] Input: data.frame already loaded in the session
  if (is.data.frame(entrada)) {
    res <- .separa_procesa(entrada, origen = "(data.frame en memoria)",
                           ruta_entrada = NULL, guardar = guardar,
                           dir_salida = dir_salida,
                           nombres = .separa_normaliza_nombres(nombres_salida, 1L)[[1]],
                           sufijos = sufijos, sobrescribir = sobrescribir,
                           clasif = clasif, desconocidas = desconocidas,
                           verbose = verbose)
    out <- list(resumen = res$resumen,
                datos = if (guardar) NULL else
                  stats::setNames(list(res$datos), res$resumen$periodo))
    return(invisible(out))
  }

  # --- Entrada: carpeta ----------------------------------------------------------
  # [EN] Input: a folder -> auto-detect layer-1 EPH .RData files
  if (length(entrada) == 1L && dir.exists(entrada)) {
    rutas <- list.files(entrada, pattern = "^EPH20[0-9]{2}_T[1-4]\\.RData$",
                        ignore.case = TRUE, full.names = TRUE)
    if (length(rutas) == 0L) {
      stop("En la carpeta ", entrada, " no se encontraron bases de capa 1 ",
           "(patrón EPH20AA_TN.RData).", call. = FALSE)
    }
    if (verbose) message("Carpeta ", entrada, ": ", length(rutas),
                         " archivo(s) detectado(s).")
    entrada <- sort(rutas)
  }

  # --- Entrada: rutas a .RData ----------------------------------------------------
  # [EN] Input: paths to .RData files
  inexistentes <- entrada[!file.exists(entrada)]
  if (length(inexistentes) > 0L) {
    stop("No se encuentran estos archivos:\n  ",
         paste(inexistentes, collapse = "\n  "), call. = FALSE)
  }
  n <- length(entrada)
  if (!is.null(dir_salida)) {
    if (!length(dir_salida) %in% c(1L, n)) {
      stop("'dir_salida' debe tener 1 valor o uno por archivo.", call. = FALSE)
    }
    dir_salida <- rep_len(dir_salida, n)
  }
  nombres <- .separa_normaliza_nombres(nombres_salida, n)

  filas <- vector("list", n)
  datos_out <- vector("list", n)
  for (k in seq_len(n)) {
    if (verbose) message("\n=== ", k, "/", n, ": ", basename(entrada[k]), " ===")
    res <- tryCatch({
      df <- .separa_carga_rdata(entrada[k])
      .separa_procesa(df, origen = basename(entrada[k]),
                      ruta_entrada = entrada[k], guardar = guardar,
                      dir_salida = if (is.null(dir_salida)) NULL else dir_salida[k],
                      nombres = nombres[[k]], sufijos = sufijos,
                      sobrescribir = sobrescribir, clasif = clasif,
                      desconocidas = desconocidas, verbose = verbose)
    }, error = function(e) {
      message("ERROR en ", basename(entrada[k]), ": ", conditionMessage(e))
      list(resumen = data.frame(
        archivo = basename(entrada[k]), periodo = NA_character_,
        estado = paste0("ERROR: ", conditionMessage(e)),
        n_filas = NA_integer_, n_hogares = NA_integer_,
        n_individuos = NA_integer_, n_vars_hogar = NA_integer_,
        n_vars_individual = NA_integer_, vars_desconocidas = NA_character_,
        salida_hogar = NA_character_, salida_individual = NA_character_,
        stringsAsFactors = FALSE
      ), datos = NULL)
    })
    filas[[k]] <- res$resumen
    datos_out[[k]] <- res$datos
  }
  resumen <- do.call(rbind, filas)
  rownames(resumen) <- NULL

  if (verbose) {
    message("\n=== Resumen separa_eph ===")
    print(resumen[, c("archivo", "periodo", "estado", "n_hogares",
                      "n_individuos", "n_vars_hogar", "n_vars_individual")])
  }
  if (any(grepl("^ERROR", resumen$estado))) {
    warning("Una o más entradas terminaron con error. Revise la columna ",
            "'estado' del resumen.", call. = FALSE)
  }
  datos <- NULL
  if (!guardar) {
    etiquetas <- ifelse(is.na(resumen$periodo),
                        paste0("entrada_", seq_len(n)), resumen$periodo)
    datos <- stats::setNames(datos_out, etiquetas)
  }
  invisible(list(resumen = resumen, datos = datos))
}


# ------------------------------------------------------------------------------
# Procesamiento de un dataset de capa 1
# [EN] Processing of one layer-1 dataset
# ------------------------------------------------------------------------------
.separa_procesa <- function(df, origen, ruta_entrada, guardar, dir_salida,
                            nombres, sufijos, sobrescribir, clasif,
                            desconocidas, verbose) {

  claves <- c("codusu", "nro_hogar")
  if (!all(claves %in% names(df))) {
    stop("la entrada no parece una base EPH-Observatorio de capa 1: faltan ",
         "las columnas ", paste(setdiff(claves, names(df)), collapse = ", "),
         ". Este script trabaja con los nombres etiquetados (no con los ",
         "códigos INDEC originales; para esos, ver bridge_eph.R).")
  }

  # --- Período -------------------------------------------------------------------
  # [EN] Period detection (anio + trimestre)
  periodo <- if (all(c("anio", "trimestre") %in% names(df))) {
    per <- unique(paste0(df$anio, "-T", df$trimestre))
    if (length(per) == 1L) per else paste(per, collapse = "+")
  } else NA_character_
  if (verbose && !is.na(periodo)) message("Período: ", periodo)

  # --- Clasificación de columnas ---------------------------------------------------
  # [EN] Column classification: every dataset column must be known; the
  #      intersect() below assigns to each base only the columns present in
  #      THIS quarter (legacy and new quarters carry different column sets)
  cols_conocidas <- c(clasif$hogar, clasif$individuo, .SEPARA_IDENT_AMBAS,
                      .SEPARA_IDENT_HOGAR, .SEPARA_IDENT_INDIVIDUO)
  sin_clasificar <- setdiff(names(df), cols_conocidas)
  if (length(sin_clasificar) > 0L) {
    if (desconocidas == "error") {
      stop("hay ", length(sin_clasificar), " columna(s) sin clasificar en el ",
           "diccionario embebido: ", paste(sin_clasificar, collapse = ", "),
           ". Use diccionario = 'ruta/a/eph_dict_capa1.json' actualizado, o ",
           "desconocidas = 'individual'/'omitir'.")
    }
    message("Aviso: ", length(sin_clasificar), " columna(s) sin clasificar (",
            paste(sin_clasificar, collapse = ", "), ") -> ",
            if (desconocidas == "individual") "asignadas a la base individual."
            else "omitidas.")
  }

  ident_ambas <- intersect(names(df), .SEPARA_IDENT_AMBAS)
  cols_hogar <- intersect(names(df),
                          c(.SEPARA_IDENT_AMBAS, .SEPARA_IDENT_HOGAR,
                            clasif$hogar))
  cols_indiv <- intersect(names(df),
                          c(.SEPARA_IDENT_AMBAS, .SEPARA_IDENT_INDIVIDUO,
                            clasif$individuo,
                            if (desconocidas == "individual") sin_clasificar))

  # --- Chequeo de constancia de las variables hogar dentro del hogar ----------------
  # [EN] Constancy check: every variable classified as household-level must
  #      be constant within the household before collapsing to one row per
  #      household; warn about exceptions (first occurrence is kept)
  clave <- paste(df$codusu, df$nro_hogar, sep = "\r")
  ref <- match(clave, clave)   # primera aparición de cada hogar
                               # [EN] first occurrence of each household
  vars_chequeo <- setdiff(cols_hogar, ident_ambas)
  no_constantes <- character(0)
  for (v in vars_chequeo) {
    x <- df[[v]]
    xr <- x[ref]
    distinta <- !((is.na(x) & is.na(xr)) |
                    (!is.na(x) & !is.na(xr) & x == xr))
    if (any(distinta)) no_constantes <- c(no_constantes, v)
  }
  if (length(no_constantes) > 0L) {
    warning("Variable(s) clasificada(s) como hogar que NO son constantes ",
            "dentro del hogar (se toma el valor de la primera aparición): ",
            paste(no_constantes, collapse = ", "), call. = FALSE)
  }

  # --- Separación -----------------------------------------------------------------
  # [EN] The split itself: household base = first row per household;
  #      individual base = person rows (componente not NA)
  hogar <- .separa_subset(df, !duplicated(clave), cols_hogar)

  if ("componente" %in% names(df)) {
    es_persona <- !is.na(df$componente)
    if (verbose && any(!es_persona)) {
      message(sum(!es_persona), " fila(s) de hogares sin individuos ",
              "encuestados: van a la base hogar, se excluyen de la individual.")
    }
  } else {
    es_persona <- rep(TRUE, nrow(df))
    message("Aviso: no existe la columna 'componente'; la base individual ",
            "conserva todas las filas.")
  }
  individual <- .separa_subset(df, es_persona, cols_indiv)

  if (verbose) {
    message("Hogar: ", nrow(hogar), " hogares x ", ncol(hogar), " variables | ",
            "Individual: ", nrow(individual), " personas x ",
            ncol(individual), " variables.")
  }

  # --- Salida ---------------------------------------------------------------------
  # [EN] Output: .RData files (objects `hogar` and `individual`) or in-memory
  salida_hogar <- salida_indiv <- NA_character_
  datos_par <- NULL
  if (guardar) {
    base_nombre <- if (!is.null(ruta_entrada)) {
      sub("\\.[^.]*$", "", basename(ruta_entrada))
    } else if (!is.na(periodo)) {
      paste0("EPH", sub("-", "_", periodo))
    } else "eph_capa1"
    destino <- if (!is.null(dir_salida)) dir_salida
               else if (!is.null(ruta_entrada)) dirname(ruta_entrada)
               else getwd()
    if (!dir.exists(destino)) dir.create(destino, recursive = TRUE)

    nom_h <- if (is.na(nombres["hogar"]))
      paste0(base_nombre, sufijos[1], ".RData") else nombres["hogar"]
    nom_i <- if (is.na(nombres["individual"]))
      paste0(base_nombre, sufijos[2], ".RData") else nombres["individual"]
    salida_hogar <- file.path(destino, nom_h)
    salida_indiv <- file.path(destino, nom_i)

    for (ruta_out in c(salida_hogar, salida_indiv)) {
      if (!is.null(ruta_entrada) &&
          suppressWarnings(normalizePath(ruta_out, mustWork = FALSE)) ==
          normalizePath(ruta_entrada)) {
        stop("la ruta de salida coincide con la de entrada (", ruta_out, ").")
      }
      if (file.exists(ruta_out) && !sobrescribir) {
        stop("el archivo de salida ya existe: ", ruta_out,
             ". Use sobrescribir = TRUE para reemplazarlo.")
      }
    }
    save(hogar, file = salida_hogar)
    save(individual, file = salida_indiv)
    if (verbose) {
      message("Guardado: ", salida_hogar, " (objeto `hogar`)")
      message("Guardado: ", salida_indiv, " (objeto `individual`)")
    }
  } else {
    datos_par <- list(hogar = hogar, individual = individual)
  }

  list(
    resumen = data.frame(
      archivo            = origen,
      periodo            = periodo,
      estado             = "ok",
      n_filas            = nrow(df),
      n_hogares          = nrow(hogar),
      n_individuos       = nrow(individual),
      n_vars_hogar       = ncol(hogar),
      n_vars_individual  = ncol(individual),
      vars_desconocidas  = paste(sin_clasificar, collapse = ", "),
      salida_hogar       = salida_hogar,
      salida_individual  = salida_indiv,
      stringsAsFactors   = FALSE
    ),
    datos = datos_par
  )
}


# ------------------------------------------------------------------------------
# Auxiliares
# [EN] Helpers
# ------------------------------------------------------------------------------

# Subset de filas + columnas que preserva los atributos de cada columna
# (las etiquetas `label` de labelled:: se pierden con el subset estándar de
# vectores atómicos; acá se restauran).
# [EN] Row + column subset that preserves each column's attributes (the
#      labelled:: `label` attributes are dropped by standard atomic-vector
#      subsetting; they are restored here).
.separa_subset <- function(df, filas, cols) {
  out <- df[filas, cols, drop = FALSE]
  for (v in cols) {
    a <- attributes(df[[v]])
    a$names <- NULL                       # names por elemento no se replican
                                          # [EN] per-element names not carried
    if (length(a) > 0L) {
      for (nm in names(a)) attr(out[[v]], nm) <- a[[nm]]
    }
  }
  rownames(out) <- NULL
  out
}

# Carga un .RData de capa 1 y devuelve su data.frame (objeto `datos`, o el
# único data.frame presente).
# [EN] Loads a layer-1 .RData and returns its data.frame (the `datos` object,
#      or the single data.frame present).
.separa_carga_rdata <- function(ruta) {
  amb <- new.env(parent = emptyenv())
  load(ruta, envir = amb)
  objetos <- ls(amb)
  if ("datos" %in% objetos && is.data.frame(amb$datos)) return(amb$datos)
  dfs <- objetos[vapply(objetos, function(o) is.data.frame(amb[[o]]),
                        logical(1))]
  if (length(dfs) == 1L) return(amb[[dfs]])
  stop("el archivo ", basename(ruta), " no contiene un data.frame de capa 1 ",
       "reconocible (se esperaba el objeto `datos`).")
}

# Clasificación a usar: la embebida, o la regenerada desde un JSON del
# diccionario si el usuario pasa `diccionario=` (requiere jsonlite). En ambos
# casos se aplica la reasignación a nivel de registro (ver
# .SEPARA_REASIGNA_INDIVIDUO).
# [EN] Classification to use: the embedded one, or one rebuilt from a
#      dictionary JSON if the user passes `diccionario=` (requires jsonlite).
#      In both cases the record-level reassignment is applied (see
#      .SEPARA_REASIGNA_INDIVIDUO).
.separa_clasificacion <- function(diccionario) {
  if (is.null(diccionario)) {
    clasif <- list(hogar = .SEPARA_VARS_HOGAR,
                   individuo = .SEPARA_VARS_INDIVIDUO)
  } else {
    if (!requireNamespace("jsonlite", quietly = TRUE)) {
      stop("Para usar 'diccionario =' se necesita el paquete jsonlite ",
           "(install.packages('jsonlite')), o bien omita el argumento para ",
           "usar la clasificación embebida.", call. = FALSE)
    }
    if (!file.exists(diccionario)) {
      stop("No se encuentra el diccionario: ", diccionario, call. = FALSE)
    }
    vars <- jsonlite::fromJSON(diccionario)$variables
    clasif <- list(hogar     = vars$name[vars$base == "Hogar"],
                   individuo = vars$name[vars$base == "Individuos"])
  }
  list(
    hogar     = setdiff(clasif$hogar, .SEPARA_REASIGNA_INDIVIDUO),
    individuo = union(clasif$individuo, .SEPARA_REASIGNA_INDIVIDUO)
  )
}

# Normaliza nombres_salida a lista de length n con c(hogar=, individual=).
# [EN] Normalizes nombres_salida to a length-n list of c(hogar=, individual=).
.separa_normaliza_nombres <- function(nombres_salida, n) {
  vacio <- c(hogar = NA_character_, individual = NA_character_)
  if (is.null(nombres_salida)) return(rep(list(vacio), n))
  if (is.character(nombres_salida) && length(nombres_salida) == 2L) {
    nombres_salida <- list(nombres_salida)
  }
  if (!is.list(nombres_salida) || length(nombres_salida) != n) {
    stop("'nombres_salida' debe ser un vector c(hogar = ..., individual = ...)",
         " para una entrada, o una lista de esos vectores (una por entrada).",
         call. = FALSE)
  }
  lapply(nombres_salida, function(x) {
    if (!is.character(x) || length(x) != 2L) {
      stop("Cada elemento de 'nombres_salida' debe tener 2 nombres ",
           "(hogar e individual).", call. = FALSE)
    }
    if (is.null(names(x)) || !all(c("hogar", "individual") %in% names(x))) {
      names(x) <- c("hogar", "individual")
    }
    x[c("hogar", "individual")]
  })
}
