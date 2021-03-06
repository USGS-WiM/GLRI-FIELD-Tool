library(shinydashboard)
library(shiny)
library(shinyFiles)
library(leaflet)
library(htmltools)
library(dplyr)
library(fs)
library(shinyjqui)
library(shinyjs)

options(shiny.maxRequestSize=2000*1024^2)

load(system.file("shiny", "cyan-app", "database", "locationIndex.RData", package = "CyAN"))

null_if_blank_as_num <- function(x) {
  if(x == "") {
    return(NULL)
  } else {
    return(as.numeric(x))
  }
}

ui <- dashboardPage(

  dashboardHeader(title = "GLRI Field Tool"),

  dashboardSidebar(
    sidebarMenu(id = "sidebar",
      menuItem("Information", tabName = "help"),
      menuItem("Configure", tabName = "db_configuration"),
      menuItem("Map", tabName = "map_screen"),
      menuItem("Bivariate Plot", tabName = "bivariate_plot"),
      menuItem("Flags", tabName = "find_flagged"),
      conditionalPanel("input.sidebar == 'bivariate_plot'",
        uiOutput("bivariate_parameter_controls"),
        checkboxInput("biv_map_limit", label = "Limit to map bounds", value=TRUE),
        #Set this via epoch or data range.
        sliderInput("biv_years", label = "Years:", min = 1975, max = year(Sys.Date()),
                    value = c(1975, 2016), sep = ""),
        selectInput("biv_color", "Highlight", choices=c("Parameter 1 methods" = "METHOD_ID.1",
                                                       "Parameter 2 methods" = "METHOD_ID.2")),
        uiOutput("method_highlight_controls"),
        checkboxGroupInput("log_biv", "Log Scale", choices=c("x", "y")),
        column(12, downloadLink("download_bivariate", "Download bivariate data"))
      )
    )

  ),

  dashboardBody(
    tabItems(
      tabItem(tabName = "help",
        includeMarkdown("help.md")
      ),
      tabItem(tabName = "db_configuration",
        h3("Connect to database"),
        shinyFilesButton('db_file', label = "Database file", title = "CyAN Database", multiple = FALSE),
        checkboxInput("db_example_file", label = "Or load example data", value = FALSE)
      ),
      tabItem(tabName = "map_screen",
        div(class = "outer",
          tags$head(
            includeCSS("styles.css"),
            includeScript("gomap.js")
          ),
          leafletOutput("map", width = "100%", height = "100%"),
          #Gets rid of that annoying close on click issue by using jqui_draggable
          jqui_draggable(
            absolutePanel(id="controls", class="panel panel-default", fixed=TRUE,
                        draggable=FALSE, top=60, left="auto", right=20, bottom="auto",
                        width=330, height="auto",

                        helpText(" "),
                        radioButtons("parm_logic", "Parameters:", choices=c("At least one", "All of")),
                        helpText(" "),
                        uiOutput("filter_points_parameter"),
                        radioButtons("tiles", "View layer:", choices=c("NHD", "Streets"),
                                     selected="Streets", inline=TRUE),
                        actionButton("show_points", "Show points")

          ),
          options = list(cancel = ".selectize-control")),
          jqui_draggable(
            absolutePanel(id="querycontrols", class="panel panel-default", fixed=TRUE,
                          draggable=TRUE, top=60, left=20, right="auto", bottom="auto",
                          width=400, height="auto",
                          textInput("download_filename", "Output file name (no extension"),
                          checkboxInput("fill_bounds", "Fill bounds from map", value = TRUE),
                          fluidRow(
                            column(4),
                            column(4, uiOutput("n_lat_box")),
                            column(4)
                          ),
                          fluidRow(
                            column(1),
                            column(4, uiOutput("w_long_box")),
                            column(2),
                            column(4, uiOutput("e_long_box")),
                            column(1)
                          ),
                          fluidRow(
                            column(4),
                            column(4, uiOutput("s_lat_box")),
                            column(4)
                          ),
                          fluidRow(
                            column(1),
                            column(10,
                                   sliderInput("years", label = "Years:", min = 1975, max = year(Sys.Date()),
                                               value = c(1975, 2016), sep = ""),
                                   uiOutput("parameter_choices")
                            ),
                            column(1)
                          ),
                          fluidRow(
                            column(5, textInput("tier", "Tier:", value = "4.0")),
                            column(1),
                            column(5, uiOutput("state_choices"))
                          ),
                          fluidRow(
                            column(6, checkboxInput("add_GMT", "Add GMT datetime"),
                                   value = FALSE),
                            column(6, checkboxInput("add_solar_noon", "Add solar noon flag",
                                                    value = FALSE))
                          ),
                          fluidRow(
                            column(6, checkboxInput("add_trophic_status", "Add trophic status",
                                   value = FALSE)),
                            column(6, checkboxInput("add_who_thresholds", "Add WHO thresholds",
                                   value = FALSE))
                          ),
                          fluidRow(
                            column(6, checkboxInput("add_epa_rec", "Add EPA thresholds",
                                                    value = FALSE)),
                            column(6)
                          ),
                          downloadButton("download_data")

            ),
            options = list(cancel = ".selectize-control"))

        )
      ),
      tabItem(tabName = "bivariate_plot",
        box(
          plotOutput("bivariate_plot", brush = brushOpts(id = "zoom_brush", resetOnNew = FALSE),
                     height="700px"),
        width = 6),
        box(
          plotOutput("zoomed_bivariate_plot", brush = brushOpts(id = "flag_brush", resetOnNew = FALSE),
                     height = "700px")
        ),
        fluidRow(
          column(6),
          column(1, actionButton("flag_biv", "Apply flag")),
          column(1, actionButton("unflag_biv", "Remove flag")),
          column(1, textInput("initials", label = NULL, placeholder = "initials")),
          column(1, actionButton("refresh", "Refresh"))
        )
      ),
      tabItem(tabName = "find_flagged",
        box(
          uiOutput("select_flag_ui"),
          downloadButton("download_flagged", "Download flagged observations")
        )
      )
    )
  )


)
####################################################################################################
server <- function(input, output) {

  volumes <- c(Home = fs::path_home(), "R Installation" = R.home(), getVolumes()())
  shinyFileChoose(input, "db_file", filetypes = c("", "db"), roots = volumes)

  db_path <- reactive({
    if(input$db_example_file) {
      path <- system.file("extdata", "example.db", package = "CyAN")
      if(!file.exists(path)) {
        showNotification("Example data not found, try re-installing the package", duration = 10, type = "error")
        db_path <- data.frame()
      } else {
        db_path <- data.frame(datapath = path, stringsAsFactors = FALSE)
      }
    } else {
      db_path <- parseFilePaths(volumes, input$db_file)
    }
    return(db_path)
  })

  cyan_connection <- reactive({

    file <- db_path()
    if(nrow(file) == 0)
      return(NULL)

    db_path <- file$datapath
    print(db_path)
    cyan <- connect_cyan(db_path)
    showNotification("Connected!", type = "message", duration = 5)
    cyan
  })

  parameter_index <- reactive({

    if(is.null(cyan_connection()))
      return(NULL)
    parm_notification <- showNotification("Indexing parameters...", duration = NULL)
    parameters <- generate_parameter_index(cyan_connection(), has_data = TRUE)
    removeNotification(parm_notification)
    showNotification("Finished!", duration = 5)
    parameters

  })

  location_index <- reactive({
    if(is.null(cyan_connection()))
      return(data.frame(LOCATION_NAME = "N/A", LATITUDE = 0, LONGITUDE = 0, PARAMETER_ID = "P0001"))

    loc_notification <- showNotification("Indexing database locations...", duration = NULL)
    locations <- generate_location_index(cyan_connection())
    removeNotification(loc_notification)
    showNotification("Finished!", duration = 5)
    locations
  })
  #try to fix here first
  output$filter_points_parameter <- renderUI({

    if(is.null(cyan_connection()))
      return(NULL)

    choices <- parameter_index()$PARAMETER_ID
    names(choices) <- parameter_index()$SHORT_NAME
    #Added option = list(plugins = list('remove_button')) to make the list mutation options keyboard free.
    selectizeInput("parms_s", label = NULL, choices = choices, selected = NULL, multiple = TRUE, options = list(plugins = list('remove_button')))
  })

  output$map <- renderLeaflet({

    pts_init <- data.frame(LOCATION_NAME = "KSWSC", LATITUDE = 38.0, LONGITUDE = -95.0)

    leaflet() %>%
      addTiles(urlTemplate = "//{s}.tiles.mapbox.com/v3/jcheng.map-5ebohr46/{z}/{x}/{y}.png",
               attribution = 'Maps by <a href="http://www.mapbox.com/">Mapbox</a>') %>%
      addCircles(data = pts_init, layerId = "KSWSC") %>%
      clearShapes() %>%
      fitBounds(-141.855, 23.483, -57.48, 53.801)

  })

  zoomWindow <- reactive({
    if(is.null(input$map_bounds))
      return(c("", "", "", ""))
    bounds <- input$map_bounds
    zw <- as.character(c(bounds$north, bounds$east, bounds$south, bounds$west))
    zw
  })

  mapData <- reactive({

    input$show_points
    isolate({
      selected_parameters <- input$parms_s
      zoom <- as.numeric(zoomWindow())
      points <- location_index()
    })

    points <- location_index()

    if(!is.null(selected_parameters)) {
      if(input$parm_logic == "All of") {
        s <- lapply(selected_parameters, function(x, ind) {
          sts <- filter(ind, PARAMETER_ID == x) %>%
            select(-PARAMETER_ID)
        }, ind = points)
        mapData <- Reduce(intersect, s)
      } else {
        mapData <- filter(points, PARAMETER_ID %in% selected_parameters) %>%
          distinct()
      }
    } else {
      mapData <- select(points, LOCATION_NAME, LATITUDE, LONGITUDE) %>%
        distinct
    }

    if(!all(is.na(zoom))) {
      mapData <- filter(mapData,
                        LATITUDE >= zoom[3], LATITUDE <= zoom[1],
                        LONGITUDE <= zoom[2], LONGITUDE >= zoom[4])
    }

    mapData

  })
  #This is layer control
  observe({

    if(input$tiles=="NHD") {
      leafletProxy("map") %>% clearTiles() %>% addWMSTiles(
        "http://basemap.nationalmap.gov/arcgis/services/USGSHydroCached/MapServer/WMSServer?",
        layers = "0",
        options = WMSTileOptions(format = "image/bmp", transparent = FALSE),
        attribution = "")
    } else if(input$tiles=="Streets") {
      leafletProxy("map") %>% clearTiles() %>% addTiles(
        urlTemplate = "//{s}.tiles.mapbox.com/v3/jcheng.map-5ebohr46/{z}/{x}/{y}.png",
        attribution = 'Maps by <a href="http://www.mapbox.com/">Mapbox</a>')
    }

  })
  #This is render dots?
  observe({

    leafletProxy("map") %>% clearShapes() %>%
      addCircles(data=mapData(), popup = ~htmlEscape(LOCATION_NAME), color='orangered',
                 fillColor='orangered', fillOpacity=0.9, opacity=0.9, radius=15)
  })
  #This is carinal boxes?
  output$n_lat_box <- renderUI({

    if(input$fill_bounds) {
      v <- zoomWindow()[1]
    } else {
      v <- ""
    }
    textInput("n_lat", "North Latitude", value=v)

  })

  output$w_long_box <- renderUI({

    if(input$fill_bounds) {
      v <- zoomWindow()[4]
    } else {
      v <- ""
    }
    textInput("w_long", "West Longitude", value=v)

  })

  output$e_long_box <- renderUI({

    if(input$fill_bounds) {
      v <- zoomWindow()[2]
    } else {
      v <- ""
    }
    textInput("e_long", "East Longitude", value=v)

  })

  output$s_lat_box <- renderUI({

    if(input$fill_bounds) {
      v <- zoomWindow()[3]
    } else {
      v <- ""
    }
    textInput("s_lat", "South Latitude", value=v)

  })
  #This is left menu param select
  output$parameter_choices <- renderUI({

    if(is.null(parameter_index()))
      return(NULL)

    choices <- parameter_index()$PARAMETER_ID
    names(choices) <- parameter_index()$SHORT_NAME

    selectInput("parms", "Parameters:",  choices = choices, multiple = TRUE)

  })
  #This is state options?
  output$state_choices <- renderUI({

    states <- state.abb[!(state.abb %in% c("AK", "HI"))]
    states <- c("All", states)
    selectInput("state", "State:", choices = states,
                selectize = TRUE, multiple = TRUE, selected = "All")


  })
  #This is download manager
  output$download_data <- downloadHandler(
    filename = function() {
      paste0(input$download_filename, ".csv")
    },
    content = function(file) {

      n_lat <- null_if_blank_as_num(input$n_lat)
      s_lat <- null_if_blank_as_num(input$s_lat)
      e_long <- null_if_blank_as_num(input$e_long)
      w_long <- null_if_blank_as_num(input$w_long)
      years <- input$years[1]:input$years[2]
      parameters <- input$parms
      minimum_tier <- null_if_blank_as_num(input$tier)

      if("All" %in% input$states) {
        states <- NULL
      } else {
        states <- input$states[input$states != "All"]
      }

      download_notification <- showNotification("Preparing data...", duration = NULL)
      #This is left menu check boxes
      output <- get_cyan_data(cyan_connection = cyan_connection(),
                              collect = TRUE,
                              north_latitude = n_lat, south_latitude = s_lat,
                              east_longitude = e_long, west_longitude = w_long,
                              years = years,
                              parameters = parameters)

      if(input$add_GMT) {
        showNotification("Adding GMT...", id = download_notification, duration = NULL)
        output <- add_GMT_time(output)
      }

      if(input$add_solar_noon) {
        showNotification("Adding solar noon...", id = download_notification, duration = NULL)
        output <- add_solar_noon(output)
      }

      if(input$add_trophic_status) {
        showNotification("Adding trophic status...", id = download_notification, duration = NULL)
        output <- add_trophic_status(output)
      }

      if(input$add_who_thresholds) {
        showNotification("Adding WHO Thresholds...", id = download_notification, duration = NULL)
        output <- add_WHO_category(output)
      }

      if(input$add_epa_rec) {
        showNotification("Adding EPA Recreational Thresholds...", id = download_notification, duration = NULL)
        output <- add_EPA_recreational_threshold(output)
      }

      removeNotification(id = download_notification)

      write.csv(output, file, row.names = FALSE, na = "")

    }
  )

  output$bivariate_parameter_controls <- renderUI({

    if(is.null(parameter_index()))
      return(NULL)

    choices <- parameter_index()$PARAMETER_ID
    names(choices) <- parameter_index()$SHORT_NAME
    tagList(
      selectInput("biv_parm_1", "Parameter 1 (x-axis):", choices = c("None" = "None", choices)),
      selectInput("biv_parm_2", "Parameter 2 (y-axis):", choices = c("None" = "None", choices))
    )
  })

  output$method_highlight_controls <- renderUI({

    if(is.null(input$biv_parm_1))
      return(NULL)

    if(input$biv_parm_1 != "None" & input$biv_parm_2 != "None") {

      if(input$biv_color == "METHOD_ID.1") {
        methods <- bivariate_data()[,c("METHOD_ID.1", "WQP_METHOD_IDENTIFIER.1",
                                       "WQP_METHOD_CONTEXT.1", "WQP_METHOD_NAME.1")]
        methods <- unique(methods)
        method_choices <- methods$METHOD_ID.1
        names(method_choices) <- paste(methods$WQP_METHOD_CONTEXT.1, methods$WQP_METHOD_IDENTIFIER.1,
                                       methods$WQP_METHOD_NAME.1, sep = "/")
      } else {
        methods <- bivariate_data()[,c("METHOD_ID.2", "WQP_METHOD_IDENTIFIER.2",
                                       "WQP_METHOD_CONTEXT.2", "WQP_METHOD_NAME.2")]
        methods <- unique(methods)
        method_choices <- methods$METHOD_ID.2
        names(method_choices) <- paste(methods$WQP_METHOD_CONTEXT.2, methods$WQP_METHOD_IDENTIFIER.2,
                                       methods$WQP_METHOD_NAME.2, sep = "/")
      }
      methods <- unique(bivariate_data()[,input$biv_color])
      selectInput("method_highlight", "Methods", choices=c("None", method_choices),
                     multiple=TRUE, selected="None")
    }
  })

  bivariate_data <- reactive({

    if(is.null(input$biv_parm_1) || is.null(input$biv_parm_2))
      return(NULL)
    if("None" %in% c(input$biv_parm_1, input$biv_parm_2))
      return(NULL)

    if(input$biv_map_limit) {
      north_latitude <- null_if_blank_as_num(input$n_lat)
      south_latitude <- null_if_blank_as_num(input$s_lat)
      west_longitude <- null_if_blank_as_num(input$w_long)
      east_longitude <- null_if_blank_as_num(input$e_long)
    } else {
      north_latitude <- south_latitude <- east_longitude <- west_longitude <- NULL
    }

    data_notification <- showNotification("Getting data...", type = "message", duration = NULL)

    data <- get_bivariate(cyan_connection(), input$biv_parm_1, input$biv_parm_2,
                          north_latitude = north_latitude, south_latitude = south_latitude,
                          west_longitude = west_longitude, east_longitude = east_longitude,
                          years = input$biv_years[1]:input$biv_years[2])

    removeNotification(id = data_notification)

    data

  })

  bivariate_flagged <- reactive({

    input$refresh
    flagged <- find_flagged(cyan_connection(), "MANBIV")
    flagged

  })

  output$bivariate_plot <- renderPlot({

    if(is.null(bivariate_data()))
      return(NULL)

    log_1 <- "x" %in% input$log_biv
    log_2 <- "y" %in% input$log_biv
    method_highlight <- input$method_highlight
    flagged_results <- bivariate_flagged()

    if(nrow(bivariate_data()) == 0) {
      plot_notification <- showNotification("No data found", type = "error", duration = 10)
      return(NULL)
    }

    if(nrow(bivariate_data()) > 10000) {
      showNotification("Plotting first 10000 points, try narrowing down your search",
                                             type = "warning", duration = 10)
    }

    plot_notification <- showNotification("Plotting...", duration = NULL)

    plot <- plot_bivariate(bivariate_data(),
                           log_1 = log_1, log_2 = log_2,
                           method_highlight = method_highlight,
                           flagged_results = flagged_results,
                           alpha = 0.6)

    removeNotification(id = plot_notification)

    plot

  })

  zoom_range <- reactiveValues(x = NULL, y = NULL)

  observe({
    brush <- input$zoom_brush
    if (!is.null(brush)) {
      zoom_range$x <- c(brush$xmin, brush$xmax)
      zoom_range$y <- c(brush$ymin, brush$ymax)

    } else {
      zoom_range$x <- NULL
      zoom_range$y <- NULL
    }
  })

  output$zoomed_bivariate_plot <- renderPlot({

    if(is.null(bivariate_data()))
      return(NULL)

    log_1 <- "x" %in% input$log_biv
    log_2 <- "y" %in% input$log_biv
    method_highlight <- input$method_highlight
    flagged_results <- bivariate_flagged()
    range_1 <- zoom_range$x
    range_2 <- zoom_range$y

    if(nrow(bivariate_data()) == 0) {
      return(NULL)
    }

    plot <- plot_bivariate(bivariate_data(),
                           log_1 = log_1, log_2 = log_2,
                           method_highlight = method_highlight,
                           flagged_results = flagged_results,
                           range_1 = range_1, range_2 = range_2,
                           alpha = 0.6)
    plot

  })

  flag_range <- reactiveValues(x = NULL, y = NULL)

  observe({
    brush <- input$flag_brush
    if (!is.null(brush)) {
      flag_range$x <- c(brush$xmin, brush$xmax)
      flag_range$y <- c(brush$ymin, brush$ymax)

    } else {
      flag_range$x <- NULL
      flag_range$y <- NULL
    }
  })

  observeEvent(input$flag_biv, {

    range_1 <- flag_range$x
    range_2 <- flag_range$y
    flagged <- bivariate_flagged()

    to_flag <- bivariate_data() %>%
      filter(RESULT_VALUE.1 >= range_1[1],
             RESULT_VALUE.1 <= range_1[2],
             RESULT_VALUE.2 >= range_2[1],
             RESULT_VALUE.2 <= range_2[2]) %>%
      select(RESULT_ID.1, RESULT_ID.2) %>%
      head(10000)

    results_to_flag <- c(to_flag$RESULT_ID.1, to_flag$RESULT_ID.2)
    results_to_flag <- results_to_flag[!(results_to_flag %in% flagged)]

    if(length(results_to_flag) > 0) {

      apply_flags(cyan_connection(), "MANBIV", input$initials, results_to_flag)

    }

  })

  observeEvent(input$unflag_biv, {

    range_1 <- flag_range$x
    range_2 <- flag_range$y

    if(!is.null(range_1)) {

      flagged <- bivariate_flagged()

      to_unflag <- bivariate_data() %>%
        filter(RESULT_VALUE.1 >= range_1[1],
               RESULT_VALUE.1 <= range_1[2],
               RESULT_VALUE.2 >= range_2[1],
               RESULT_VALUE.2 <= range_2[2]) %>%
        select(RESULT_ID.1, RESULT_ID.2) %>%
        head(10000)

      results_to_unflag <- c(to_unflag$RESULT_ID.1, to_unflag$RESULT_ID.2)
      results_to_unflag <- results_to_unflag[results_to_unflag %in% flagged]

      if(length(results_to_unflag) > 0) {

        remove_flags(cyan_connection(), "MANBIV", results_to_unflag)

      }
    }
  })

  output$download_bivariate <- downloadHandler(
    filename = function() {
      "bivariate_data.csv"
    },
    content = function(file) {

      write.csv(bivariate_data(), file, row.names = FALSE, na = "")

    }
  )

  output$select_flag_ui <- renderUI({

    if(is.null(cyan_connection()))
      return(NULL)

    flags <- tbl(cyan_connection(), "FLAG_KEY") %>%
      collect()
    choices <- flags$FLAG_CODE
    names(choices) <- flags$FLAG_DEFINITION

    selectInput("select_flag", label = "Download results flagged with", choices = choices)

  })

  output$download_flagged <- downloadHandler(
    filename = function() {
      paste0(input$select_flag, "_flagged.csv")
    },
    content = function(file) {
      data <- find_flagged_data(cyan_connection(), input$select_flag,  collect = TRUE)
      write.csv(data, file, row.names = FALSE, na = "")
    }
  )

}

shinyApp(ui = ui, server = server)

