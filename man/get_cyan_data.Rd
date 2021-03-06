% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/database.R
\name{get_cyan_data}
\alias{get_cyan_data}
\title{Get data from CyAN}
\usage{
get_cyan_data(cyan_connection, collect = FALSE, north_latitude = NULL,
  south_latitude = NULL, west_longitude = NULL,
  east_longitude = NULL, years = NULL, parameters = NULL,
  minimum_tier = NULL, states = NULL)
}
\arguments{
\item{cyan_connection}{a CyAN database connection from \code{connect_cyan}}

\item{collect}{a logical indicating whether the query will be pulled into
a local tibble using dbplyr::collect. If you are planning on doing further
selection or filtering using dplyr, you may want not want to collect until
you're ready}

\item{north_latitude, south_latitude}{numerics indicating the northern most
and sothern most latitude that will be included in the query. Latitude
should be given as a positive number of degrees north of the equator.}

\item{west_longitude, east_longitude}{numerics indicating the western most
and eastern most latitude that will be included in the query. Longitude
should be given as a negative number of decimal degrees west of the prime
meridian.}

\item{years}{numeric vector of years that will be included in the query}

\item{parameters}{a character vector of parameter names that will be
returned in the query}

\item{minimum_tier}{a number between 1.0 and 4.0 indicating the minimum
data tier that will be returned in the query}

\item{states}{a character vector of the postal codes for the states to be
included in the query. Usually, this would not be used if querying by
latitude and longitude.}
}
\value{
if collect is FALSE, the query will be generated, but not collected.
See the documentation on \code{collect()} for details. Otherwise, if collect
is TRUE, the query will be pulled into memory and returned as a tibble.
}
\description{
Basic data query from the CyAN database based on a number of parameters,
used to drive the data download from the map screen of the shiny app. Can also
be used with the plotting functions
}
\examples{
#Connect to the example database bundled with CyAN
path <- system.file("extdata", "example.db", package = "CyAN")
db_connection <- connect_cyan(path)

#Get all of the chlorophyll and chlorophyll-a data (parameter id P0051 & P0054)
#or the state of Kansas in the year 2016
ks_chl_2016 <- get_cyan_data(db_connection,
                             years = 2016,
                             parameters = c("P0051", "P0054"),
                             states = "KS")

#Get chlorophyll-a data within a latitude longitude bounding box. If you
#need to reference the parameter table to find parameter codes, you can use
#generate_parameter_index()
chla_2017 <- get_cyan_data(db_connection,
                           north_latitude = 37.818, south_latitude = 37.714,
                           west_longitude = -98.028, east_longitude = -97.735,
                           years = 2017:2018,
                           parameters = "P0051")

}
