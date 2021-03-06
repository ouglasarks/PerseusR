# helper variable that maps between R and perseus types

.typeMap <- function(readPerseus = FALSE, writePerseus = FALSE,
                    additionalMatrices = FALSE){
  if (additionalMatrices){
    if (readPerseus){
      return(list(Perseus = c('N', 'E', 'C', 'T', 'M'),
                  R = c('numeric', 'character',
                        'factor', 'character',
                        'character')))
    } else if (writePerseus){
      return(list(Perseus = c('N', 'C', 'T', 'M'),
                  R = c('numeric', 'factor',
                        'character', 'character')))
    }
  } else {
    return(list(Perseus = c('N', 'E', 'C', 'T', 'M'),
                R = c('numeric', 'numeric',
                      'factor', 'character',
                      'character')))
  }
}

#' @importFrom plyr mapvalues
map_perseus_types <- function(typeAnnotation, typeMap) {
  plyr::mapvalues(typeAnnotation,
                  from = typeMap$Perseus,
                  to = typeMap$R,
                  warn_missing = FALSE)
}

#' Infer Perseus type annotation row from DataFrame column classes
#'
#' @param df The data.frame
#' @param typeMap A list with elements 'Perseus' and 'R'. The ordering determines the mapping
#' @importFrom plyr laply
#' @return A vector with perseus type annotations
#' @seealso Based on \code{\link{mapvalues}}
infer_perseus_annotation_types <- function(df, typeMap) {
  colClasses <- plyr::laply(df, class)
  if (length(colClasses) == 0) return(colClasses)
  plyr::mapvalues(colClasses,
                  from = typeMap$R,
                  to = typeMap$Perseus,
                  warn_missing = FALSE)
}

#' Create annotation rows
#'
#' Create the annotation rows data.frame from the list
#' of comment rows parsed from the input file and the main columns indicator
#' @param commentRows list of comment rows
#' @param isMain logical array indicating all main columns
#' @seealso used by \code{\link{read.perseus}}
create_annotRows <- function(commentRows, isMain) {
  annotRows <- list()
  for (name in names(commentRows)) {
    if (startsWith(name, 'C:')) {
      annotRows[[substring(name, 3)]] <- factor(commentRows[[name]][isMain])
    }
    else if (startsWith(name, 'N:')) {
      annotRows[[substring(name, 3)]] <- as.numeric(commentRows[[name]][isMain])
    }
    else {
      warning("Found unrecognized annotation row: ", name)
    }
  }
  return(as.data.frame(annotRows))
}


#' Read Perseus matrix files
#'
#' Read the custom Perseus matrix file format *.txt into R.
#' @note Limitations to column names in R still apply. Column names valid
#' in Perseus, such as 'Column 1' will be changed to 'Column.1'
#' @export
#'
#' @family read.perseus
#' @param con A \code{\link{connection}} object or the path to input file
#' @param check Logical indicating whether to check for the validity of the exported object (slightly slower)
#' @param additionalMatrices Logical indication whether to write out quality and imputation matrices in perseus format
#' @return DataFrame with additional 'annotationRows' attribute
#' @seealso \code{\link{write.perseus}}
#' @importFrom stringr str_split
#' @rdname read.perseus
#' @aliases read.perseus
#' @note If the provided connection \code{con} is a character string, it will assumed
#' to be a file path. A \code{\link{connection}} which is not seekable (see \code{\link{isSeekable}})
#' will be written to a temporary file. Any connection will be closed when \code{read.perseus} exits.
#' \code{read.perseus.as.list}, \code{read.perseus.as.matrixData} and \code{read.perseus.as.ExpressionSet} are also available depending on the class desired as an output
#' @examples
#' tmp <- tempfile(fileext = ".txt")
#' write('Column_1\tColumn_2\tColumn_3
#' #!{Description}\t\t
#' #!{Type}E\tE\tE
#' -1.860574\t-0.3910594\t0.2870352
#' NaN\t-0.4742951\t0.849998', file=tmp)
#' mdata <- read.perseus(tmp)
#'
read.perseus.default <- function(con, check = TRUE, additionalMatrices = FALSE) {
  if (is.character(con)) {
    con <- file(con, open = 'r')
  } else if (!isSeekable(con)) {
    fileCon <- file()
    writeLines(readLines(con), fileCon)
    close(con)
    con <- fileCon
  }
  invisible(strsplit(readLines(con, n = 1), '\t')[[1]])
  commentRows <- list()
  while (startsWith(oneLine <- readLines(con, n = 1), '#!')) {
    name <- stringr::str_split(substring(oneLine, 4), '[}]')[[1]][1]
    rowStr <- substring(oneLine, nchar(name) + 5)
    rowValues <- stringr::str_split(rowStr, '\t')[[1]]
    commentRows[[name]] <- rowValues
  }
  types <- commentRows$Type
  descr <- commentRows$Description
  commentRows[c('Type', 'Description')] <- NULL
  if (additionalMatrices){
    colClasses <- map_perseus_types(types, .typeMap(readPerseus = TRUE, additionalMatrices = TRUE))
  } else {
    colClasses <- map_perseus_types(types, .typeMap(readPerseus = TRUE))
  }
  seek(con, 0)
  df <- utils::read.table(con, header = TRUE,
                          sep = '\t', comment.char = '#',
                          colClasses = colClasses, fill = TRUE,
                          quote = "")
  close(con)
  isMain <- types == 'E'
  main <- df[isMain]
  imputeData <- matrix('False', ncol = ncol(main), nrow = nrow(main))
  qualityData <- matrix(0, ncol = ncol(main), nrow = nrow(main))
  if (additionalMatrices) {
    for (i in 1:nrow(main)){
      for (j in 1:ncol(main)){
        mainDataList <- unlist(strsplit(main[i, j], ';'))
        if (length(mainDataList) == 1){
        } else {
          main[i, j] <- mainDataList[1]
          imputeData[i, j] <- mainDataList[2]
          qualityData[i, j] <- mainDataList[3]
        }
      }
    }
  }
  imputeData <- as.data.frame(imputeData)
  colnames(imputeData) <- colnames(main)
  qualityData <- as.data.frame(qualityData)
  colnames(qualityData) <- colnames(main)
  main <- as.data.frame(sapply(main, as.numeric))
  annotCols <- df[!isMain]
  annotRows <- create_annotRows(commentRows, isMain)
  if (is.null(descr)) {
    descr <- character(0)
  }

  if ('Name' %in% colnames(df)) {
    rowNames <- make.names(df$Name, unique = T)
    colNames <- colnames(main)
    rownames(main) <- rowNames
    rownames(annotCols) <- rowNames
    rownames(annotRows) <- colNames
  }
  perseus.list <- list(main = main,
                      annotCols = annotCols,
                      annotRows = annotRows,
                      description = descr,
                      imputeData = imputeData,
                      qualityData = qualityData)
  if (check) MatrixDataCheck(perseus.list)
  return(perseus.list)
}

#' @describeIn read.perseus Difference between the mean and the median
#' @family read.perseus
#' @export
read.perseus.as.list <- function(con, check = TRUE) {
  return(read.perseus.default(con, check = check))
}


#' @describeIn read.perseus Difference between the mean and the median
#' @family read.perseus
#' @export
read.perseus.as.matrixData <- function(con, check = TRUE, additionalMatrices = FALSE) {
  perseus.list <- read.perseus.default(con, check = check, additionalMatrices = additionalMatrices)
  return(matrixData(main = perseus.list$main,
                    annotCols = perseus.list$annotCols,
                    annotRows = perseus.list$annotRows,
                    description = perseus.list$descr,
                    imputeData = perseus.list$imputeData,
                    qualityData = perseus.list$qualityData))
}

#' @describeIn read.perseus Difference between the mean and the median
#' @family read.perseus
#' @export
read.perseus.as.ExpressionSet <- function(con, check = TRUE) {

  if (!requireNamespace("Biobase", quietly = TRUE)) {
    stop('This function requires the Biobase package, please install it in the bioconductor repository')
  }

  perseus.list <- read.perseus.default(con, check = check)

  eSet <- Biobase::ExpressionSet(
    assayData = data.matrix(perseus.list$main),
    phenoData = methods::new('AnnotatedDataFrame',
                             perseus.list$annotRows),
    annotation = perseus.list$descr,
    featureData = methods::new('AnnotatedDataFrame',
                               perseus.list$annotCols),
    imputeData = perseus.list$imputeData,
    qualityData = perseus.list$qualityData)

  return(eSet)
}

#' @export
read.perseus <- read.perseus.as.matrixData

#' Write data to a perseus text file or connection
#'
#' @title write.perseus: function to generate a perseus-readable text document
#'
#' @param object an expressionSet, matrixData, list or table-like object.
#'
#' @return writes to disk a perseus-interpretable text representation of an R object
#' @rdname write.perseus
#' @examples
#' df <- matrixData(
#' main=data.frame(a=1:3, b=6:8),
#' annotCols=data.frame(b=c('a','b','c')),
#' annotRows=data.frame(x=factor(c('1','1'))),
#' description=c('a','a','b'))
#' con <- textConnection('df1', 'w')
#' write.perseus(df, con)
#' close(con)
#' @export write.perseus
write.perseus <- function(object = NULL, con = NULL, ...) {
  if (is.character(object)) {
    stop("First argument should be the object to write to file.")
  }
  UseMethod("write.perseus", object)
}

#' Write Data to Perseus matrix format
#'
#' Write Data to file in the custom Perseus matrix file format.
#'
#' @param main a data frame containing
#' @param annotCols a df containing columns containing metadata (about the rows)
#' @param annotRows a df containing columns containing metadata (about the columns)
#' @param descr a character vector that describes the columns in main and in annotCols (in that order)
#' @param imputeData a df containing imputations -- True or False of main data frame
#' @param qualityData a df containing quality values of main data frame
#' @param con A \code{\link{connection}} object or the path to output file
#' @param ... additional arguments passed to other functions
#' @seealso \code{\link{read.perseus}} \code{\link{matrixData}}
#' @inheritParams write.perseus
#'
#' @rdname write.perseus
#' @method write.perseus default
#'
#' @export
write.perseus.default <- function(object = NULL, con = NULL, main, annotCols = NULL,
                          annotRows = NULL, descr = NULL, imputeData = NULL,
                          qualityData = NULL, ...) {
  stopifnot(is.data.frame(main) | is.data.frame(annotCols))

  if (is.null(annotCols)) assign('annotCols', value = data.frame())
  if ((!plyr::empty(imputeData)) || (!plyr::empty(qualityData))) {
    imputeVector <-as.vector(t(imputeData))
    qualityVector <-as.vector(t(qualityData))
    if ((length(unique(imputeVector)) != 1) || (length(unique(qualityVector)) != 1)) {
      importAdditionalMatrix = TRUE
    } else {
      importAdditionalMatrix = FALSE
    }
    if (importAdditionalMatrix) {
      for (i in 1:nrow(main)){
        for (j in 1:ncol(main)){
          mergeMain <- unlist(list(main[i, j], as.character(imputeData[i, j]), qualityData[i, j]))
          main[i, j] <- paste(mergeMain, collapse = ';')
        }
      }
    }
  }
  columns <- c(names(main), names(annotCols))
  df <- main
  closeAtEnd <- FALSE
  if (is.character(con)) {
    con <- file(con, open = 'w')
    closeAtEnd <- TRUE
  }
  writeLines(paste0(columns, collapse = '\t'), con)
  if (length(descr) != 0) {
    descr[1] <- paste0('#!{Description}', descr[1])
    writeLines(paste0(descr, collapse = '\t'), con)
  }
  if ((!plyr::empty(imputeData)) || (!plyr::empty(qualityData))) {
    type <- c(rep('E', ncol(main)),
              infer_perseus_annotation_types(annotCols, .typeMap(writePerseus = TRUE, additionalMatrices = TRUE)))
  } else {
    type <- c(rep('E', ncol(main)),
              infer_perseus_annotation_types(annotCols, .typeMap(writePerseus = TRUE)))
  }
  type[1] <- paste0('#!{Type}', type[1])
  writeLines(paste0(type, collapse = '\t'), con)
  for (name in names(annotRows)) {
    values <- annotRows[[name]]
    line <- paste0(c(as.character(values), rep('', ncol(annotCols))), collapse = '\t')
    if (is.numeric(values)) {
      writeLines(sprintf('#!{N:%s}%s', name, line), con)
    }
    else {
      writeLines(sprintf('#!{C:%s}%s', name, line), con)
    }
  }
  if (nrow(annotCols) != 0) {
    if (nrow(main) == 0) {
      df <- annotCols
    }
    else {
      df <- cbind(main, annotCols)
    }
  }
  utils::write.table(df, con, sep = '\t', quote = FALSE,
                     row.names = FALSE, col.names = FALSE,
                     na = 'NaN')
  if (closeAtEnd) close(con)
  return()
}

#' @return \code{NULL}
#'
#' @inheritParams write.perseus.default
#'
#' @export
#' @method write.perseus matrixData
#' @rdname write.perseus
write.perseus.matrixData <- function(object, con , ...) {
  descr <- description(object)
  annotRows <- as.list(annotRows(object))
  main <- main(object)
  annotCols <- annotCols(object)
  imputeData <- imputeData(object)
  qualityData <- qualityData(object)

  (function(...){
    write.perseus.default(main = main, annotCols = annotCols,
                        annotRows = annotRows, descr = descr,
                        imputeData = imputeData, qualityData = qualityData,
                        con = con)})(...)
}


#' @return \code{NULL}
#'
#' @inheritParams write.perseus.default
#'
#' @rdname write.perseus
#' @method write.perseus list
#'
#' @export
write.perseus.list <- function(object, con, ...) {
  stopifnot(any(c('main', 'annotCols') %in% names(object)))
  object$con <- con

  do.call(write.perseus.default, c(list(...), object))
}


#' @return \code{NULL}
#'
#' @inheritParams write.perseus.default
#'
#' @rdname write.perseus
#' @method write.perseus data.frame
#'
#' @export
write.perseus.data.frame <- function(object, con, annotCols = NULL, ...) {
  stopifnot(is.data.frame(object))
  numeric_cols <- plyr::laply(object, is.numeric)
  main <- subset.data.frame(object, select = numeric_cols, subset = T)

  if (is.null(annotCols)) {
    annotCols <- subset.data.frame(object, select = !numeric_cols, subset = T)
  }

  (function(...){
    write.perseus.default(main = main,
                          annotCols = annotCols,
                          con = con, ...)})(...)
}


#' @return \code{NULL}
#'
#' @inheritParams write.perseus.default
#'
#' @rdname write.perseus
#' @method write.perseus matrix
#'
#' @export
write.perseus.matrix <- function(object, con, annotCols = NULL, ...) {

  if (is.null(annotCols) & !is.null(rownames(object))) {
    annotCols <- as.data.frame(rownames(object))
    colnames(annotCols) <- 'Names'
  }

  (function(...){
    write.perseus.default(main = as.data.frame(object),
                          annotCols = annotCols,
                          con = con, ...)})(...)
}


#' @return \code{NULL}
#'
#' @inheritParams write.perseus.default
#'
#' @rdname write.perseus
#' @method write.perseus ExpressionSet
#'
#' @export
write.perseus.ExpressionSet <- function(object, con, ...) {

  mainDF <- data.frame(Biobase::exprs(object))
  annotationRows <- methods::as(object@phenoData, 'data.frame')
  descriptions <- Biobase::annotation(object)
  annotationCols <- methods::as(object@featureData, 'data.frame')


  (function(...){
    write.perseus.default(main = mainDF, annotCols = annotationCols,
                        annotRows = annotationRows, descr = descriptions,
                        con = con)})(...)
}

