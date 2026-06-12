# ==============================================================================
# bridge_eph.R — Puente de comparabilidad para las bases usuarias de la EPH
#                Comparability bridge for the EPH user databases
# ==============================================================================
#
# QUE HACE
# --------
# A partir del 4to trimestre de 2024, INDEC modificó el cuestionario de la EPH:
# varias variables agregadas de las bases usuarias desaparecieron y fueron
# "atomizadas" en sub-componentes por fuente. Este script reconstruye, sobre
# las bases usuarias ORIGINALES de INDEC (formato .txt), las variables
# eliminadas, para mantener la comparabilidad con la serie histórica:
#
#   Base HOGAR (estado sí/no de estrategias del hogar):
#     - V5   (subsidio en dinero)        <- V5_01,  V5_02,  V5_03
#     - V11  (beca de estudio)           <- V11_01, V11_02
#     - V21  (aguinaldo)                 <- V21_01, V21_02, V21_03
#     - V22  (retroactivos)              <- V22_01, V22_02, V22_03
#
#   Base INDIVIDUAL (montos de ingresos no laborales):
#     - V2_M  (jubilación/pensión)       <- V2_01_M,  V2_02_M,  V2_03_M
#     - V5_M  (subsidio en dinero)       <- V5_01_M,  V5_02_M,  V5_03_M
#     - V11_M (beca de estudio)          <- V11_01_M, V11_02_M
#     - V21_M (aguinaldo)                <- V21_01_M, V21_02_M, V21_03_M
#     - V22_M (retroactivos)             <- V22_01_M, V22_02_M, V22_03_M
#
#   Además corrige, si detecta la condición de error, la inversión de las
#   variables PP11L1 y PP11L2 de la base individual (los contenidos de ambas
#   columnas aparecen intercambiados en las bases publicadas).
#
# La lógica de imputación replica exactamente la del pipeline EPH-Observatorio
# (script/new/02.check.R) y está documentada en la Parte A del:
#
#   Manual Metodológico EPH – Observatorio (UNR)
#   RepHip UNR: https://hdl.handle.net/2133/33253
#   Dataverse:  https://doi.org/10.57715/UNR/BL85Z8
#
# Referencia académica de las reglas de reconstrucción:
#   Tessmer, G. & Boggiano, B. (2026) "From Breaks to Bridges: Harmonizing the
#   New and Old Permanent Household Survey for Consistent Labor Market Series"
#   (SSRN 6597399).
#
# PARA QUIEN ES
# -------------
# Para usuarios que trabajan con las bases usuarias CRUDAS de INDEC
# (usu_hogar_TNAA.txt + usu_individual_TNAA.txt). Quien use las bases
# EPH-Observatorio (capa 1) NO necesita este script: ya traen las variables
# reconstruidas.
#
# REQUISITOS
# ----------
# R >= 3.5. No requiere ningún paquete adicional (solo R base).
#
# USO
# ---
#   source("bridge_eph.R")
#
#   # 1) Un par de bases (hogar + individual del mismo trimestre):
#   bridge_eph(
#     hogar      = "C:/mis_bases/usu_hogar_T125.txt",
#     individual = "C:/mis_bases/usu_individual_T125.txt"
#   )
#
#   # 2) Varios pares (se emparejan por posición):
#   bridge_eph(
#     hogar      = c("C:/eph/usu_hogar_T125.txt", "C:/eph/usu_hogar_T225.txt"),
#     individual = c("C:/eph/usu_individual_T125.txt", "C:/eph/usu_individual_T225.txt")
#   )
#
#   # 3) Una carpeta: detecta automáticamente todos los pares usu_hogar_tNAA /
#   #    usu_individual_tNAA presentes (mayúsculas o minúsculas, indistinto):
#   bridge_eph("C:/mis_bases")
#
#   # 4) Un único .txt por trimestre con el join hogar + individual:
#   bridge_eph(hogar, individual, salida = "join")
#
#   # 5) Sin guardar nada: devuelve las bases procesadas en memoria (con los
#   #    tipos ya convertidos, como las leería read.table):
#   r <- bridge_eph(hogar, individual, guardar = FALSE)
#   r$datos[["2025-T1"]]$hogar        # base hogar puenteada
#   r$datos[["2025-T1"]]$individual   # base individual puenteada
#
#   r <- bridge_eph(hogar, individual, guardar = FALSE, salida = "join")
#   r$datos[["2025-T1"]]$join         # base unida hogar + individual
#
# PARAMETROS
# ----------
#   hogar          Ruta(s) a la(s) base(s) de hogar (.txt de INDEC), o una
#                  carpeta que las contenga (en ese caso omitir 'individual').
#                  Los nombres de archivo se reconocen sin distinguir
#                  mayúsculas/minúsculas (usu_hogar_T125.txt, usu_hogar_t125.txt
#                  y USU_HOGAR_T125.TXT son equivalentes).
#   individual     Ruta(s) a la(s) base(s) individuales, pareadas por posición.
#   guardar        Si TRUE (default), escribe los archivos de salida. Si FALSE,
#                  no escribe nada y devuelve las bases procesadas en memoria
#                  (en $datos; se ignoran dir_salida/nombres_salida/sobrescribir).
#   salida         "separadas" (default): dos .txt por par, uno con la base
#                  hogar + sus variables reconstruidas y otro con la base
#                  individual + las suyas. "join": un único .txt por par con la
#                  unión hogar + individual (por CODUSU + NRO_HOGAR, replicando
#                  el join del pipeline EPH-Observatorio) más todas las
#                  variables reconstruidas.
#   dir_salida     Carpeta donde guardar los resultados. Por defecto, la misma
#                  carpeta de cada archivo de entrada. Acepta un valor único o
#                  uno por par.
#   nombres_salida Nombres de los archivos de salida. Con salida = "separadas":
#                  vector c(hogar = "...", individual = "...") para un par, o
#                  una lista de esos vectores para varios. Con salida = "join":
#                  un nombre por par. Por defecto se usa el nombre del archivo
#                  original + sufijo (ej: usu_hogar_T125_bridge.txt; para el
#                  join: usu_hogar_individual_T125_bridge.txt).
#   sufijo         Sufijo del nombre por defecto ("_bridge").
#   sobrescribir   Si FALSE (default), no pisa archivos de salida existentes.
#   verbose        Si TRUE (default), informa el detalle del procesamiento.
#
# SALIDA
# ------
# Con guardar = TRUE escribe, por cada par, dos .txt (salida = "separadas") o
# uno (salida = "join") con EXACTAMENTE el mismo formato que los originales de
# INDEC (separador ";", decimales con coma, campos de texto entre comillas,
# celdas vacías para datos faltantes). Todas las columnas originales se copian
# textualmente, sin alterar ningún valor; las variables reconstruidas se
# agregan al final de cada base. La única modificación sobre columnas
# existentes es el intercambio PP11L1/PP11L2 cuando corresponde.
#
# La función devuelve (invisible) una lista con dos elementos:
#   $resumen  data.frame con un renglón por par: período, estado, variables
#             creadas y rutas de salida.
#   $datos    NULL si guardar = TRUE (los datos quedan en los archivos).
#             Si guardar = FALSE, una lista nombrada por período; cada elemento
#             contiene los data.frames procesados ($hogar y $individual, o
#             $join), con los tipos ya convertidos como los leería read.table.
#
# NOTAS
# -----
# - Las bases anteriores al 4to trimestre de 2024 ("legacy") no necesitan
#   puente: se detectan y se omiten con un aviso.
# - Si una variable agregada ya existe en la base, o faltan sus
#   sub-componentes, se omite su reconstrucción con un aviso (mismas
#   condiciones de seguridad que el pipeline EPH-Observatorio).
# - En el modo "join", los hogares sin individuos encuestados quedan con las
#   columnas individuales vacías (igual que el join del pipeline) y la columna
#   REALIZADA vacía se completa con 0.
#
# ==============================================================================
#
# [EN] ENGLISH NOTES
# ==============================================================================
#
# WHAT IT DOES
# ------------
# Starting in Q4-2024, INDEC redesigned the EPH questionnaire: several
# aggregate variables disappeared from the user databases and were "atomized"
# into sub-components by source. This script reconstructs, on top of the RAW
# INDEC user databases (.txt format), the removed variables, so that the new
# bases remain comparable with the historical series:
#
#   HOUSEHOLD base (yes/no household livelihood strategies):
#     - V5  (cash subsidy)          <- V5_01,  V5_02,  V5_03
#     - V11 (scholarship)           <- V11_01, V11_02
#     - V21 (annual bonus)          <- V21_01, V21_02, V21_03
#     - V22 (retroactive payments)  <- V22_01, V22_02, V22_03
#
#   INDIVIDUAL base (non-labor income amounts, per recipient):
#     - V2_M  (pension)             <- V2_01_M,  V2_02_M,  V2_03_M
#     - V5_M  (cash subsidy)        <- V5_01_M,  V5_02_M,  V5_03_M
#     - V11_M (scholarship)         <- V11_01_M, V11_02_M
#     - V21_M (annual bonus)        <- V21_01_M, V21_02_M, V21_03_M
#     - V22_M (retroactive paym.)   <- V22_01_M, V22_02_M, V22_03_M
#
#   It also fixes, when the error condition is detected, the inversion of
#   variables PP11L1 and PP11L2 in the individual base (their contents appear
#   swapped in the published bases).
#
# The imputation logic exactly replicates the EPH-Observatorio pipeline
# (script/new/02.check.R) and is documented in Part A of the Methodological
# Manual (RepHip UNR: https://hdl.handle.net/2133/33253; Dataverse:
# https://doi.org/10.57715/UNR/BL85Z8). Academic reference for the
# reconstruction rules: Tessmer & Boggiano (2026), "From Breaks to Bridges"
# (SSRN 6597399).
#
# WHO IT IS FOR
# -------------
# Users working with the RAW INDEC user databases (usu_hogar_TNAA.txt +
# usu_individual_TNAA.txt). Users of the EPH-Observatorio datasets (layer 1)
# do NOT need this script: those already include the rebuilt variables.
#
# REQUIREMENTS
# ------------
# R >= 3.5. No additional packages required (base R only). Runtime messages
# are printed in Spanish.
#
# USAGE
# -----
# Same call patterns as the Spanish examples above:
#   bridge_eph(hogar = "...usu_hogar_T125.txt",
#              individual = "...usu_individual_T125.txt")   # one pair
#   bridge_eph(c(h1, h2), c(i1, i2))                        # several pairs
#   bridge_eph("C:/my_bases")                               # folder mode:
#                                            # auto-detects pairs, case-insensitive
#   bridge_eph(h, i, salida = "join")                       # one joined .txt
#   r <- bridge_eph(h, i, guardar = FALSE)                  # in-memory, no files
#
# PARAMETERS
# ----------
#   hogar          Path(s) to the household base(s) (INDEC .txt), or a folder
#                  containing them (omit 'individual' in that case). File
#                  names are matched case-insensitively.
#   individual     Path(s) to the individual base(s), paired by position.
#   guardar        TRUE (default) writes the output files. FALSE writes
#                  nothing and returns the processed data.frames in $datos
#                  (dir_salida/nombres_salida/sobrescribir are ignored).
#   salida         "separadas" (default): two .txt per pair (household and
#                  individual, each with its rebuilt variables). "join": one
#                  .txt per pair with the household + individual merge (by
#                  CODUSU + NRO_HOGAR, replicating the pipeline join).
#   dir_salida     Output folder. Defaults to each input file's folder.
#                  Accepts one value, or one per pair.
#   nombres_salida Output file names. For "separadas": c(hogar = ...,
#                  individual = ...) for one pair, or a list of those for
#                  several. For "join": one name per pair. Default: original
#                  file name + suffix (e.g. usu_hogar_T125_bridge.txt).
#   sufijo         Suffix for the default names ("_bridge").
#   sobrescribir   FALSE (default) refuses to overwrite existing outputs.
#   verbose        TRUE (default) reports processing details.
#
# OUTPUT
# ------
# With guardar = TRUE, writes .txt files with EXACTLY the same format as the
# INDEC originals (";" separator, decimal comma, quoted text fields, empty
# cells for missing data). All original columns are copied textually, with no
# value altered; the rebuilt variables are appended at the end of each base.
# The only modification to existing columns is the PP11L1/PP11L2 swap when it
# applies.
#
# The function returns (invisibly) a list with two elements:
#   $resumen  data.frame with one row per pair: period, status, variables
#             created and output paths.
#   $datos    NULL if guardar = TRUE (data live in the files). If
#             guardar = FALSE, a list named by period; each element holds the
#             processed data.frames ($hogar and $individual, or $join), typed
#             as read.table would type them.
#
# NOTES
# -----
# - Bases prior to Q4-2024 ("legacy") need no bridge: they are detected and
#   skipped with a notice.
# - If an aggregate variable already exists in the base, or its
#   sub-components are missing, its reconstruction is skipped with a notice
#   (same safety conditions as the EPH-Observatorio pipeline).
# - In "join" mode, households with no surveyed individuals keep empty
#   individual columns (as in the pipeline join) and an empty REALIZADA is
#   filled with 0.
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Función principal
# [EN] Main function
# ------------------------------------------------------------------------------
bridge_eph <- function(hogar,
                       individual = NULL,
                       guardar = TRUE,
                       salida = c("separadas", "join"),
                       dir_salida = NULL,
                       nombres_salida = NULL,
                       sufijo = "_bridge",
                       sobrescribir = FALSE,
                       verbose = TRUE) {

  salida <- match.arg(salida)

  # --- Modo carpeta: detectar pares automáticamente ---------------------------
  # [EN] Folder mode: auto-detect household/individual pairs
  if (length(hogar) == 1L && is.null(individual) && dir.exists(hogar)) {
    pares <- .bridge_detecta_pares(hogar, verbose = verbose)
    hogar <- pares$hogar
    individual <- pares$individual
  }

  # --- Validación de argumentos ------------------------------------------------
  # [EN] Argument validation
  if (is.null(individual)) {
    stop("Falta el argumento 'individual'. Indique las bases individuales ",
         "pareadas con las de hogar, o pase en 'hogar' una carpeta que ",
         "contenga ambas.", call. = FALSE)
  }
  if (length(hogar) != length(individual)) {
    stop("'hogar' (", length(hogar), ") e 'individual' (", length(individual),
         ") deben tener la misma cantidad de archivos: se emparejan por ",
         "posición.", call. = FALSE)
  }
  inexistentes <- c(hogar, individual)[!file.exists(c(hogar, individual))]
  if (length(inexistentes) > 0L) {
    stop("No se encuentran estos archivos:\n  ",
         paste(inexistentes, collapse = "\n  "), call. = FALSE)
  }

  n_pares <- length(hogar)

  if (!is.null(dir_salida)) {
    if (!length(dir_salida) %in% c(1L, n_pares)) {
      stop("'dir_salida' debe tener 1 valor (común a todos los pares) o uno ",
           "por par.", call. = FALSE)
    }
    dir_salida <- rep_len(dir_salida, n_pares)
  }
  nombres <- .bridge_normaliza_nombres(nombres_salida, n_pares, salida)

  if (!guardar && verbose) {
    message("guardar = FALSE: no se escriben archivos, las bases procesadas ",
            "se devuelven en $datos.")
  }

  # --- Procesamiento por par ----------------------------------------------------
  # [EN] Per-pair processing; an error in one pair does not abort the rest
  filas_resumen <- vector("list", n_pares)
  datos_pares   <- vector("list", n_pares)
  for (k in seq_len(n_pares)) {
    if (verbose) {
      message("\n=== Par ", k, "/", n_pares, ": ",
              basename(hogar[k]), " + ", basename(individual[k]), " ===")
    }
    res <- tryCatch(
      .bridge_procesa_par(
        ruta_hogar   = hogar[k],
        ruta_indiv   = individual[k],
        guardar      = guardar,
        salida       = salida,
        dir_salida   = if (is.null(dir_salida)) NULL else dir_salida[k],
        nombres      = nombres[[k]],
        sufijo       = sufijo,
        sobrescribir = sobrescribir,
        verbose      = verbose
      ),
      error = function(e) {
        message("ERROR en el par ", basename(hogar[k]), " + ",
                basename(individual[k]), ": ", conditionMessage(e))
        list(
          resumen = data.frame(
            archivo_hogar      = basename(hogar[k]),
            archivo_individual = basename(individual[k]),
            periodo            = NA_character_,
            estado             = paste0("ERROR: ", conditionMessage(e)),
            swap_pp11l         = NA,
            vars_hogar         = NA_character_,
            vars_individual    = NA_character_,
            n_hogares          = NA_integer_,
            n_individuos       = NA_integer_,
            salida_hogar       = NA_character_,
            salida_individual  = NA_character_,
            salida_join        = NA_character_,
            stringsAsFactors   = FALSE
          ),
          datos = NULL
        )
      }
    )
    filas_resumen[[k]] <- res$resumen
    datos_pares[[k]]   <- res$datos
  }
  resumen <- do.call(rbind, filas_resumen)
  rownames(resumen) <- NULL

  if (verbose) {
    message("\n=== Resumen bridge_eph ===")
    print(resumen[, c("archivo_hogar", "periodo", "estado",
                      "vars_hogar", "vars_individual")])
  }
  if (any(grepl("^ERROR", resumen$estado))) {
    warning("Uno o más pares terminaron con error. Revise la columna 'estado' ",
            "del resumen.", call. = FALSE)
  }

  if (guardar) {
    datos <- NULL
  } else {
    etiquetas <- ifelse(is.na(resumen$periodo),
                        paste0("par_", seq_len(n_pares)), resumen$periodo)
    datos <- stats::setNames(datos_pares, etiquetas)
  }
  invisible(list(resumen = resumen, datos = datos))
}


# ------------------------------------------------------------------------------
# Procesamiento de un par hogar + individual
# [EN] Processing of one household + individual pair
# ------------------------------------------------------------------------------
.bridge_procesa_par <- function(ruta_hogar, ruta_indiv, guardar, salida,
                                dir_salida, nombres, sufijo, sobrescribir,
                                verbose) {

  # --- 1. Lectura (todas las columnas como texto: copia fiel) -------------------
  # [EN] 1. Read everything as text: faithful passthrough of the original
  #      columns (preserves leading zeros, decimal commas, INDEC quoting)
  base_hogar <- .bridge_lee_base(ruta_hogar)
  base_indiv <- .bridge_lee_base(ruta_indiv)

  # Detectar qué columnas vienen entre comillas en el original (para reescribir
  # el archivo con el mismo estilo). Se hace ANTES de agregar columnas nuevas.
  # [EN] Detect which columns come quoted in the original file (to rewrite
  #      with the same style). Done BEFORE adding new columns.
  comillas_hogar <- .bridge_detecta_comillas(ruta_hogar, names(base_hogar))
  comillas_indiv <- .bridge_detecta_comillas(ruta_indiv, names(base_indiv))

  # --- 2. Chequeo de roles (¿los archivos están invertidos?) --------------------
  # [EN] 2. Role check: are the files swapped? The household base must NOT
  #      have COMPONENTE; the individual base must have it.
  if ("COMPONENTE" %in% names(base_hogar) || !"COMPONENTE" %in% names(base_indiv)) {
    stop("los archivos parecen estar invertidos o no corresponden a bases ",
         "usuarias EPH: la base de hogar no debe tener la columna COMPONENTE ",
         "y la individual debe tenerla. Verifique el orden de los argumentos ",
         "'hogar' e 'individual'.")
  }

  # --- 3. Chequeo de período: ambas bases del mismo trimestre -------------------
  # [EN] 3. Period check: both bases must belong to the same quarter
  per_hogar <- .bridge_periodo(base_hogar, basename(ruta_hogar))
  per_indiv <- .bridge_periodo(base_indiv, basename(ruta_indiv))
  if (!identical(per_hogar, per_indiv)) {
    stop("las bases NO pertenecen al mismo período: ",
         basename(ruta_hogar), " es ", per_hogar["etiqueta"], " y ",
         basename(ruta_indiv), " es ", per_indiv["etiqueta"],
         ". Empareje hogar e individual del mismo trimestre.")
  }
  anio <- as.integer(per_hogar["anio"])
  trim <- as.integer(per_hogar["trimestre"])
  periodo <- unname(per_hogar["etiqueta"])
  if (verbose) message("Período detectado: ", periodo)

  # --- 4. Chequeo de era: el puente aplica solo a bases nuevas (>= 2024-T4) -----
  # [EN] 4. Era check: the bridge only applies to new-methodology bases
  #      (>= 2024-Q4); legacy bases already include the aggregate variables.
  if (anio < 2024L || (anio == 2024L && trim < 4L)) {
    message("Base ", periodo, " anterior al cambio metodológico (4to ",
            "trimestre de 2024): no requiere puente, las variables agregadas ",
            "ya existen. Par omitido.")
    return(list(
      resumen = data.frame(
        archivo_hogar      = basename(ruta_hogar),
        archivo_individual = basename(ruta_indiv),
        periodo            = periodo,
        estado             = "omitido (base legacy, no requiere puente)",
        swap_pp11l         = FALSE,
        vars_hogar         = "",
        vars_individual    = "",
        n_hogares          = nrow(base_hogar),
        n_individuos       = nrow(base_indiv),
        salida_hogar       = NA_character_,
        salida_individual  = NA_character_,
        salida_join        = NA_character_,
        stringsAsFactors   = FALSE
      ),
      datos = NULL
    ))
  }

  # --- 5. Base HOGAR: reconstrucción de estrategias del hogar -------------------
  # Misma lógica y mismas condiciones de seguridad que script/new/02.check.R
  # (sección 3.1) del pipeline EPH-Observatorio.
  # [EN] 5. HOUSEHOLD base: rebuild the yes/no livelihood-strategy aggregates
  #      from their sub-components. Same logic and safety conditions as
  #      pipeline script/new/02.check.R (section 3.1): only rebuild if the
  #      aggregate is absent and all its sub-components exist.
  relaciones_hogar <- list(
    V11 = c("V11_01", "V11_02"),
    V21 = c("V21_01", "V21_02", "V21_03"),
    V22 = c("V22_01", "V22_02", "V22_03"),
    V5  = c("V5_01", "V5_02", "V5_03")
  )

  vars_hogar_creadas <- character(0)
  for (dependiente in names(relaciones_hogar)) {
    independientes <- relaciones_hogar[[dependiente]]
    if (!dependiente %in% names(base_hogar) &&
        all(independientes %in% names(base_hogar))) {
      if (verbose) message("Hogar: reconstruyendo ", dependiente,
                           " a partir de ", paste(independientes, collapse = ", "))
      m <- do.call(cbind, lapply(base_hogar[independientes], .bridge_a_numerico))
      base_hogar[[dependiente]] <- as.integer(
        vapply(seq_len(nrow(m)),
               function(i) as.numeric(.bridge_calcula_dependiente(m[i, ])),
               numeric(1))
      )
      vars_hogar_creadas <- c(vars_hogar_creadas, dependiente)
    } else {
      message("Hogar: se omite '", dependiente,
              "' (ya existe o faltan sus variables de origen).")
    }
  }

  # --- 6. Base INDIVIDUAL: corrección PP11L1/PP11L2 -----------------------------
  # Misma condición de error que script/new/02.check.R (sección 2): PP11L2 trae
  # los niveles 1/2/3 (que corresponden a la PP11L1 del cuestionario legacy) y
  # PP11L1 no registra el nivel 3.
  # [EN] 6. INDIVIDUAL base: PP11L1/PP11L2 swap fix. Same error condition as
  #      pipeline 02.check.R (section 2): PP11L2 carries levels 1/2/3 (which
  #      belong to the legacy PP11L1 question) while PP11L1 never shows
  #      level 3 -> the two columns are swapped in the published base.
  swap_pp11l <- FALSE
  if (all(c("PP11L1", "PP11L2") %in% names(base_indiv))) {
    pp11l1_num <- .bridge_a_numerico(base_indiv$PP11L1)
    pp11l2_num <- .bridge_a_numerico(base_indiv$PP11L2)
    if (all(c(1, 2, 3) %in% unique(pp11l2_num)) && !(3 %in% pp11l1_num)) {
      message("Individual: condición de error detectada -> intercambiando ",
              "PP11L1 y PP11L2.")
      base_indiv[, c("PP11L1", "PP11L2")] <- base_indiv[, c("PP11L2", "PP11L1")]
      swap_pp11l <- TRUE
    }
  }

  # --- 7. Base INDIVIDUAL: reconstrucción de ingresos no laborales --------------
  # Cada monto agregado se reconstruye desde sus sub-componentes, usando como
  # control la variable de estrategia del hogar correspondiente (que viaja de
  # la base hogar a la individual vía CODUSU + NRO_HOGAR; equivale al join de
  # bases del pipeline). Lógica idéntica a script/new/02.check.R (sección 3.2).
  # [EN] 7. INDIVIDUAL base: rebuild the aggregate non-labor income amounts
  #      from their sub-components. Each amount uses the corresponding
  #      household strategy variable as control, carried from the household
  #      base via CODUSU + NRO_HOGAR (equivalent to the pipeline's join).
  #      Logic identical to pipeline 02.check.R (section 3.2).
  relaciones_indiv <- list(
    V11_M = c("V11_01_M", "V11_02_M"),
    V2_M  = c("V2_01_M", "V2_02_M", "V2_03_M"),
    V21_M = c("V21_01_M", "V21_02_M", "V21_03_M"),
    V22_M = c("V22_01_M", "V22_02_M", "V22_03_M"),
    V5_M  = c("V5_01_M", "V5_02_M", "V5_03_M")
  )
  control_dependientes <- c(
    V11_M = "V11", V2_M = "V2", V21_M = "V21", V22_M = "V22", V5_M = "V5"
  )

  clave_hogar <- paste(base_hogar$CODUSU, base_hogar$NRO_HOGAR, sep = "\r")
  if (anyDuplicated(clave_hogar) > 0L) {
    stop("la base de hogar tiene combinaciones CODUSU + NRO_HOGAR duplicadas; ",
         "no es posible asignar controles del hogar a los individuos.")
  }
  idx_hogar <- match(paste(base_indiv$CODUSU, base_indiv$NRO_HOGAR, sep = "\r"),
                     clave_hogar)
  if (anyNA(idx_hogar)) {
    message("Aviso: ", sum(is.na(idx_hogar)), " individuo(s) sin hogar ",
            "correspondiente en la base de hogar (control NA, mismo ",
            "tratamiento que el pipeline).")
  }

  vars_indiv_creadas <- character(0)
  for (dependiente in names(relaciones_indiv)) {
    independientes <- relaciones_indiv[[dependiente]]
    control_actual <- control_dependientes[[dependiente]]
    if (!dependiente %in% names(base_indiv) &&
        all(independientes %in% names(base_indiv)) &&
        control_actual %in% names(base_hogar)) {
      if (verbose) message("Individual: reconstruyendo ", dependiente,
                           " (control del hogar: ", control_actual, ")")
      m <- do.call(cbind, lapply(base_indiv[independientes], .bridge_a_numerico))
      ctrl_hogar <- base_hogar[[control_actual]]
      ctrl_hogar <- if (is.character(ctrl_hogar)) {
        .bridge_a_numerico(ctrl_hogar)
      } else {
        as.numeric(ctrl_hogar)
      }
      ctrl <- ctrl_hogar[idx_hogar]
      base_indiv[[dependiente]] <- vapply(
        seq_len(nrow(m)),
        function(i) .bridge_reconstruye_ingreso(m[i, ], ctrl[i]),
        numeric(1)
      )
      vars_indiv_creadas <- c(vars_indiv_creadas, dependiente)
    } else {
      message("Individual: se omite '", dependiente,
              "' (ya existe, faltan sus variables de origen o falta la ",
              "variable control ", control_actual, " en la base de hogar).")
    }
  }

  # --- 8. Salida: archivos en disco y/o datos en memoria ------------------------
  # [EN] 8. Output: files on disk and/or in-memory data
  salida_hogar <- salida_indiv <- salida_join <- NA_character_
  datos_par <- NULL

  if (salida == "join") {
    union_bases <- .bridge_construye_join(base_hogar, base_indiv, idx_hogar)
    if (guardar) {
      nombre_join <- nombres
      if (is.na(nombre_join)) {
        base_sin_ext <- sub("\\.[^.]*$", "", basename(ruta_hogar))
        nombre_join <- if (grepl("hogar", base_sin_ext, ignore.case = TRUE)) {
          paste0(sub("(?i)hogar", "hogar_individual", base_sin_ext, perl = TRUE),
                 sufijo, ".txt")
        } else {
          paste0("eph_join_", anio, "_T", trim, sufijo, ".txt")
        }
      }
      salida_join <- .bridge_ruta_salida(ruta_hogar, dir_salida,
                                         nombre_join, sufijo)
      .bridge_chequea_destino(salida_join, c(ruta_hogar, ruta_indiv),
                              sobrescribir)
      .bridge_escribe_base(union_bases, salida_join,
                           union(comillas_indiv, comillas_hogar))
      if (verbose) message("Guardado (join): ", salida_join)
    } else {
      datos_par <- list(join = .bridge_tipa(union_bases))
    }
  } else {
    if (guardar) {
      salida_hogar <- .bridge_ruta_salida(ruta_hogar, dir_salida,
                                          nombres["hogar"], sufijo)
      salida_indiv <- .bridge_ruta_salida(ruta_indiv, dir_salida,
                                          nombres["individual"], sufijo)
      .bridge_chequea_destino(salida_hogar, c(ruta_hogar, ruta_indiv),
                              sobrescribir)
      .bridge_chequea_destino(salida_indiv, c(ruta_hogar, ruta_indiv),
                              sobrescribir)
      .bridge_escribe_base(base_hogar, salida_hogar, comillas_hogar)
      .bridge_escribe_base(base_indiv, salida_indiv, comillas_indiv)
      if (verbose) {
        message("Guardado: ", salida_hogar)
        message("Guardado: ", salida_indiv)
      }
    } else {
      datos_par <- list(hogar      = .bridge_tipa(base_hogar),
                        individual = .bridge_tipa(base_indiv))
    }
  }

  list(
    resumen = data.frame(
      archivo_hogar      = basename(ruta_hogar),
      archivo_individual = basename(ruta_indiv),
      periodo            = periodo,
      estado             = "ok",
      swap_pp11l         = swap_pp11l,
      vars_hogar         = paste(vars_hogar_creadas, collapse = ", "),
      vars_individual    = paste(vars_indiv_creadas, collapse = ", "),
      n_hogares          = nrow(base_hogar),
      n_individuos       = nrow(base_indiv),
      salida_hogar       = salida_hogar,
      salida_individual  = salida_indiv,
      salida_join        = salida_join,
      stringsAsFactors   = FALSE
    ),
    datos = datos_par
  )
}


# ------------------------------------------------------------------------------
# Lógica de imputación (idéntica a script/new/02.check.R del pipeline)
# [EN] Imputation logic (identical to pipeline script/new/02.check.R)
# ------------------------------------------------------------------------------

# Estrategias del hogar (variables sí/no): recibe el vector con los valores de
# los sub-componentes de una fila y devuelve el valor de la variable agregada.
# [EN] Household strategies (yes/no variables): takes one row's sub-component
#      values and returns the aggregate variable value. Codes: 1 = Yes,
#      2 = No, 0 = Not applicable, 9 = Don't know / no answer.
.bridge_calcula_dependiente <- function(...) {
  vars <- c(...)

  # Lógica para 2 VARIABLES: regla de "dominancia transitiva" 1 > 2 > 0 > 9.
  # [EN] 2-VARIABLE logic: "transitive dominance" rule 1 > 2 > 0 > 9.
  if (length(vars) == 2) {
    niveles_dominancia <- c(9, 0, 2, 1)
    vars_factor <- factor(vars, levels = niveles_dominancia, ordered = TRUE)
    return(as.integer(as.character(max(vars_factor))))
  }

  # Lógica para 3 VARIABLES: reglas especiales sobre la dominancia estricta.
  # [EN] 3-VARIABLE logic: special rules that override strict dominance.
  if (length(vars) == 3) {
    # Prioridad 1: si existe al menos un 1 (Sí), el resultado es 1 (Sí).
    # [EN] Priority 1: at least one 1 (Yes) -> result is 1 (Yes).
    if (any(vars == 1)) return(1)
    # Prioridad 2: si solo hay 0 (No corresponde) y 9 (Ns/Nr).
    # [EN] Priority 2: only 0 (N/A) and 9 (DK/NA) present...
    if (all(vars %in% c(0, 9))) {
      # ... y hay dos o más 9, el resultado es 9 (Ns/Nr).
      # [EN] ... two or more 9s -> result is 9 (DK/NA).
      if (sum(vars == 9) >= 2) return(9)
      # ... y hay solo un 9, el resultado es 0 (No corresponde).
      # [EN] ... a single 9 -> result is 0 (N/A).
      else return(0)
    }
    # Prioridad 3 (por defecto): el resultado es 2 (No).
    # [EN] Priority 3 (default): result is 2 (No).
    return(2)
  }

  stop("La función solo está preparada para 2 o 3 variables desagregadas")
}

# Ingresos no laborales (montos): recibe el vector con los montos de los
# sub-componentes de una fila y el valor de la variable control del hogar.
# [EN] Non-labor incomes (amounts): takes one row's sub-component amounts
#      plus the household control variable value. Negative INDEC codes:
#      -7 = not applicable, -8 = no income this month, -9 = DK/no answer.
.bridge_reconstruye_ingreso <- function(valores, valor_control) {

  # Prioridad absoluta: ingresos positivos -> suma de los no negativos.
  # [EN] Absolute priority: any positive amount -> sum of non-negative values.
  if (any(valores > 0, na.rm = TRUE)) {
    return(sum(valores[valores >= 0], na.rm = TRUE))
  }

  # Prioridad 1: si todas las variables independientes son 0, se imputa 0.
  # [EN] Priority 1: all sub-components equal 0 -> impute 0.
  if (all(valores == 0, na.rm = TRUE)) {
    return(0)
  }

  # Prioridad 2: control por estrategia del hogar. Si el hogar contestó
  # [2 == No] a la fuente de ingreso correspondiente, se imputa -7.
  # [EN] Priority 2: household control. If the household answered [2 == No]
  #      to the corresponding income source, impute -7.
  if (!is.na(valor_control) && valor_control == 2) {
    return(-7)
  }

  # Prioridad 3: incertidumbre. Si hay un -9 (Ns/Nr), el total es
  # imposible de determinar.
  # [EN] Priority 3: uncertainty. Any -9 -> the total cannot be determined.
  if (any(valores == -9)) return(-9)

  # Prioridad 4: ingreso potencial. Si no hay -9 pero sí un -8 (no tuvo
  # ingresos este mes), se conserva esa información.
  # [EN] Priority 4: potential income. No -9 but a -8 present -> keep that
  #      information (richer than -7 or 0).
  if (any(valores == -8)) return(-8)

  # Prioridad 5: no aplicabilidad. Si solo quedan -7, la categoría completa
  # no aplica para la persona.
  # [EN] Priority 5: non-applicability. Only -7s remain -> the whole category
  #      does not apply to the person.
  if (all(valores == -7)) return(-7)

  # Prioridad 6 (por defecto): cero explícito.
  # [EN] Priority 6 (default): explicit zero.
  return(0)
}


# ------------------------------------------------------------------------------
# Construcción del join hogar + individual (modo salida = "join")
# [EN] Household + individual join construction ("join" output mode)
# ------------------------------------------------------------------------------
# Replica el join del pipeline EPH-Observatorio (script/comun/01.une_bases.R):
# full_join por CODUSU + NRO_HOGAR conservando la versión individual de las
# columnas compartidas, más los hogares sin individuos encuestados (columnas
# individuales vacías) y el arreglo REALIZADA vacía -> 0.
# [EN] Replicates the EPH-Observatorio pipeline join (01.une_bases.R):
#      full_join by CODUSU + NRO_HOGAR keeping the individual-side version of
#      shared columns, plus households without surveyed individuals (empty
#      individual columns) and the fix empty REALIZADA -> 0.
.bridge_construye_join <- function(base_hogar, base_indiv, idx_hogar) {
  cols_hogar_extra <- setdiff(names(base_hogar), names(base_indiv))

  union_bases <- cbind(
    base_indiv,
    base_hogar[idx_hogar, cols_hogar_extra, drop = FALSE],
    stringsAsFactors = FALSE
  )

  # Hogares sin ningún individuo en la base individual
  # [EN] Households with no individual in the individual base
  sin_indiv <- setdiff(seq_len(nrow(base_hogar)),
                       idx_hogar[!is.na(idx_hogar)])
  if (length(sin_indiv) > 0L) {
    bloque_indiv <- base_indiv[rep(NA_integer_, length(sin_indiv)), ,
                               drop = FALSE]
    bloque_indiv$CODUSU    <- base_hogar$CODUSU[sin_indiv]
    bloque_indiv$NRO_HOGAR <- base_hogar$NRO_HOGAR[sin_indiv]
    bloque <- cbind(
      bloque_indiv,
      base_hogar[sin_indiv, cols_hogar_extra, drop = FALSE],
      stringsAsFactors = FALSE
    )
    union_bases <- rbind(union_bases, bloque)
  }

  # Arreglo del pipeline: REALIZADA sin dato -> 0
  # [EN] Pipeline fix: missing REALIZADA -> 0
  if ("REALIZADA" %in% names(union_bases)) {
    vacia <- is.na(union_bases$REALIZADA) | union_bases$REALIZADA == ""
    union_bases$REALIZADA[vacia] <- "0"
  }

  rownames(union_bases) <- NULL
  union_bases
}


# ------------------------------------------------------------------------------
# Auxiliares de entrada/salida
# [EN] Input/output helpers
# ------------------------------------------------------------------------------

# Lee una base usuaria EPH con todas las columnas como texto, sin convertir
# nada: garantiza que las columnas no tocadas se reescriban idénticas (códigos
# con ceros a la izquierda, decimales con coma, etc.).
# [EN] Reads an EPH user base with every column as text, converting nothing:
#      guarantees that untouched columns are rewritten identically (codes
#      with leading zeros, decimal commas, etc.).
.bridge_lee_base <- function(ruta) {
  base <- utils::read.table(
    ruta,
    sep              = ";",
    header           = TRUE,
    fill             = TRUE,
    colClasses       = "character",
    na.strings       = character(0),
    quote            = "\"",
    comment.char     = "",
    stringsAsFactors = FALSE
  )
  claves <- c("CODUSU", "NRO_HOGAR", "ANO4", "TRIMESTRE")
  if (!all(claves %in% names(base))) {
    stop("el archivo ", basename(ruta), " no parece una base usuaria EPH: ",
         "faltan las columnas ",
         paste(setdiff(claves, names(base)), collapse = ", "), ".")
  }
  base
}

# Extrae el período (ANO4 + TRIMESTRE) y verifica que la base tenga uno solo.
# [EN] Extracts the period (ANO4 + TRIMESTRE) and checks the base has exactly
#      one period.
.bridge_periodo <- function(base, nombre_archivo) {
  anios <- unique(trimws(base$ANO4))
  trims <- unique(trimws(base$TRIMESTRE))
  anios <- anios[anios != ""]
  trims <- trims[trims != ""]
  if (length(anios) != 1L || length(trims) != 1L) {
    stop("el archivo ", nombre_archivo, " contiene más de un período ",
         "(ANO4: ", paste(anios, collapse = "/"),
         "; TRIMESTRE: ", paste(trims, collapse = "/"),
         "). Cada base debe corresponder a un único trimestre.")
  }
  c(anio = anios, trimestre = trims,
    etiqueta = paste0(anios, "-T", trims))
}

# Convierte texto INDEC a numérico (decimales con coma; vacío -> NA).
# [EN] Converts INDEC text to numeric (decimal comma; empty -> NA).
.bridge_a_numerico <- function(x) {
  x <- trimws(x)
  x[x == ""] <- NA_character_
  suppressWarnings(as.numeric(sub(",", ".", x, fixed = TRUE)))
}

# Re-tipa una base leída como texto, columna por columna, con la misma
# inferencia de tipos que usaría read.table (numéricas con coma decimal,
# vacíos -> NA; las columnas de texto conservan sus "" como read.table, y el
# texto literal "NA" pasa a missing — algunas bases INDEC, p.ej. 2024-T4, usan
# NA como marcador de dato faltante).
# [EN] Re-types a text-read base, column by column, with the same type
#      inference read.table would apply (decimal-comma numerics, empty -> NA;
#      text columns keep "" as read.table does, and the literal text "NA"
#      becomes missing — some INDEC bases, e.g. 2024-Q4, use NA as their
#      missing-data marker).
.bridge_tipa <- function(base) {
  base[] <- lapply(base, function(col) {
    if (!is.character(col)) return(col)
    col_na <- col
    col_na[col_na == ""] <- NA_character_
    conv <- utils::type.convert(col_na, as.is = TRUE, dec = ",",
                                na.strings = "NA")
    if (is.character(conv)) {
      col[col == "NA"] <- NA_character_   # paridad read.table (na.strings)
      col
    } else {
      conv
    }
  })
  base
}

# Detecta qué columnas del archivo original vienen entre comillas, para
# reescribirlas con el mismo estilo. Devuelve los nombres de esas columnas.
# [EN] Detects which columns of the original file come quoted, so they can be
#      rewritten in the same style. Returns those column names.
.bridge_detecta_comillas <- function(ruta, columnas, max_filas = 50000L) {
  lineas <- readLines(ruta, warn = FALSE, n = max_filas + 1L)
  if (length(lineas) < 2L) return(character(0))
  lineas <- lineas[-1L]                       # sin el encabezado
  # Centinela al final para no perder campos vacíos al final de la línea
  # [EN] Trailing sentinel so end-of-line empty fields are not dropped
  trozos <- strsplit(paste0(lineas, ";_"), ";", fixed = TRUE)
  alineadas <- lengths(trozos) == length(columnas) + 1L
  if (!any(alineadas)) return(character(0))
  m <- matrix(unlist(trozos[alineadas]), nrow = length(columnas) + 1L)
  con_comilla <- startsWith(as.vector(m), "\"")
  dim(con_comilla) <- dim(m)
  columnas[rowSums(con_comilla)[seq_along(columnas)] > 0L]
}

# Escribe la base con el mismo formato que los .txt usuarios de INDEC.
# [EN] Writes the base with the same format as the INDEC user .txt files.
.bridge_escribe_base <- function(base, ruta, columnas_comilla) {
  idx_comilla <- which(names(base) %in% columnas_comilla)
  if (length(idx_comilla) == 0L) idx_comilla <- FALSE
  utils::write.table(
    base, ruta,
    sep       = ";",
    dec       = ",",
    na        = "",
    row.names = FALSE,
    quote     = idx_comilla,
    qmethod   = "double"
  )
}

# Verifica que el destino no pise un archivo de entrada ni uno existente.
# [EN] Checks that the destination clobbers neither an input file nor an
#      existing output (unless sobrescribir = TRUE).
.bridge_chequea_destino <- function(ruta_salida, rutas_entrada, sobrescribir) {
  destino_norm <- suppressWarnings(normalizePath(ruta_salida, mustWork = FALSE))
  if (destino_norm %in% normalizePath(rutas_entrada)) {
    stop("la ruta de salida coincide con la de entrada (", ruta_salida,
         "): se pisaría la base original. Cambie 'dir_salida', ",
         "'nombres_salida' o 'sufijo'.")
  }
  if (file.exists(ruta_salida) && !sobrescribir) {
    stop("el archivo de salida ya existe: ", ruta_salida,
         ". Use sobrescribir = TRUE para reemplazarlo.")
  }
  invisible(TRUE)
}

# Arma la ruta de salida de un archivo: nombre explícito del usuario o nombre
# original + sufijo, en dir_salida o en la carpeta del original.
# [EN] Builds an output path: explicit user-supplied name, or original name +
#      suffix, in dir_salida or in the original file's folder.
.bridge_ruta_salida <- function(ruta_entrada, dir_salida, nombre, sufijo) {
  if (is.na(nombre)) {
    nombre <- paste0(sub("\\.[^.]*$", "", basename(ruta_entrada)),
                     sufijo, ".txt")
  }
  destino <- if (is.null(dir_salida)) dirname(ruta_entrada) else dir_salida
  if (!dir.exists(destino)) dir.create(destino, recursive = TRUE)
  file.path(destino, nombre)
}

# Normaliza nombres_salida según el modo de salida.
# - "separadas": lista de length n con c(hogar = ..., individual = ...).
# - "join": lista de length n con un nombre (o NA) por par.
# [EN] Normalizes nombres_salida per output mode: "separadas" -> list of
#      c(hogar =, individual =) per pair; "join" -> one name (or NA) per pair.
.bridge_normaliza_nombres <- function(nombres_salida, n_pares, salida) {
  if (salida == "join") {
    if (is.null(nombres_salida)) {
      return(rep(list(NA_character_), n_pares))
    }
    nombres_salida <- unlist(nombres_salida, use.names = FALSE)
    if (!is.character(nombres_salida) || length(nombres_salida) != n_pares) {
      stop("Con salida = 'join', 'nombres_salida' debe tener un nombre de ",
           "archivo por par.", call. = FALSE)
    }
    return(as.list(nombres_salida))
  }

  vacio <- c(hogar = NA_character_, individual = NA_character_)
  if (is.null(nombres_salida)) {
    return(rep(list(vacio), n_pares))
  }
  if (is.character(nombres_salida) && length(nombres_salida) == 2L) {
    nombres_salida <- list(nombres_salida)
  }
  if (!is.list(nombres_salida) || length(nombres_salida) != n_pares) {
    stop("'nombres_salida' debe ser un vector c(hogar = ..., individual = ...) ",
         "para un par, o una lista con un vector de esos por par.",
         call. = FALSE)
  }
  lapply(nombres_salida, function(x) {
    if (!is.character(x) || length(x) != 2L) {
      stop("Cada elemento de 'nombres_salida' debe ser un vector de 2 nombres ",
           "(hogar e individual).", call. = FALSE)
    }
    if (is.null(names(x)) || !all(c("hogar", "individual") %in% names(x))) {
      names(x) <- c("hogar", "individual")
    }
    x[c("hogar", "individual")]
  })
}

# Modo carpeta: detecta pares usu_hogar_tNAA.txt + usu_individual_tNAA.txt.
# Insensible a mayúsculas/minúsculas (INDEC publica p.ej. usu_hogar_T125.txt).
# [EN] Folder mode: detects usu_hogar_tNAA.txt + usu_individual_tNAA.txt
#      pairs. Case-insensitive (INDEC publishes e.g. usu_hogar_T125.txt).
.bridge_detecta_pares <- function(carpeta, verbose) {
  archivos <- list.files(carpeta,
                         pattern = "^usu_(hogar|individual)_t[1-4][0-9]{2}\\.txt$",
                         ignore.case = TRUE, full.names = TRUE)
  if (length(archivos) == 0L) {
    stop("En la carpeta ", carpeta, " no se encontraron bases usuarias EPH ",
         "(patrón usu_hogar_TNAA.txt / usu_individual_TNAA.txt, mayúsculas o ",
         "minúsculas).", call. = FALSE)
  }
  nombre <- tolower(basename(archivos))
  token  <- sub("^usu_(hogar|individual)_(t[1-4][0-9]{2})\\.txt$", "\\2", nombre)
  tipo   <- ifelse(grepl("^usu_hogar", nombre), "hogar", "individual")

  tokens_h <- token[tipo == "hogar"]
  tokens_i <- token[tipo == "individual"]
  comunes  <- intersect(tokens_h, tokens_i)
  sueltos  <- setdiff(union(tokens_h, tokens_i), comunes)
  if (length(sueltos) > 0L) {
    message("Aviso: se ignoran trimestres sin par completo hogar+individual: ",
            paste(sueltos, collapse = ", "))
  }
  if (length(comunes) == 0L) {
    stop("En la carpeta ", carpeta, " no hay ningún par completo ",
         "hogar + individual del mismo trimestre.", call. = FALSE)
  }
  # Orden cronológico: año (2 dígitos) y luego trimestre
  # [EN] Chronological order: 2-digit year, then quarter
  orden <- order(as.integer(substr(comunes, 3, 4)),
                 as.integer(substr(comunes, 2, 2)))
  comunes <- comunes[orden]
  if (verbose) {
    message("Carpeta ", carpeta, ": ", length(comunes),
            " par(es) detectado(s): ", paste(comunes, collapse = ", "))
  }
  list(
    hogar      = archivos[match(paste0("hogar", comunes),
                                paste0(tipo, token))],
    individual = archivos[match(paste0("individual", comunes),
                                paste0(tipo, token))]
  )
}
