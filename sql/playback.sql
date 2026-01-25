------------------ FUNKCJE DOT. ODTWARZANIA / SESJI ------------------
-- sluchanie 1 piosenki bez next (przed automatyzacja) (DO USUNIECIA!!!)
CREATE OR REPLACE FUNCTION play_song(svid INTEGER, sec INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO ListeningHistory
        (song_version_id, listened_at, listened_seconds, is_full_played)
    SELECT
        svid,
        now(),
        sec,
        sec >= duration * 0.8
    FROM SongVersions
    WHERE song_version_id = svid;
END;
$$;

-- Odtwarzanie - start
CREATE OR REPLACE FUNCTION start_playback(sv_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE sid INTEGER;
BEGIN
    INSERT INTO PlaybackSessions(song_version_id, started_at, last_update)
    VALUES (sv_id, now(), now())
    RETURNING session_id INTO sid;

    RETURN sid;
END;
$$;

-- Odtwarzanie - pauza/stop
CREATE OR REPLACE FUNCTION pause_playback(p_session_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE PlaybackSessions
    SET
        listened_seconds = listened_seconds
            + EXTRACT(EPOCH FROM (now() - last_update))::INTEGER,
        last_update = now(),
        is_active = FALSE
    WHERE session_id = p_session_id;
END;
$$;

-- Odtwarzanie - zakonczenie
CREATE OR REPLACE FUNCTION finish_playback(p_session_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    sv_id INTEGER;
    sec INTEGER;
    dur INTEGER;
BEGIN
    SELECT ps.song_version_id, ps.listened_seconds, sv.duration
    INTO sv_id, sec, dur
    FROM PlaybackSessions ps
    JOIN SongVersions sv USING(song_version_id)
    WHERE ps.session_id = p_session_id;

    INSERT INTO ListeningHistory(song_version_id, listened_at, listened_seconds, is_full_played)
    VALUES (sv_id, now(), sec, sec >= dur * 0.8);

    DELETE FROM PlaybackSessions WHERE session_id = p_session_id;
END;

$$;

-- Nowa zakończenie odtwarzania
CREATE OR REPLACE FUNCTION finish_playback(p_session_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
  DECLARE
v_sv_id INTEGER;
v_total_sec INTEGER;
v_dur INTEGER;
v_session_active BOOLEAN;
v_already_listened INTEGER;
v_last_upd TIMESTAMPTZ;
BEGIN
-- Pobieramy dane sesji
SELECT song_version_id, listened_seconds, last_update, is_active
INTO v_sv_id, v_already_listened, v_last_upd, v_session_active
FROM PlaybackSessions WHERE session_id = p_session_id;

IF NOT FOUND THEN RETURN; END IF;

-- Pobieramy długość utworu
SELECT duration INTO v_dur FROM SongVersions WHERE song_version_id = v_sv_id;

-- OBLICZANIE CZASU:
  -- Jeśli sesja jest aktywna, dodajemy różnicę czasu od ostatniego update'u do teraz
    IF v_session_active THEN
        v_total_sec := v_already_listened + EXTRACT(EPOCH FROM (now() - v_last_upd))::INTEGER;
    ELSE
        v_total_sec := v_already_listened;
    END IF;

    -- Zabezpieczenie: nie możemy słuchać dłużej niż trwa utwór (np. przez błędy systemowe)
    IF v_total_sec > v_dur THEN v_total_sec := v_dur; END IF;

    -- Zapis do historii
    INSERT INTO ListeningHistory(song_version_id, listened_at, listened_seconds, is_full_played)
    VALUES (v_sv_id, now(), v_total_sec, v_total_sec >= v_dur * 0.8);

    -- Usuwamy sesję
    DELETE FROM PlaybackSessions WHERE session_id = p_session_id;
END;
$$;
