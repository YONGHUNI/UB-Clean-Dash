# load required packages
library(shiny)
library(shinydashboard)
library(shinybusy)
library(flexdashboard) 
library(lubridate)
library(leaflet)
#library(DT)
library(sf)
library(data.table)
library(base64enc)
library(jsonlite)
library(DBI)
library(RPostgres)
library(plotly)
library(ggplot2)


# read secret
if (file.exists(".Renviron")) {
    readRenviron(".Renviron")
}


# some front-end design
ui <- shinydashboard::dashboardPage(
    dashboardHeader(
        title =  "Breathe Buffalo: UB Air Quality Monitoring",
        titleWidth = "100%",
        # Dropdown menu for notifications
        dropdownMenu(type = "notifications", icon = icon("list"),
                     headerText = "",
                     notificationItem(icon = icon("leaf"),
                                      status = "success", "  About",
                                      href = "https://ubairqualitystudy.github.io/EPA-Website/index.html"
                     ),
                     notificationItem(icon = icon("square-github"), status = "primary",
                                      "  Source Code",href = "https://github.com/YONGHUNI/UB-Clean-Dash"
                     ),
                     notificationItem(icon = icon("bug-slash"), status = "danger",
                                      "  Report a Bug", href = "https://github.com/YONGHUNI/UB-Clean-Dash/issues"
                     )
        )
    ),
    # Don't need a sidebar at the moment
    shinydashboard::dashboardSidebar(disable = TRUE, width = 0),
    
    dashboardBody(
        tags$head(
            # calculate width of browser
            tags$script(HTML("
                              $(document).on('shiny:connected', function(e) {
                                Shiny.setInputValue('browser_width', window.innerWidth);
                              });
                        
                              $(window).resize(function(e) {
                                Shiny.setInputValue('browser_width', window.innerWidth);
                              });
                            ")
                        ),
            # globally set target="_blank" when href
            tags$base(target="_blank"),
            # favicon https://stackoverflow.com/questions/30096187/favicon-in-shiny
            tags$link(rel="shortcut icon", href="favicon.ico"),
            # custom css for the theme
            tags$style(HTML("
            
         .main-header .logo {
            font-size: 20px;
            font-weight: bold;
            white-space: normal !important;
            word-break: break-word;
            display: flex;
            align-items: center;
            justify-content: space-between;
            flex-wrap: wrap;
            width: 100%;
        }
        /* Steel blue (#3c8dbc) */
        
        /* 1) Header/Logo/Top Navigation Bar */
        .main-header .logo, 
        .skin-blue .main-header .navbar {
          background-color: #3c8dbc !important;
          color: white !important;
        }
        
        /* 2) Footer color */
        .footer {
          background-color: #3c8dbc;
          position: fixed;
          left: 0;
          bottom: 0;
          width: 100%;
          color: white;
          text-align: right;
          padding: 10px 20px;
          z-index: 1000;
        }
      "))
        ),
        fluidRow(
            # left column: map
            column(
                width = 5,
                
                # Map for AQ
                box(
                    title = "Spatial Distribution of Daily Air Quality", 
                    status = "primary", 
                    solidHeader = TRUE, 
                    width = NULL,
                    #height = "calc(100vh-0px)",
                    style = "position: relative; padding: 0;",

                    #leafletOutput("map", height = "calc(100vh - 200px)"),
                    uiOutput("map_ui"),
                    absolutePanel(            id = "overlay_controls", class = "panel panel-default",
                                              top = 5,   # relative to the map box
                                              right  = 10,
                                              width  = 230,
                                              draggable = TRUE,
                                              style  = "z-index: 1000; max-height:118px;",
                                              uiOutput("controls_box")
                    )
                )
            ),
            # right column: guage & lower sections (Controls + bar plot)
            column(
                width = 7,
                
                # Air Quality Gauges
                box(
                    title = "Air Quality Gauges", 
                    status = "primary", 
                    solidHeader = TRUE,
                    width = NULL,
                    fluidRow(
                        column(6,
                               tags$div("Daily Average: Selected ZIP Code", style = "text-align: center; font-weight: bold;"),
                               gaugeOutput("pollutant_gauge", height = "120px")
                        ),
                        column(6,
                               tags$div("Daily Average: City-wide", style = "text-align: center; font-weight: bold;"),
                               gaugeOutput("pollutant_avg_gauge", height = "120px")
                        )
                    ),
                    # PM2.5 Color Ramp
                    plotOutput("pollutant_color_ramp", height = "50px"),
                    # Color Ramp Help Messages
                    tags$p("Color Ramp: indicates air quality levels from 'Good' (Green) to 'Hazardous' (Red).",
                           style = "text-align:center; font-size:14px; margin-top:5px; font-weight:bold;")
                ),
                
                # Arrange the controls next to the bar plot
                fluidRow(
                    # column(
                    #     width = 4,
                    #     uiOutput("controls_box")
                    # ),
                    column(
                        width = 12,
                        box(
                            title = "Past 7-Day Air Quality Summary", 
                            status = "primary", 
                            solidHeader = TRUE,
                            width = NULL,
                            plotlyOutput("bar_plot",height = "calc(100vh - 507px)")
                        )
                    )
                )
            )
        ),
        div(class = "footer",
            img(src = "UB_logo-removebg-preview.png", alt = "UB Logo", height = "40px",
                style = "vertical-align: middle; margin-right: 10px; margin-left: 10px;"),
            span("UB Clean Air")
        )
    )
)


# custom legend for the leaflet
addLegendCustom <- function(map, theme, position = "bottomright") {
    if (theme == "pm2.5_atm") {
        colors <- c("#73C557", "#FA9857", "#FA4662")
        labels <- c("0–12 µg/m³", "12–55.4 µg/m³", ">55.4 µg/m³")
        title <- "PM2.5 Range"
    } else if (theme == "voc") {
        colors <- c("#73C557", "#FA9857", "#FA4662")
        labels <- c("0–300 ppb", "300–500 ppb", ">500 ppb")
        title <- "VOC Range"
    } else {
        colors <- "gray"
        labels <- "No range"
        title <- "N/A"
    }
    
    leaflet::addLegend(
        map,
        colors = colors,
        labels = labels,
        title = title,
        opacity = 1,
        position = position
    )
    
}


# server-side
server <- function(input, output, session) {
    
    #removeUI(selector = "span.label.label-primary")
    removeUI(selector = "li[role='presentation']")
    
    # function for PM calibration
    calibrate_pm25 <- function(pm25atm,rh){
        
        
        y = (0.444*pm25atm) + (-0.059*rh) + 4.768
        
        return(y)
        
    }
    
    
    # spinner for every init
    show_modal_spinner(
        spin = "cube-grid",
        color = "firebrick",
        text = "Initializing... Please wait..."
    )

    
    # 1) read spatial data (US zip)
    target <- st_read("data/zip/target.gpkg", quiet = TRUE)
    # mutation for the join
    target$ZCTA5CE10 <- as.character(target$ZCTA5CE10)
    
    ## read participants' sensitive info from the env file
    participants <- Sys.getenv("PARTICIPANTS") |>
        base64enc::base64decode() |>
        rawToChar() |>
        jsonlite::fromJSON() |>
        as.data.table()
    
    ## Make the connection from the DB
    con <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("DB_NAME"),

                          host = Sys.getenv("DB_HOST"), port = Sys.getenv("DB_PORT"), user = Sys.getenv("DB_USER"),

                          password = Sys.getenv("DB_PASS"))


    # read cached database
    database <- fread("./data/base_PA.csv")
    
    # find new data from the remote DB
    end_time <- database[,max(time_stamp),by = sensor_index]
    latest_conditions <- paste0(
        "(sensor_index = '", end_time$sensor_index,
        "' AND time_stamp > ", end_time$V1, ")"
    )
    
    
    # make query
    where_clause <- paste(latest_conditions, collapse = " OR ")
    
    ## hourly reduced fetch query to save the amount of outgoing traffic
    query <- paste("
                      SELECT 
                        date_trunc('hour', to_timestamp(time_stamp)) AS time_stamp,
                        sensor_index,
                        AVG(voc) AS voc,
                        AVG(humidity) AS humidity,
                        AVG(\"pm2.5_atm\") AS \"pm2.5_atm\"
                      FROM \"Purple_Air\"
                      WHERE",where_clause,"
                      GROUP BY time_stamp, sensor_index
                    ")
    
    # reduce to daily and calibrate 2.5's
    database <- dbGetQuery(con, query) |> as.data.table()  |> rbind(database,use.names = T) |>
        _[,  `Date_Time(ET)`  :=  floor_date(with_tz(as_datetime(time_stamp,tz="UTC"), tzone = "America/New_York"),unit = "hour")][
                 # Calculate averages by sensor and time
                , .(
                    humidity = mean(humidity, na.rm = TRUE),
                    voc = mean(voc, na.rm = TRUE),
                    `pm2.5_atm` = mean(`pm2.5_atm`, na.rm = TRUE) 
                    )
                , by = .(sensor_index, `Date_Time(ET)`)][
            ,c("sensor_index","pm2.5_atm"):=list(as.numeric(sensor_index),calibrate_pm25(`pm2.5_atm`,humidity))]|>
        _[participants, on = c(sensor_index = "sensor index")]
    
    
 
    # on-demand data filtering for the map
    filtered_data <- reactive({
        req(input$end_time_inp)
        
        end_time_m   <- (as_date(input$end_time_inp, tz = "America/New_York")+days(1))
        start_time_m <- (as_date(input$end_time_inp, tz = "America/New_York"))
        
        database[`Date_Time(ET)` >= start_time_m & `Date_Time(ET)` <end_time_m]
    })
    
    # on-demand data filtering for the bar plot
    filtered_data_barplot<- reactive({
        req(input$end_time_inp)
        
        end_time_b   <- (as_date(input$end_time_inp, tz = "America/New_York")+days(1))
        start_time_b <- (as_date(input$end_time_inp, tz = "America/New_York")-days(6))
        
        database[`Date_Time(ET)` >= start_time_b & `Date_Time(ET)` < end_time_b]
    })
    
    
    
    # 3) Calculate averages by ZIP code
    zipgroup <- reactive({
        fd <- filtered_data()
        if (nrow(fd) == 0) {
            return(data.table(zipcode = character(), pm2.5_atm = numeric(), voc = numeric()))
        }
        fd[, .(
            pm2.5_atm = mean(pm2.5_atm, na.rm = TRUE),
            voc       = mean(voc, na.rm = TRUE)
        ), by = zipcode]

    })
    
    # 4) Join the spatial sf data for the map with the ZIP‐level averages
    target_attr <- reactive({
        tg <- copy(target)
        zg <- zipgroup()
        if ("zipcode" %in% names(zg)) {
            zg[, zipcode := as.character(zipcode)]
        }
        merge(tg, zg, by.x = "ZCTA5CE10", by.y = "zipcode", all.x = TRUE)
    })
    
    # end of initialization, stop the loading screen
    remove_modal_spinner()

    
    # render the map
    output$map <- renderLeaflet({
        ta <- target_attr()
        val_vec <- ta[[input$color_theme]]
        
        # 0. map extent for both mobile & desktop support
        w <- input$browser_width
        
        fitBounds_adapt <- function(map,x){
            
            if (x < 768) {
                
                fitBounds(map, -78.75, 42.80, -78.67, 43.00)
                
            } else {
                
                fitBounds(map, -78.93, 42.80, -78.77, 43.00)
                
            }
            
        }
        
        
        # 1. Define a custom color function
        get_custom_pal <- function(theme) {
            function(x) {
                if (theme == "pm2.5_atm") {
                    ifelse(x <= 12, "#73C557",       # green
                           ifelse(x <= 55.4, "#FA9857", "#FA4662"))  # yellow / red
                } else if (theme == "voc") {
                    ifelse(x <= 300, "#73C557",
                           ifelse(x <= 500, "#FA9857", "#FA4662"))
                } else {
                    # fallback
                    rep("gray", length(x))
                }
            }
        }
        
        # then call it
        my_pal <- get_custom_pal(input$color_theme)
        

        

        
        
        # 2. build lefleat layers
        leaflet(ta) %>%
            addTiles() %>%
            addPolygons(
                layerId = ~ZCTA5CE10,
                fillColor = ~my_pal(ta[[input$color_theme]]),
                color = "black",
                weight = 1,
                fillOpacity = 0.7,
                popup = ~paste(
                    "Zip Code:", ZCTA5CE10, "<br>",
                    "PM2.5:", ifelse(is.na(pm2.5_atm), "No data", round(pm2.5_atm, 1)), " µg/m³<br>",
                    "VOC:", ifelse(is.na(voc), "No data", round(voc, 1)), " ppb"
                )
            )  %>%
            fitBounds_adapt(w) %>%
            # 3. add custom legend
            addLegendCustom(
                theme = input$color_theme,
                position = "bottomright"
            )
    })
    
    
    # 6) on click event to select a zip -> save selected zip
    selected_region <- reactiveVal(NULL)
    observeEvent(input$map_shape_click, {
        click <- input$map_shape_click
        if (!is.null(click$id)) {
            selected_region(click$id)
        }
    })
    
    output$map_ui <- renderUI({
        
        # get width from browser
        w <- input$browser_width


        # exception for handling null width
        if (is.null(w) || w == 0) w <- 767
        
        # calculate map height
        h <- round(w * 0.65)
        
        # for debugging
        #print(paste0(w,", ",h, "px"))
        
        if (w<768) {
            # for the mobile support
            leafletOutput("map", width = "100%", height = paste0(h, "px"))
            
        } else {
            
            leafletOutput("map", width = "100%", height = "calc(100vh - 180px)")
        }
        
    })
    

    # 7) render gauge & color ramp
    output$pollutant_gauge <- renderGauge({
        req(input$color_theme)
        region_id <- selected_region()
        sel <- zipgroup()[zipcode %in% region_id]
        
        
        if (input$color_theme == "pm2.5_atm") {
            if (nrow(sel) == 0) return(gauge("NaN", symbol = " µg/m³", min = 0, max = 100))
            
            val <- sel$pm2.5_atm
            gauge(val, min = 0, max = 100, symbol = " µg/m³",
                  gaugeSectors(success = c(0, 12), warning = c(12, 55.4), danger = c(55.4, 100)))
        } else {
            if (nrow(sel) == 0) return(gauge("NaN", symbol = " ppb", min = 0, max = 1000))
            
            val <- sel$voc
            gauge(val, min = 0, max = 1000, symbol = " ppb",
                  gaugeSectors(success = c(0, 300), warning = c(300, 500), danger = c(500, 1000)))
        }
    })
    
    
    output$pollutant_avg_gauge <- renderGauge({
        req(input$color_theme)
        fd <- filtered_data()
        
        if (input$color_theme == "pm2.5_atm") {
            if (nrow(fd) == 0) return(gauge("NaN", symbol = " µg/m³", min = 0, max = 100))
            
            val <- mean(fd$pm2.5_atm, na.rm = TRUE)
            gauge(val, min = 0, max = 100, symbol = " µg/m³",
                  gaugeSectors(success = c(0, 12), warning = c(12, 55.4), danger = c(55.4, 100)))
        } else {
            if (nrow(fd) == 0) return(gauge("NaN", symbol = " ppb", min = 0, max = 1000))
            
            val <- mean(fd$voc, na.rm = TRUE)
            gauge(val, min = 0, max = 1000, symbol = " ppb",
                  gaugeSectors(success = c(0, 300), warning = c(300, 500), danger = c(500, 1000)))
        }
    })
    
    output$pollutant_color_ramp <- renderPlot({
        req(input$color_theme)
        par(mar = c(2, 1, 1, 1))
        plot.new()
        
        if (input$color_theme == "pm2.5_atm") {
            plot.window(xlim = c(0, 100), ylim = c(0, 1))
            rect(0, 0, 12, 1, col = "#73C557", border = NA)
            rect(12, 0, 55.4, 1, col = "#FA9857", border = NA)
            rect(55.4, 0, 100, 1, col = "#FA4662", border = NA)
            axis(1, at = c(0, 12, 55.4, 100), labels = c("0", "12", "55.4", "100"), cex.axis = 0.8)
        } else {
            plot.window(xlim = c(0, 1000), ylim = c(0, 1))
            rect(0, 0, 300, 1, col = "#73C557", border = NA)
            rect(300, 0, 500, 1, col = "#FA9857", border = NA)
            rect(500, 0, 1000, 1, col = "#FA4662", border = NA)
            axis(1, at = c(0, 300, 500, 1000), labels = c("0", "300", "500", "1000"), cex.axis = 0.8)
        }
    })

    # 11) add control-box backend
    
    end_time <- max(database$`Date_Time(ET)`,na.rm = T) |>
        as_datetime(tz = "America/New_York") |> floor_date("day")
    
    output$controls_box <- renderUI({
        box(
            #title = "Your Selection", 
            status = "primary", 
            solidHeader = TRUE,
            width = NULL,
            height = "133px",
            
            dateInput("end_time_inp", 
                      label = "Choose a Date to View Air Quality",
                      format = "MM-dd-yyyy",
                      max = end_time,
                      value = end_time
                      ),
            
            radioButtons(
                inputId = "color_theme",
                label = "Type of Air Pollutant",
                choices = c("PM2.5" = "pm2.5_atm", "VOC" = "voc"),
                selected = "pm2.5_atm",
                inline = T
            )
        )
    })
    # 12) render bar plot
    output$bar_plot <- renderPlotly({
        req(input$color_theme)
        region_id <- selected_region()
        fd <- filtered_data_barplot()
        
        # extract the date
        fd[, date_only := as_date(`Date_Time(ET)`, tz = "America/New_York" )]
        
        #for debugging
        #print(table(fd$date_only))
        
        col_selected <- input$color_theme
        label <- if (col_selected == "pm2.5_atm") "PM2.5" else "VOC"
        
        
        # calculate daily averages for the entire dataset
        total_avg <- fd[, .(
            value = mean(get(col_selected), na.rm = TRUE)
        ), by = date_only]
        total_avg[, group := "City-wide"]
        
        
        
        # daily avg. for the selected ZIP.
        zip_avg <- fd[zipcode %in% region_id, .(
            value = mean(get(col_selected), na.rm = TRUE)
        ), by = date_only]
        
        
        # if the selected zip has value
        if (!is.null(region_id) && length(region_id) > 0 && dim(zip_avg)[1]>0) {
            
            zip_avg[, group := paste("ZIP", region_id)]
            
            # rbind two
            plot_dt <- rbind(zip_avg, total_avg)
            
            # render bar plot with plotly
            plot_ly(
                data = plot_dt,
                x = ~date_only,
                y = ~value,
                color = ~group,
                colors = c("skyblue","tomato"),
                type = "bar"
            ) |>
                layout(
                    title = paste("Selected ZIP", 
                                  #region_id,
                                  "vs City-wide"),
                    xaxis = list(title = "Date"),
                    yaxis = list(title = paste(label, "Average")),
                    barmode = "group"
                )
            
        # otherwise...
        } else {

            # rbind not needed
            plot_dt <- total_avg
            
            
            # render bar plot of only city-wide avg. with plotly
            plot_ly(
                data = plot_dt,
                x = ~date_only,
                y = ~value,
                #color = ~group,
                type = "bar"
            ) |>
                layout(
                    title = "City-wide",
                    xaxis = list(title = "Date"),
                    yaxis = list(title = paste(label, "Average")),
                    barmode = "group"
                )
            
        }

        

    })
    
    
    
    # if user closes the dashboard, disconnect the DB conn
    session$onSessionEnded(function() {
        DBI::dbDisconnect(con)
    })
    
    
}

# run the app
shinyApp(ui, server)