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