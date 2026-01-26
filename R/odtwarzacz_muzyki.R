library(shiny)
library(DBI)
library(DT)
library(RPostgres)

con <- dbConnect(
  RPostgres::Postgres(),
  dbname = "WPISZ",
  host = "localhost",
  port = 5432,
  user = "WPISZ",
  password = "WPISZ"
)

# Funkcje do playlist

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


db_remove_song_from_playlist <- function(conn, p_id, pos) {
  dbExecute(conn, "SELECT remove_song_from_playlist($1, $2)", 
            params = list(p_id, pos))
}

db_add_song_auto <- function(conn, p_id, sv_id) {
  dbExecute(conn, "SELECT add_song_to_playlist_auto($1, $2)", params = list(p_id, as.numeric(sv_id)))
}

db_move_item <- function(conn, p_id, old_pos, new_pos) {
  dbExecute(conn, "SELECT move_playlist_item($1, $2, $3)", params = list(p_id, old_pos, new_pos))
}

db_play_item <- function(conn, p_id, pos, seconds) {
  dbExecute(conn, "SELECT play_playlist_item($1, $2, $3)", params = list(p_id, pos, seconds))
}

# Funkcje do odtwarzania

db_start_playback <- function(conn, sv_id) {
  res <- dbGetQuery(conn, "SELECT start_playback($1) as session_id", params = list(as.numeric(sv_id)))
  return(res$session_id)
}

db_pause_playback <- function(conn, session_id) {
  dbExecute(conn, "SELECT pause_playback($1)", params = list(as.numeric(session_id)))
}

db_finish_playback <- function(conn, session_id) {
  dbExecute(conn, "SELECT finish_playback($1)", params = list(as.numeric(session_id)))
}



# Funkcje do dodawania/usuwanie piosenek z bazy

db_get_library_full <- function(conn) {
  query <- "
    SELECT 
        s.song_id, 
        s.title, 
        ma.title AS album, 
        STRING_AGG(DISTINCT a.name, ', ') AS artists, -- Łączy wielu artystów w jeden tekst
        s.release_year, 
        STRING_AGG(DISTINCT mg.genre, ', ') AS genres, -- Łączy wiele gatunków w jeden tekst
        l.language 
    FROM Songs s 
    JOIN MusicAlbums ma ON s.album_id = ma.album_id 
    JOIN Languages l ON s.language_id = l.language_id
    -- Używamy LEFT JOIN, żeby piosenka nie zniknęła, jeśli nie ma gatunku/artysty
    LEFT JOIN SongsArtists sa ON s.song_id = sa.song_id
    LEFT JOIN Artists a ON sa.artist_id = a.artist_id
    LEFT JOIN SongsGenres sg ON s.song_id = sg.song_id
    LEFT JOIN MusicGenres mg ON mg.genre_id = sg.genre_id
    GROUP BY s.song_id, s.title, ma.title, s.release_year, l.language
    ORDER BY s.song_id DESC"
  
  dbGetQuery(conn, query)
}


#pomocnicza dla dodawania piosenki
to_pg_array <- function(x) {
  if (is.null(x) || length(x) == 0) return(NULL)
  # Zamieniamy c("A", "B") na '{"A","B"}'
  inner <- paste0('"', x, '"', collapse = ",")
  return(paste0("{", inner, "}"))
}

db_add_song_full <- function(conn, artists, title, album, lang, year, genres, version, dur, v_date) {
  
  sql <- "
    SELECT add_song(
      $1::varchar[], 
      $2::varchar, 
      $3::varchar, 
      $4::varchar, 
      $5::integer, 
      $6::varchar[], 
      $7::varchar, 
      $8::integer, 
      $9::date
    )"
  
  params_list <- list(
    to_pg_array(artists),    
    as.character(title),
    as.character(album),
    as.character(lang),
    as.integer(year),
    to_pg_array(genres),     
    as.character(version),
    as.integer(dur),
    as.character(v_date)
  )
  
  dbGetQuery(conn, sql, params = params_list)
}

db_delete_song_from_db <- function(conn, sid) {
  dbGetQuery(conn, "SELECT delete_song($1)", params = list(as.integer(sid)))
}

db_get_versions_by_sid <- function(conn, sid) {
  dbGetQuery(conn, "
    SELECT sv.song_version_id, vt.name as version_type, sv.duration, sv.created_at
    FROM SongVersions sv
    JOIN VersionTypes vt ON sv.version_type_id = vt.version_type_id
    WHERE sv.song_id = $1
    ORDER BY sv.created_at DESC", params = list(as.integer(sid)))
}


db_add_version <- function(conn, sid, version, dur, v_date) {
  dbGetQuery(conn, "SELECT add_version($1::integer, $2::varchar, $3::integer, $4::date)", 
             params = list(as.integer(sid), as.character(version), as.integer(dur), as.character(v_date)))
}


db_delete_version_from_db <- function(conn, vid) {
  dbGetQuery(conn, "SELECT delete_version($1::integer)", params = list(as.integer(vid)))
}


db_modify_song <- function(conn, sid,
                           new_lang = NULL,
                           add_artist = NULL,
                           delete_artist = NULL,
                           add_genre = NULL,
                           delete_genre = NULL) {
  dbGetQuery(
    conn,
    "SELECT modify_song($1,$2,$3,$4,$5,$6)",
    params = list(
      as.integer(sid),
      new_lang,
      add_artist,
      delete_artist,
      add_genre,
      delete_genre
    )
  )
}

# Funkcje statystyk
db_get_all_stats <- function(conn) {
  dbGetQuery(conn, "SELECT * FROM statistics_all")
}

db_get_monthly_stats <- function(conn, od_dnia, do_dnia) {
  dbGetQuery(conn, "SELECT * FROM monthly_stats($1, $2)", 
             params = list(as.character(od_dnia), as.character(do_dnia)))
}



# Ui statycznych elementów
ui <- navbarPage(
  "Odtwarzacz Muzyki",
  
  # ZAKŁADKA 1: Zarządzanie Playlistami
  tabPanel("Odtwarzacz i Playlisty",
           fluidPage(
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
             uiOutput("dynamic_songs_ui"),
             hr(),
             conditionalPanel(
               condition = "input.songs_table_rows_selected > 0 || output.is_playing == true",
               fluidRow(
                 column(12, align = "center",
                        wellPanel(
                          h4(textOutput("current_track_label")),
                          uiOutput("playback_progress_ui"),
                          br(),
                          actionButton("play_btn", "Play", icon = icon("play"), class = "btn-success"),
                          actionButton("pause_btn", "Pause", icon = icon("pause"), class = "btn-warning"),
                          actionButton("stop_btn", "Stop", icon = icon("stop"), class = "btn-danger")
                        )
                 )
               )
             )
           )
  ),
  
  # ZAKŁADKA 2: Zarządzanie Bazą Piosenek 
  tabPanel("Biblioteka i Zarządzanie",
           sidebarLayout(
             sidebarPanel(
               h3("Dodaj nową piosenkę"),
               helpText("Wypełnij formularz, aby dodać utwór, album i wersję."),
               textInput("new_s_title", "Tytuł piosenki:"),
               textInput("new_s_artists", "Artyści (oddzieleni przecinkiem, max 3):", ""),
               textInput("new_s_album", "Album:"),
               textInput("new_s_lang", "Język:", ""),
               numericInput("new_s_year", "Rok wydania:", value = 2026, min = 1861),
               textInput("new_s_genres", "Gatunki (oddzielone przecinkiem, max 3):", ""),
               hr(),
               h4("Pierwsza wersja utworu"),
               textInput("new_s_ver_type", "Typ wersji:", "Original"),
               numericInput("new_s_duration", "Czas trwania (sekundy):", value = 200, min = 1),
               dateInput("new_s_date", "Data utworzenia wersji:", value = Sys.Date()),
               br(),
               actionButton("save_song_btn", "Dodaj piosenkę do bazy", class = "btn-primary", width = "100%"),
               
               hr(),
               
               
               h4("Modyfikuj zaznaczoną piosenkę"),
               
               textInput("mod_lang", "Nowy język:", ""),
               textInput("mod_add_artist", "Dodaj artystę:", ""),
               textInput("mod_del_artist", "Usuń artystę:", ""),
               textInput("mod_add_genre", "Dodaj gatunek:", ""),
               textInput("mod_del_genre", "Usuń gatunek:", ""),
               
               actionButton(
                 "modify_song_btn",
                 "Zastosuj zmiany",
                 class = "btn-warning",
                 width = "100%"
               ),
             ),
             mainPanel(
               h3("Wszystkie piosenki w bazie danych"),
               DTOutput("full_library_table"),
               br(),
               actionButton("delete_song_db_btn", "USUŃ PIOSENKĘ (Z WSZYSTKIMI WERSJAMI)", class = "btn-danger"),
               
               hr(),
               # Sekcja wersji - widoczna tylko po wybraniu piosenki
               uiOutput("versions_management_ui")# Linia oddzielająca
             )
           )
  ),
  
  # ZAKŁADKA 3: Statystyki
  tabPanel("Statystyki",
           fluidPage(
             h2("Twoje statystyki słuchania"),
             
             fluidRow(
               column(6,
                      wellPanel(
                        h3("Statystyki ogólne (cały czas)"),
                        tableOutput("stats_all_table")
                      )
               ),
               column(6,
                      wellPanel(
                        h3("Statystyki w wybranym okresie"),
                        dateRangeInput("stats_date_range", 
                                       "Wybierz zakres dat:",
                                       start = Sys.Date() - 30,
                                       end = Sys.Date(),
                                       format = "yyyy-mm-dd",
                                       language = "pl"),
                        actionButton("refresh_monthly_stats", "Odśwież", 
                                     class = "btn-info", icon = icon("refresh")),
                        hr(),
                        tableOutput("stats_monthly_table")
                      )
               )
             )
           )
  )
)


server <- function(input, output, session) {
  
  # --- STAN APLIKACJI ---
  playlists_rv <- reactiveVal()
  songs_rv <- reactiveVal()
  library_rv <- reactiveVal()
  versions_rv <- reactiveVal()
  stats_all_rv <- reactiveVal()
  stats_monthly_rv <- reactiveVal()# Stan wersji wybranej piosenki
  
  
  
  
  # Stan odtwarzacza
  playback_state <- reactiveValues(
    session_id = NULL,
    is_playing = FALSE,
    elapsed = 0,    # sekundy słuchania
    duration = 0,   # całkowity czas utworu
    track_name = ""
  )
  
  # Inicjalizacja danych
  
  observe({ 
    playlists_rv(db_get_playlists(con))
    library_rv(db_get_library_full(con))
    stats_all_rv(db_get_all_stats(con))  # NOWA LINIA
  })
  
  
  observe({ playlists_rv(db_get_playlists(con)) })
  
  get_selected_playlist_id <- function() {
    req(input$playlist_table_rows_selected)
    playlists_rv()$playlist_id[input$playlist_table_rows_selected]
  }
  
  output$playlist_table <- renderDT({
    datatable(playlists_rv(), selection = 'single', rownames = FALSE, 
              options = list(scrollX = TRUE, pageLength=5))
  })
  
  output$songs_table <- renderDT({
    req(songs_rv())
    datatable(songs_rv(), selection = 'single', rownames = FALSE,
              options = list(scrollX = TRUE, pageLength=5))
  })
  
  observe({ 
    playlists_rv(db_get_playlists(con))
    library_rv(db_get_library_full(con))
  })
  
  observeEvent(input$playlist_table_rows_selected, {
    songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
  })
  
  # --- DYNAMICZNE UI ---
  output$dynamic_songs_ui <- renderUI({
    req(input$playlist_table_rows_selected)
    
    tagList(
      fluidRow(
        column(4,
               wellPanel(
                 h4("Dodaj utwór"),
                 selectizeInput("song_v_id", "Wyszukaj utwór:", 
                                choices = c("Zacznij pisać..." = "", db_get_song_choices(con))),
                 # Zauważ: Brak numericInput dla pozycji!
                 actionButton("add_song_btn", "Dodaj na koniec", class = "btn-primary", width = "100%"),
                 actionButton("move_up", "Przesuń w górę", icon = icon("arrow-up")),
                 actionButton("move_down", "Przesuń w dół", icon = icon("arrow-down")),
                 hr(),
                 actionButton("remove_song_btn", "Usuń", icon = icon("trash"), class = "btn-danger"
                 )
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
  
  # Renderowanie dynamicznego UI dla wersji
  output$versions_management_ui <- renderUI({
    req(input$full_library_table_rows_selected)
    
    sel_song <- library_rv()[input$full_library_table_rows_selected, ]
    
    tagList(
      h3(paste("Wersje dla:", sel_song$title)),
      fluidRow(
        column(6,
               h4("Dodaj nową wersję"),
               wellPanel(
                 textInput("new_v_type", "Typ :", "Remix"),
                 numericInput("new_v_dur", "Czas (sekundy):", 220),
                 dateInput("new_v_date", "Data wersji:", value = Sys.Date()),
                 actionButton("save_version_btn", "Zapisz wersję", class = "btn-info", width = "100%")
               )
        ),
        column(6,
               h4("Lista wersji"),
               DTOutput("song_versions_table"),
               br(),
               actionButton("delete_version_btn", "Usuń wybraną wersję", class = "btn-warning")
        )
      )
    )
  })
  
  
  # --- LOGIKA ODTWARZACZA (TIMER) ---
  
  # Timer działający co sekundę, gdy muzyka gra
  observe({
    invalidateLater(1000, session)
    
    # Używamy isolate, aby timer nie reagował na każdą zmianę innych zmiennych
    if (playback_state$is_playing) {
      isolate({
        playback_state$elapsed <- playback_state$elapsed + 1
        
        # Jeśli utwór dobiegł końca (lub go przekroczył)
        if (playback_state$elapsed >= playback_state$duration) {
          # 1. Zapisujemy w bazie danych
          db_finish_playback(con, playback_state$session_id)
          stats_all_rv(db_get_all_stats(con))
          
          # 2. Resetujemy stan w R
          playback_state$is_playing <- FALSE
          playback_state$session_id <- NULL
          playback_state$elapsed <- 0
          
          showNotification("Utwór zakończony i zapisany", type = "message")
        }
      })
    }
  })
  
  # Renderowanie paska postępu
  output$playback_progress_ui <- renderUI({
    perc <- if(playback_state$duration > 0) (playback_state$elapsed / playback_state$duration) * 100 else 0
    tags$div(class = "progress",
             tags$div(class = "progress-bar progress-bar-striped active", 
                      role = "progressbar", 
                      style = paste0("width: ", perc, "%;"),
                      paste0(playback_state$elapsed, "s / ", playback_state$duration, "s")
             )
    )
  })
  
  output$current_track_label <- renderText({
    if (playback_state$track_name == "") "Wybierz utwór z listy"
    else paste("Teraz odtwarzane:", playback_state$track_name)
  })
  # Przekazanie stanu do UI (dla conditionalPanel)
  output$is_playing <- reactive({ playback_state$is_playing })
  outputOptions(output, "is_playing", suspendWhenHidden = FALSE)
  
  
  
  # --- OBSŁUGA PRZYCISKÓW ODTWARZACZA ---
  
  observeEvent(input$play_btn, {
    req(input$songs_table_rows_selected)
    
    # Jeśli startujemy nowy utwór (nie ma aktywnej sesji)
    if (is.null(playback_state$session_id)) {
      selected_row <- songs_rv()[input$songs_table_rows_selected, ]
      
      playback_state$session_id <- db_start_playback(con, selected_row$song_version_id)
      playback_state$duration <- selected_row$duration
      playback_state$elapsed <- 0
      playback_state$track_name <- selected_row$song_title
    }
    
    playback_state$is_playing <- TRUE
    showNotification("Odtwarzanie...", type = "message")
  })
  
  observeEvent(input$pause_btn, {
    req(playback_state$session_id)
    playback_state$is_playing <- FALSE
    db_pause_playback(con, playback_state$session_id)
    showNotification("Pauza", type = "warning")
  })
  # Przycisk STOP (też powinien używać finish_playback)
  observeEvent(input$stop_btn, {
    req(playback_state$session_id)
    
    db_finish_playback(con, playback_state$session_id)
    
    playback_state$is_playing <- FALSE
    playback_state$session_id <- NULL
    playback_state$elapsed <- 0
    showNotification("Zatrzymano i zapisano postęp", type = "default")
    stats_all_rv(db_get_all_stats(con)) 
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
  
  # Doaj piosenkę do playlisty
  observeEvent(input$add_song_btn, {
    req(input$song_v_id)
    tryCatch({
      db_add_song_auto(con, get_selected_playlist_id(), input$song_v_id)
      songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
      showNotification("Dodano na koniec listy", type = "message")
    }, error = function(e) { showNotification(e$message, type = "error") })
  })
  
  # Przesuwanie w górę
  observeEvent(input$move_up, {
    req(input$songs_table_rows_selected)
    current_pos <- songs_rv()$item_position[input$songs_table_rows_selected]
    
    if(current_pos > 1) {
      db_move_item(con, get_selected_playlist_id(), current_pos, current_pos - 1)
      songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
      # Automatyczne zaznaczenie wiersza po przesunięciu (opcjonalne)
      # selectRows(proxy, current_pos - 1)
    }
  })
  
  #  Przesuwanie w dół
  observeEvent(input$move_down, {
    req(input$songs_table_rows_selected)
    current_pos <- songs_rv()$item_position[input$songs_table_rows_selected]
    max_pos <- max(songs_rv()$item_position)
    
    if(current_pos < max_pos) {
      db_move_item(con, get_selected_playlist_id(), current_pos, current_pos + 1)
      songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
    }
  })
  
  
  # Usuń piosenkę z playlisty
  observeEvent(input$remove_song_btn, {
    req(input$songs_table_rows_selected)
    
    # Wyciągamy pozycję z tabeli songs_rv
    pos_to_del <- songs_rv()$item_position[input$songs_table_rows_selected]
    
    db_remove_song_from_playlist(con, get_selected_playlist_id(), pos_to_del)
    
    # Odświeżamy dane 
    songs_rv(db_get_playlist_items(con, get_selected_playlist_id()))
    showNotification("Utwór usunięty", type = "warning")
  })
  
  output$full_library_table <- renderDT({
    datatable(library_rv(), selection = 'single', rownames = FALSE)
  })
  
  # Dodawanie/usuwanie piosenek z bazy
  observeEvent(input$save_song_btn, {
    # Przetwarzanie stringów na wektory dla SQL ARRAY
    artists_vec <- trimws(unlist(strsplit(input$new_s_artists, ",")))
    genres_vec <- trimws(unlist(strsplit(input$new_s_genres, ",")))
    
    tryCatch({
      res <- db_add_song_full(
        con, artists_vec, input$new_s_title, input$new_s_album,
        input$new_s_lang, input$new_s_year, genres_vec,
        input$new_s_ver_type, input$new_s_duration, input$new_s_date
      )
      
      showNotification(paste("Sukces:", res[1,1]), type = "message")
      library_rv(db_get_library_full(con)) # Odśwież tabelę
      
      # Odśwież listę wyboru w zakładce playlist
      updateSelectizeInput(session, "song_v_id", choices = db_get_song_choices(con))
      
    }, error = function(e) {
      showNotification(paste("Błąd:", e$message), type = "error")
    })
  })
  
  observeEvent(input$delete_song_db_btn, {
    req(input$full_library_table_rows_selected)
    sid <- library_rv()$song_id[input$full_library_table_rows_selected]
    
    res <- db_delete_song_from_db(con, sid)
    showNotification(as.character(res[1,1]), type = "warning")
    
    library_rv(db_get_library_full(con))
    updateSelectizeInput(session, "song_v_id", choices = db_get_song_choices(con))
  })
  
  
  
  # Pobieranie wersji po kliknięciu w piosenkę
  observeEvent(input$full_library_table_rows_selected, {
    sid <- library_rv()$song_id[input$full_library_table_rows_selected]
    versions_rv(db_get_versions_by_sid(con, sid))
  })
  
  # Tabela wersji
  output$song_versions_table <- renderDT({
    req(versions_rv())
    datatable(versions_rv(), selection = 'single', rownames = FALSE, options = list(dom = 't'))
  })
  
  #  Dodawanie wersji
  observeEvent(input$save_version_btn, {
    req(input$full_library_table_rows_selected)
    sid <- library_rv()$song_id[input$full_library_table_rows_selected]
    
    tryCatch({
      res <- db_add_version(con, sid, input$new_v_type, input$new_v_dur, input$new_v_date)
      showNotification(as.character(res[1,1]), type = "message")
      
      # Odśwież widoki
      versions_rv(db_get_versions_by_sid(con, sid))
      updateSelectizeInput(session, "song_v_id", choices = db_get_song_choices(con))
    }, error = function(e) showNotification(e$message, type = "error"))
  })
  
  # Usuwanie wersji
  observeEvent(input$delete_version_btn, {
    req(input$song_versions_table_rows_selected)
    vid <- versions_rv()$song_version_id[input$song_versions_table_rows_selected]
    sid <- library_rv()$song_id[input$full_library_table_rows_selected]
    
    res <- db_delete_version_from_db(con, vid)
    showNotification(as.character(res[1,1]), type = "warning")
    
    
    # Odśwież widoki
    versions_rv(db_get_versions_by_sid(con, sid))
    updateSelectizeInput(session, "song_v_id", choices = db_get_song_choices(con))
  })
  
  
  
  # Pomocnicza funkcja dla modyfikacji
  to_na <- function(x) {
    if (is.null(x) || x == "") NA else x
  }
  
  # Modyfikacja piosenki
  observeEvent(input$modify_song_btn, {
    req(input$full_library_table_rows_selected)
    
    sid <- library_rv()$song_id[input$full_library_table_rows_selected]
    
    # Zamiana pustych stringów na NULL
    to_null <- function(x) if (is.null(x) || x == "") NULL else x
    
    tryCatch({
      res <- db_modify_song(
        con,
        sid,
        new_lang      = to_na(input$mod_lang),
        add_artist    = to_na(input$mod_add_artist),
        delete_artist = to_na(input$mod_del_artist),
        add_genre     = to_na(input$mod_add_genre),
        delete_genre  = to_na(input$mod_del_genre)
      )
      
      showNotification(as.character(res[1,1]), type = "message")
      
      # Odśwież bibliotekę + playlisty
      library_rv(db_get_library_full(con))
      updateSelectizeInput(session, "song_v_id",
                           choices = db_get_song_choices(con))
      
      # Wyczyść pola
      updateTextInput(session, "mod_lang", value = "")
      updateTextInput(session, "mod_add_artist", value = "")
      updateTextInput(session, "mod_del_artist", value = "")
      updateTextInput(session, "mod_add_genre", value = "")
      updateTextInput(session, "mod_del_genre", value = "")
      
    }, error = function(e) {
      showNotification(e$message, type = "error")
    })
  })
  # Renderowanie tabeli statystyk ogólnych
  output$stats_all_table <- renderTable({
    req(stats_all_rv())
    
    df <- stats_all_rv()
    data.frame(
      "Metryka" = c(
        "Najczęściej słuchana piosenka",
        "Najczęściej słuchana wersja",
        "Typ wersji",
        "Ulubiony gatunek",
        "Łączna liczba odtworzeń",
        "Piosenki wysłuchane do końca",
        "Łączny czas słuchania (minuty)"
      ),
      "Wartość" = c(
        df$most_listened_song,
        df$most_listened_version_title,
        df$most_listened_song_version,
        df$favourite_genre,
        as.character(df$total_playcount),
        as.character(df$songs_fully_played),
        as.character(df$total_minutes_listened)
      ),
      stringsAsFactors = FALSE
    )
  }, striped = TRUE, hover = TRUE, bordered = TRUE, width = "100%")
  
  # Pobieranie statystyk miesięcznych
  observeEvent(input$refresh_monthly_stats, {
    req(input$stats_date_range)
    
    tryCatch({
      stats_monthly_rv(
        db_get_monthly_stats(con, 
                             input$stats_date_range[1], 
                             input$stats_date_range[2])
      )
    }, error = function(e) {
      showNotification(paste("Błąd:", e$message), type = "error")
    })
  })
  
  # Renderowanie tabeli statystyk miesięcznych
  output$stats_monthly_table <- renderTable({
    req(stats_monthly_rv())
    
    df <- stats_monthly_rv()
    
    if(nrow(df) == 0 || is.na(df$most_listened_song[1])) {
      return(data.frame(
        "Info" = "Brak danych w wybranym okresie",
        stringsAsFactors = FALSE
      ))
    }
    
    data.frame(
      "Metryka" = c(
        "Najczęściej słuchana piosenka",
        "Najczęściej słuchana wersja",
        "Typ wersji",
        "Ulubiony gatunek",
        "Łączna liczba odtworzeń",
        "Piosenki wysłuchane do końca",
        "Łączny czas słuchania (minuty)"
      ),
      "Wartość" = c(
        df$most_listened_song,
        df$most_listened_version_title,
        df$most_listened_song_version,
        df$favourite_genre,
        as.character(df$total_playcount),
        as.character(df$songs_fully_played),
        as.character(df$total_minutes_listened)
      ),
      stringsAsFactors = FALSE
    )
  }, striped = TRUE, hover = TRUE, bordered = TRUE, width = "100%")
  
}

shinyApp(ui, server)

