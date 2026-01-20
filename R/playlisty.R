
library(shiny)
library(DBI)
library(DT)
library(RPostgres)

con <- dbConnect(
  RPostgres::Postgres(),
  dbname = "projekt_muzyka",
  host = "localhost",
  port = 5432,
  user = "guy",
  password = "haslo"
)


db_get_playlists <- function(conn) {
  dbGetQuery(conn, "SELECT * FROM get_all_playlists()")
}

db_get_song_choices <- function(conn) {
  res <- dbGetQuery(conn, "SELECT * FROM get_song_version_choices()")
  setNames(res$id, res$display_label)
}

db_get_playlist_items <- function(conn, p_id) {
  dbGetQuery(conn, "SELECT * FROM get_playlist_contents($1)", params = list(p_id))
}

db_add_playlist <- function(conn, name) {
  dbExecute(conn, "INSERT INTO Playlists (name, created_at) VALUES ($1, $2)", 
            params = list(name, as.character(Sys.Date())))
}

db_delete_playlist <- function(conn, p_id) {
  dbExecute(conn, "DELETE FROM Playlists WHERE playlist_id = $1", params = list(p_id))
}

db_add_song_to_playlist <- function(conn, p_id, sv_id, pos) {
  # Wykorzystujemy naszą funkcję SQL
  dbExecute(conn, "SELECT add_song_to_playlist($1, $2, $3)", 
            params = list(p_id, as.numeric(sv_id), pos))
}

db_remove_song_from_playlist <- function(conn, p_id, pos) {
  dbExecute(conn, "DELETE FROM PlaylistItems WHERE playlist_id = $1 AND position = $2",
            params = list(p_id, pos))
}

ui <- fluidPage(
  titlePanel("System Zarządzania Muzyką"),
  
  # Sekcja 1: Wybór Playlisty
  fluidRow(
    column(4, 
           wellPanel(
             h4("Zarządzaj Playlistami"),
             textInput("playlist_name", "Nazwa nowej playlisty:", ""),
             actionButton("add_btn", "Utwórz", class = "btn-success"),
             actionButton("delete_btn", "Usuń wybraną", class = "btn-danger")
           )
    ),
    column(8, 
           h4("Twoje Playlisty"),
           DTOutput("playlist_table")
    )
  ),
  
  hr(),
  
  # Sekcja 2: Dynamiczne UI (Piosenki)
  uiOutput("dynamic_songs_ui")
)


server <- function(input, output, session) {
  
  # --- STAN APLIKACJI ---
  playlists_rv <- reactiveVal()
  songs_rv <- reactiveVal()
  
  # Inicjalizacja danych
  observe({
    playlists_rv(db_get_playlists(con))
  })
  
  # Helper: pobieranie ID obecnie wybranej playlisty
  get_selected_playlist_id <- function() {
    req(input$playlist_table_rows_selected)
    playlists_rv()$playlist_id[input$playlist_table_rows_selected]
  }
  
  # --- RENDEROWANIE TABELI ---
  output$playlist_table <- renderDT({
    datatable(playlists_rv(), selection = 'single', rownames = FALSE, 
              options = list(scrollX = TRUE, pageLength=5))
  })
  
  output$songs_table <- renderDT({
    req(songs_rv())
    datatable(songs_rv(), selection = 'single', rownames = FALSE,
              options = list(scrollX = TRUE, pageLength=5))
  })
  
  # --- DYNAMICZNE UI ---
  output$dynamic_songs_ui <- renderUI({
    # Jeśli nie wybrano wiersza, nic nie pokazuj
    if (is.null(input$playlist_table_rows_selected)) {
      return(helpText("Wybierz playlistę z tabeli powyżej, aby zobaczyć utwory."))
    }
    
    # Obliczamy kolejną pozycję (max + 1)
    current_items <- songs_rv()
    next_pos <- if(is.null(current_items) || nrow(current_items) == 0) 1 else max(current_items$item_position) + 1
    
    # Budujemy panel szczegółów
    tagList(
      fluidRow(
        column(4,
               wellPanel(
                 h4("Dodaj utwór"),
                 selectizeInput("song_v_id", "Wyszukaj utwór:", 
                                choices = c("Zacznij pisać..." = "", db_get_song_choices(con))),
                 numericInput("pos", "Pozycja:", value = next_pos),
                 actionButton("add_song_btn", "Dodaj do listy", class = "btn-primary"),
                 br(),
                 actionButton("remove_song_btn", "Usuń zaznaczony utwór", class = "btn-warning")
               )
        ),
        column(8,
               h4(paste("Zawartość:", playlists_rv()$name[input$playlist_table_rows_selected])),
               DTOutput("songs_table"),
               br()
        )
      )
    )
  })
  
  # --- OBSŁUGA ZDARZEŃ: PLAYLISTY ---
  observeEvent(input$add_btn, {
    req(input$playlist_name)
    db_add_playlist(con, input$playlist_name)
    playlists_rv(db_get_playlists(con))
    updateTextInput(session, "playlist_name", value = "")
    showNotification("Playlista dodana", type = "message")
  })
  
  observeEvent(input$delete_btn, {
    db_delete_playlist(con, get_selected_playlist_id())
    playlists_rv(db_get_playlists(con))
    songs_rv(NULL)
    showNotification("Playlista usunięta", type = "message")
  })
  
  # --- OBSŁUGA ZDARZEŃ: UTWORY ---
  
  # Pobierz utwory, gdy zmieni się zaznaczona playlista
  observeEvent(input$playlist_table_rows_selected, {
    songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
  })
  
  observeEvent(input$add_song_btn, {
    req(input$song_v_id)
    tryCatch({
      db_add_song_to_playlist(con, get_selected_playlist_id(), input$song_v_id, input$pos)
      songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
      showNotification("Utwór dodany", type = "message")
    }, error = function(e) {
      showNotification(paste("Błąd bazy:", e$message), type = "error")
    })
  })
  
  observeEvent(input$remove_song_btn, {
    req(input$songs_table_rows_selected)
    
    # Wyciągamy pozycję z tabeli songs_rv
    pos_to_del <- songs_rv()$item_position[input$songs_table_rows_selected]
    
    db_remove_song_from_playlist(con, get_selected_playlist_id(), pos_to_del)
    
    # Odświeżamy dane 
    songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
    showNotification("Utwór usunięty", type = "warning")
  })
}

shinyApp(ui, server)
