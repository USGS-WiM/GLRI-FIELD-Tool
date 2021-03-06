.onAttach <- function(libname, pkgname) {
  packageStartupMessage("Although this software program has been used by the U.S. Geological Survey (USGS), no warranty, expressed or implied, is made by the USGS or the U.S. Government as to the accuracy and functioning of the program and related program material nor shall the fact of distribution constitute any such warranty, and no responsibility is assumed by the USGS in connection therewith.")
}

#' Start the CyAN app
#'
#' Launch the CyAN app in a browser
#'
#' @import shinydashboard
#' @import shiny
#' @import shinyFiles
#' @import leaflet
#' @import htmltools
#' @import dplyr
#' @import fs
#'
#' @export
#'

run_CyAN <- function() {

  app_dir <- system.file("shiny", "cyan-app", package = "CyAN")
  if(app_dir == "") {
    stop("Couldn't find app directory, try reinstalling the package")
  }

  shiny::runApp(app_dir, launch.browser = TRUE)

}

