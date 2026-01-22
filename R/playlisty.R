library(shiny)
library(DBI)
library(DT)
library(RPostgres)
#library(shinydashboard)
library(shinyWidgets)

# Łączenie z bazą
con <- dbConnect(
  RPostgres::Postgres(),
  dbname = "WPISZ",
  host = "localhost",
  port = 5432,
  user = "WPISZ",
  password = "WPISZ"
)

# Funkcje db
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
  dbExecute(conn, "SELECT add_new_playlist($1)", params = list(name))
}

db_delete_playlist <- function(conn, p_id) {
  dbExecute(conn, "SELECT delete_playlist($1)", params = list(p_id))
}

db_add_song_to_playlist <- function(conn, p_id, sv_id) {
  dbExecute(conn, "SELECT add_song_to_playlist_auto($1, $2)",
    params = list(p_id, as.numeric(sv_id)))
}

db_remove_song_from_playlist <- function(conn, p_id, pos) {
  dbExecute(conn, "SELECT remove_song_from_playlist($1, $2)", 
            params = list(p_id, pos))
}

db_move_playlist_item <- function(conn, p_id, old_pos, new_pos) {
  dbExecute(conn, "SELECT move_playlist_item($1, $2, $3)",
    params = list(p_id, old_pos, new_pos))
}

db_start_playback <- function(conn, sv_id) {
  dbGetQuery(conn, "SELECT start_playback($1) AS id", params = list(sv_id))$id
}

db_finish_playback <- function(conn, session_id) {
  dbExecute(conn, "SELECT finish_playback($1)", params = list(session_id))
}

# UI 
ui <- fluidPage(
  titlePanel("Odtwarzacz Muzyki"), # System zarządzania muzyką brzmi slay, ale cmoooon XD
  
  # Sekcja 1: Wybór Playlisty
  fluidRow(
    column(4, 
           wellPanel(
             h4("Zarządzaj Playlistami"),
             textInput("playlist_name", "Nazwa nowej playlisty:", ""),
             actionButton("add_btn", "Dodaj", class = "btn-success"),
             actionButton("delete_btn", "Usuń", class = "btn-danger")
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

# SERVER
server <- function(input, output, session) {
  
  # Stan aplikacji 
  playlists_rv <- reactiveVal()
  songs_rv <- reactiveVal()

    # Stan odtwarzania
  current_session <- reactiveVal(NULL)
  playback_seconds <- reactiveVal(0)
  is_playing <- reactiveVal(FALSE)
  
  # Inicjalizacja danych
  observe({
    playlists_rv(db_get_playlists(con))
  })
  
  # Helper: pobieranie ID obecnie wybranej playlisty
  get_selected_playlist_id <- function() {
    req(input$playlist_table_rows_selected)
    playlists_rv()$playlist_id[input$playlist_table_rows_selected]
  }
  
  # Renderowanie tabel
  output$playlist_table <- renderDT({
    datatable(playlists_rv(), selection = 'single', rownames = FALSE, 
              options = list(scrollX = TRUE, pageLength=5))
  })
  
  output$songs_table <- renderDT({
    req(songs_rv())
    datatable(songs_rv(), selection = 'single', rownames = FALSE,
              options = list(scrollX = TRUE, pageLength=5))
  })
  
  # DYNAMICZNE UI 
  output$dynamic_songs_ui <- renderUI({
    # Jeśli nie wybrano wiersza, nic nie pokazuj
    if (is.null(input$playlist_table_rows_selected)) {
      return(helpText("Wybierz playlistę, aby zobaczyć utwory."))
    }

    dur <- if (!is.null(input$songs_table_rows_selected))
      songs_rv()$duration[input$songs_table_rows_selected] else 1
      
    # Budujemy panel szczegółów
    tagList(
      fluidRow(
        column(4,
               wellPanel(
                 h4("Dodaj utwór"),
                 selectizeInput("song_v_id", "Wyszukaj utwór:", 
                                choices = c("Zacznij pisać..." = "", db_get_song_choices(con))),
                 #numericInput("pos", "Pozycja:", value = next_pos()), # psuło, było bez ()
                 actionButton("add_song_btn", "Dodaj do listy", class = "btn-primary"),
                 hr(),
                 actionButton("move_up_btn", "↑ Przesuń w górę", class = "btn-secondary"),
                 actionButton("move_down_btn", "↓ Przesuń w dół", class = "btn-secondary"),
                 actionButton("remove_song_btn", "Usuń zaznaczony utwór", class = "btn-warning"),
                 hr(),
                 #actionButton("play_btn", label = reactive(if (is_playing()) "Stop" else "Play")), # na dole w play_btn label
                 actionButton("play_btn", "Play"),
                 shinyWidgets::progressBar(id = "progress", value = 0, total = dur)
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
  
  # OBSŁUGA ZDARZEŃ: PLAYLISTY
  observeEvent(input$add_btn, {
#    req(input$playlist_name) # zbędne?
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
  
  # OBSŁUGA ZDARZEŃ: UTWORY 
  # Pobierz utwory, gdy zmieni się zaznaczona playlista
  observeEvent(input$playlist_table_rows_selected, {
    songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
  })
  
  observeEvent(input$add_song_btn, {
    db_add_song_to_playlist(con, get_selected_playlist_id(), input$song_v_id)
    songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
  })

  observeEvent(input$remove_song_btn, {
    pos <- songs_rv()$item_position[input$songs_table_rows_selected]
    # Wyciągamy pozycję z tabeli songs_rv
    db_remove_song_from_playlist(con, get_selected_playlist_id(), pos)
    # Odświeżamy dane 
    songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
    showNotification("Utwór usunięty", type = "warning")
  })

  observeEvent(input$move_up_btn, {
    pos <- songs_rv()$item_position[input$songs_table_rows_selected]
    if (pos > 1)
      db_move_playlist_item(con, get_selected_playlist_id(), pos, pos - 1)
    songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
  })

  observeEvent(input$move_down_btn, {
    pos <- songs_rv()$item_position[input$songs_table_rows_selected]
    maxp <- max(songs_rv()$item_position)
    if (pos < maxp)
      db_move_playlist_item(con, get_selected_playlist_id(), pos, pos + 1)
    songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
}) 
      
  # PLAY / STOP
  observeEvent(input$play_btn, {
    req(input$songs_table_rows_selected)
    
    if (!is_playing()) {
      sv_id <- songs_rv()$song_version_id[input$songs_table_rows_selected]
      sid <- db_start_playback(con, sv_id)
      
      current_session(sid)
      playback_seconds(0)
      is_playing(TRUE)
      
      shinyWidgets::updateProgressBar(
        session, "progress",
        value = 0,
        total = songs_rv()$duration[input$songs_table_rows_selected]
      )
      
    } else {
      db_finish_playback(con, current_session())
      current_session(NULL)
      is_playing(FALSE)
      
      shinyWidgets::updateProgressBar(session, "progress", value = 0, total = dur)
    }
  })
  
  
  # TIMER
  observe({
    req(is_playing(), input$songs_table_rows_selected)
    
    invalidateLater(1000, session)
    
    playback_seconds(playback_seconds() + 1)
    
    shinyWidgets::updateProgressBar(
      session,
      id = "progress",
      value = playback_seconds(),
      total = songs_rv()$duration[input$songs_table_rows_selected]
    )
  })
  
  # play_btn label  - żeby label ile jest sekund się zmieniał bo ten poprzedni podobno może być tylko stały
  observe({
    updateActionButton(
      session,
      "play_btn",
      label = if (is_playing()) "Stop" else "Play"
    )
  })
  
  

}

shinyApp(ui, server)

